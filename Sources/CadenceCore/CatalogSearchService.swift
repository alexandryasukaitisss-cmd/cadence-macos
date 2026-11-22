import Foundation

/// Searches the Apple iTunes catalog (songs, podcasts, albums) through an
/// injectable loader so tests run on fixture JSON and never touch the network.
public final class CatalogSearchService: CatalogSearching {
    /// The iTunes Search API rejects limits outside 1...200.
    private static let maximumLimit = 200

    private let loader: CatalogDataLoading
    private let country: String

    /// - Parameters:
    ///   - loader: Performs the HTTP request; inject fixtures in tests.
    ///   - country: Two-letter iTunes storefront code.
    public init(loader: CatalogDataLoading = URLSessionCatalogLoader(), country: String = "pl") {
        self.loader = loader
        self.country = country
    }

    public func searchMusic(term: String, limit: Int = 20) async throws -> [CatalogItem] {
        try await search(term: term, media: "music", entity: "song", limit: limit)
    }

    public func searchPodcasts(term: String, limit: Int = 20) async throws -> [CatalogItem] {
        try await search(term: term, media: "podcast", entity: "podcast", limit: limit)
    }

    /// Not part of `CatalogSearching`, but the mapping is needed for album artwork lookups.
    public func searchAlbums(term: String, limit: Int = 20) async throws -> [CatalogItem] {
        try await search(term: term, media: "music", entity: "album", limit: limit)
    }

    private func search(term: String, media: String, entity: String, limit: Int) async throws -> [CatalogItem] {
        let clampedLimit = min(max(limit, 1), Self.maximumLimit)
        guard let url = Self.makeURL(term: term, media: media, entity: entity, limit: clampedLimit, country: country) else {
            throw CatalogSearchError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await loader.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogSearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CatalogSearchError.httpStatus(http.statusCode) }

        let decoded: CatalogSearchResponse
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoded = try decoder.decode(CatalogSearchResponse.self, from: data)
        } catch {
            throw CatalogSearchError.decoding(error.localizedDescription)
        }
        return decoded.results.compactMap(Self.item(from:))
    }

    /// Visible for tests: term and country go through `URLComponents`, which
    /// percent-encodes both.
    static func makeURL(term: String, media: String, entity: String, limit: Int, country: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: media),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]
        return components.url
    }

    // MARK: - Response decoding

    private struct CatalogSearchResponse: Decodable {
        var resultCount: Int
        var results: [CatalogResult]
    }

    private struct CatalogResult: Decodable {
        var wrapperType: String?
        var kind: String?
        var trackId: Int?
        var collectionId: Int?
        var trackName: String?
        var collectionName: String?
        var artistName: String?
        var artworkUrl100: String?
        var artworkUrl600: String?
        var trackViewUrl: String?
        var collectionViewUrl: String?
        var previewUrl: String?
        var releaseDate: Date?
        var trackCount: Int?

        /// iTunes IDs are per-entity integers; the string form is stable enough for `Identifiable`.
        var identifier: String? {
            if let trackId { return String(trackId) }
            if let collectionId { return String(collectionId) }
            return nil
        }

        func url(_ string: String?) -> URL? {
            string.flatMap(URL.init(string:))
        }

        func firstURL(_ candidates: [String?]) -> URL? {
            for candidate in candidates {
                if let url = url(candidate) { return url }
            }
            return nil
        }
    }

    /// Classifies one result: songs and podcasts by `kind`, albums by `wrapperType`.
    /// Anything else (music videos, episodes) is skipped.
    private static func item(from result: CatalogResult) -> CatalogItem? {
        guard let id = result.identifier else { return nil }
        switch result.kind ?? "" {
        case "song":
            return CatalogItem(
                id: id,
                kind: .song,
                title: result.trackName ?? "",
                artist: result.artistName ?? "",
                collectionName: result.collectionName,
                artworkURL: result.firstURL([result.artworkUrl100, result.artworkUrl600]),
                viewURL: result.url(result.trackViewUrl),
                previewURL: result.url(result.previewUrl),
                releaseDate: result.releaseDate,
                trackCount: nil
            )
        case "podcast":
            return CatalogItem(
                id: id,
                kind: .podcast,
                title: result.collectionName ?? result.trackName ?? "",
                artist: result.artistName ?? "",
                collectionName: nil,
                artworkURL: result.firstURL([result.artworkUrl600, result.artworkUrl100]),
                viewURL: result.firstURL([result.collectionViewUrl, result.trackViewUrl]),
                previewURL: nil,
                releaseDate: result.releaseDate,
                trackCount: result.trackCount
            )
        default:
            guard result.wrapperType == "collection" else { return nil }
            return CatalogItem(
                id: id,
                kind: .album,
                title: result.collectionName ?? "",
                artist: result.artistName ?? "",
                collectionName: nil,
                artworkURL: result.firstURL([result.artworkUrl100, result.artworkUrl600]),
                viewURL: result.url(result.collectionViewUrl),
                previewURL: nil,
                releaseDate: result.releaseDate,
                trackCount: result.trackCount
            )
        }
    }
}
