import XCTest
@testable import CadenceCore

final class CatalogSearchServiceTests: XCTestCase {
    // MARK: - Fixtures

    private var songFixture: Data {
        Data(
            """
            {
              "resultCount": 2,
              "results": [
                {
                  "wrapperType": "track",
                  "kind": "song",
                  "trackId": 1440926883,
                  "trackName": "Go Easy",
                  "artistName": "Dua Lipa",
                  "collectionName": "Radical Optimism",
                  "collectionId": 1440926870,
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/song-100x100bb.jpg",
                  "trackViewUrl": "https://music.apple.com/album/1440926870?i=1440926883",
                  "previewUrl": "https://is1-ssl.mzstatic.com/audio/preview.m4a",
                  "releaseDate": "2024-05-03T07:00:00Z"
                },
                {
                  "wrapperType": "track",
                  "kind": "music-video",
                  "trackId": 777,
                  "trackName": "Video",
                  "artistName": "Someone"
                }
              ]
            }
            """.utf8
        )
    }

    private var albumFixture: Data {
        Data(
            """
            {
              "resultCount": 1,
              "results": [
                {
                  "wrapperType": "collection",
                  "collectionType": "Album",
                  "collectionId": 1440926870,
                  "collectionName": "Radical Optimism",
                  "artistName": "Dua Lipa",
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/album-100x100bb.jpg",
                  "collectionViewUrl": "https://music.apple.com/album/1440926870",
                  "releaseDate": "2024-05-03T07:00:00Z",
                  "trackCount": 11
                }
              ]
            }
            """.utf8
        )
    }

    private var podcastFixture: Data {
        Data(
            """
            {
              "resultCount": 2,
              "results": [
                {
                  "wrapperType": "track",
                  "kind": "podcast",
                  "trackId": 120034348,
                  "collectionId": 120034348,
                  "collectionName": "The Daily",
                  "artistName": "The New York Times",
                  "artworkUrl600": "https://is1-ssl.mzstatic.com/image/thumb/daily-600x600bb.jpg",
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/daily-100x100bb.jpg",
                  "collectionViewUrl": "https://podcasts.apple.com/podcast/the-daily/id120034348",
                  "releaseDate": "2026-01-05T05:00:00Z",
                  "trackCount": 999
                },
                {
                  "wrapperType": "track",
                  "kind": "podcast",
                  "trackId": 998877,
                  "collectionId": 998877,
                  "trackName": "Minimal Cast",
                  "artistName": "Minimal Media",
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/minimal-100x100bb.jpg",
                  "trackViewUrl": "https://podcasts.apple.com/podcast/minimal/id998877"
                }
              ]
            }
            """.utf8
        )
    }

