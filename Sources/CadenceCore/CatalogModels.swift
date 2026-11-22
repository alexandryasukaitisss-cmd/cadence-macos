import Foundation

public struct CatalogItem: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case song
        case album
        case podcast
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let artist: String
    public let collectionName: String?
    public let artworkURL: URL?
    public let viewURL: URL?
    public let previewURL: URL?
    public let releaseDate: Date?
    public let trackCount: Int?

    public init(
        id: String,
        kind: Kind,
        title: String,
        artist: String,
        collectionName: String? = nil,
        artworkURL: URL? = nil,
        viewURL: URL? = nil,
        previewURL: URL? = nil,
        releaseDate: Date? = nil,
        trackCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.artist = artist
        self.collectionName = collectionName
        self.artworkURL = artworkURL
        self.viewURL = viewURL
        self.previewURL = previewURL
        self.releaseDate = releaseDate
        self.trackCount = trackCount
    }

    public var largeArtworkURL: URL? {
        guard let artworkURL else { return nil }
        let string = artworkURL.absoluteString
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "60x60bb", with: "600x600bb")
        return URL(string: string)
    }
}

public enum CatalogSearchError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Каталог Apple вернул некорректный ответ."
        case let .httpStatus(code): return "Каталог Apple вернул HTTP \(code)."
        case let .decoding(message): return "Не удалось разобрать ответ каталога: \(message)"
        }
    }
}

public protocol CatalogDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionCatalogLoader: CatalogDataLoading {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public protocol CatalogSearching: AnyObject {
    func searchMusic(term: String, limit: Int) async throws -> [CatalogItem]
    func searchPodcasts(term: String, limit: Int) async throws -> [CatalogItem]
}