    private static let emptyFixture = Data(#"{"resultCount":0,"results":[]}"#.utf8)

    /// Serves fixture JSON by the request's `entity` parameter, the way the real
    /// API serves a different result set per entity. No network is involved.
    private final class MockCatalogLoader: CatalogDataLoading, @unchecked Sendable {
        private let lock = NSLock()
        private let dataByEntity: [String: Data]
        private let response: URLResponse
        private var capturedRequests: [URLRequest] = []

        init(dataByEntity: [String: Data], response: URLResponse) {
            self.dataByEntity = dataByEntity
            self.response = response
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return capturedRequests
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.lock()
            capturedRequests.append(request)
            lock.unlock()

            let entity = request.url.flatMap { url in
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first { $0.name == "entity" }?
                    .value
            }
            let data = dataByEntity[entity ?? ""] ?? CatalogSearchServiceTests.emptyFixture
            return (data, response)
        }
    }

    /// The service and its mock loader, so tests can inspect captured requests.
    private func makeService(
        dataByEntity: [String: Data] = [:],
        status: Int = 200,
        response: URLResponse? = nil,
        country: String = "pl"
    ) throws -> (service: CatalogSearchService, loader: MockCatalogLoader) {
        let urlResponse: URLResponse
        if let response {
            urlResponse = response
        } else {
            urlResponse = try XCTUnwrap(
                HTTPURLResponse(
                    url: URL(string: "https://itunes.apple.com/search")!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
        }
        let loader = MockCatalogLoader(dataByEntity: dataByEntity, response: urlResponse)
        let service = CatalogSearchService(loader: loader, country: country)
        return (service, loader)
    }

    private func isoDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private func queryValues(of request: URLRequest) throws -> [String: String] {
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: - Mapping

    func testSearchMusicMapsSongFieldsAndSkipsVideos() async throws {
        let (service, loader) = try makeService(dataByEntity: ["song": songFixture])

        let items = try await service.searchMusic(term: "go easy", limit: 10)

        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(items.count, 1)
        let song = try XCTUnwrap(items.first)
        XCTAssertEqual(song.kind, .song)
        XCTAssertEqual(song.id, "1440926883")
        XCTAssertEqual(song.title, "Go Easy")
        XCTAssertEqual(song.artist, "Dua Lipa")
        XCTAssertEqual(song.collectionName, "Radical Optimism")
        XCTAssertEqual(song.artworkURL?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/song-100x100bb.jpg")
        XCTAssertEqual(song.largeArtworkURL?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/song-600x600bb.jpg")
        XCTAssertEqual(song.viewURL?.absoluteString, "https://music.apple.com/album/1440926870?i=1440926883")
        XCTAssertEqual(song.previewURL?.absoluteString, "https://is1-ssl.mzstatic.com/audio/preview.m4a")
        XCTAssertEqual(song.releaseDate, isoDate("2024-05-03T07:00:00Z"))
        XCTAssertNil(song.trackCount)
    }

    func testSearchPodcastsMapsPodcastFields() async throws {
        let (service, _) = try makeService(dataByEntity: ["podcast": podcastFixture])

        let items = try await service.searchPodcasts(term: "daily", limit: 15)

        XCTAssertEqual(items.count, 2)
        let daily = try XCTUnwrap(items.first { $0.title == "The Daily" })
        XCTAssertEqual(daily.kind, .podcast)
        XCTAssertEqual(daily.id, "120034348")
        XCTAssertEqual(daily.artist, "The New York Times")
        XCTAssertEqual(daily.artworkURL?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/daily-600x600bb.jpg")
        XCTAssertEqual(daily.viewURL?.absoluteString, "https://podcasts.apple.com/podcast/the-daily/id120034348")
        XCTAssertNil(daily.previewURL)
        XCTAssertEqual(daily.releaseDate, isoDate("2026-01-05T05:00:00Z"))
        XCTAssertEqual(daily.trackCount, 999)

        // The minimal entry falls back to artworkUrl100 and trackViewUrl.
        let minimal = try XCTUnwrap(items.first { $0.title == "Minimal Cast" })
        XCTAssertEqual(minimal.artworkURL?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/minimal-100x100bb.jpg")
        XCTAssertEqual(minimal.viewURL?.absoluteString, "https://podcasts.apple.com/podcast/minimal/id998877")
        XCTAssertNil(minimal.releaseDate)
        XCTAssertNil(minimal.trackCount)
    }

    func testSearchAlbumsMapsAlbumFields() async throws {
        let (service, _) = try makeService(dataByEntity: ["album": albumFixture])

        let items = try await service.searchAlbums(term: "radical", limit: 5)

        XCTAssertEqual(items.count, 1)
        let album = try XCTUnwrap(items.first)
        XCTAssertEqual(album.kind, .album)
        XCTAssertEqual(album.id, "1440926870")
        XCTAssertEqual(album.title, "Radical Optimism")
        XCTAssertEqual(album.artist, "Dua Lipa")
        XCTAssertEqual(album.largeArtworkURL?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/album-600x600bb.jpg")
        XCTAssertEqual(album.viewURL?.absoluteString, "https://music.apple.com/album/1440926870")
        XCTAssertNil(album.previewURL)
        XCTAssertEqual(album.releaseDate, isoDate("2024-05-03T07:00:00Z"))
        XCTAssertEqual(album.trackCount, 11)
    }

    // MARK: - Request encoding

    func testRequestEncodingAndParameters() async throws {
        let (service, loader) = try makeService(dataByEntity: ["song": songFixture], country: "us")

        _ = try await service.searchMusic(term: "Дуа Липа & Friends", limit: 7)

        let request = try XCTUnwrap(loader.requests.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(url.path, "/search")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

        let values = try queryValues(of: request)
        XCTAssertEqual(values["term"], "Дуа Липа & Friends")
        XCTAssertEqual(values["media"], "music")
        XCTAssertEqual(values["entity"], "song")
        XCTAssertEqual(values["limit"], "7")
        XCTAssertEqual(values["country"], "us")
        // Non-ASCII and reserved characters must be percent-encoded on the wire.
        XCTAssertTrue(url.absoluteString.contains("%D0%94"))
        XCTAssertTrue(url.absoluteString.contains("%26"))
    }

    func testPodcastRequestUsesPodcastEntityAndDefaults() async throws {
        let (service, loader) = try makeService(dataByEntity: ["podcast": podcastFixture])

        _ = try await service.searchPodcasts(term: "daily")

        let request = try XCTUnwrap(loader.requests.first)
        let values = try queryValues(of: request)
        XCTAssertEqual(values["media"], "podcast")
        XCTAssertEqual(values["entity"], "podcast")
        XCTAssertEqual(values["limit"], "20")
        XCTAssertEqual(values["country"], "pl")
    }

    // MARK: - Errors

    func testHTTPStatusThrows() async throws {
        let (service, _) = try makeService(status: 403)

        do {
            _ = try await service.searchMusic(term: "x")
            XCTFail("Expected httpStatus error")
        } catch let error as CatalogSearchError {
            guard case let .httpStatus(code) = error else { return XCTFail("Wrong error: \(error)") }
            XCTAssertEqual(code, 403)
        }
    }

    func testNonHTTPResponseThrowsInvalidResponse() async throws {
        let plain = URLResponse(
            url: URL(string: "https://itunes.apple.com/search")!,
            mimeType: nil,
            expectedContentLength: -1,
            textEncodingName: nil
        )
        let (service, _) = try makeService(response: plain)

        do {
            _ = try await service.searchPodcasts(term: "x")
            XCTFail("Expected invalidResponse error")
        } catch let error as CatalogSearchError {
            guard case .invalidResponse = error else { return XCTFail("Wrong error: \(error)") }
        }
    }

    func testMalformedJSONThrowsDecoding() async throws {
        let (service, _) = try makeService(dataByEntity: ["song": Data("{ not json".utf8)])

        do {
            _ = try await service.searchMusic(term: "x")
            XCTFail("Expected decoding error")
        } catch let error as CatalogSearchError {
            guard case let .decoding(message) = error else { return XCTFail("Wrong error: \(error)") }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testEmptyCatalogResponseDecodesToEmptyList() async throws {
        let (service, _) = try makeService()

        let items = try await service.searchMusic(term: "nothing")

        XCTAssertTrue(items.isEmpty)
    }
}
