import XCTest
@testable import CadenceCore

final class MusicLibraryCacheTests: XCTestCase {
    /// Points into a directory that does not exist yet.
    private func makeCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceCacheTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    private func makeSnapshot(fetchedAt: Date = Date(timeIntervalSince1970: 1_700_001_000)) -> MusicLibrarySnapshot {
        MusicLibrarySnapshot(
            tracks: [
                MusicTrack(
                    id: 7,
                    persistentID: "A1B2C3D4E5F6A7B8",
                    title: "Песня",
                    artist: "Артист",
                    album: "Альбом",
                    albumArtist: "Артист",
                    duration: 123.5,
                    trackNumber: 3,
                    discNumber: 1,
                    year: 2026,
                    genre: "Pop",
                    playedCount: 2,
                    favorited: true,
                    cloudStatus: "subscription",
                    kind: "AAC",
                    dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
                    playedDate: Date(timeIntervalSince1970: 1_700_000_950)
                )
            ],
            playlists: [
                MusicPlaylist(name: "Слушать", trackCount: 1, specialKind: "none", isFolder: false, trackIDs: [7])
            ],
            fetchedAt: fetchedAt,
            musicVersion: "1.5"
        )
    }

    func testMissingCacheReturnsNil() {
        let cache = MusicLibraryCache(url: makeCacheURL())
        XCTAssertNil(cache.read())
    }

    func testRoundTripCreatesParentDirectories() throws {
        let url = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let cache = MusicLibraryCache(url: url)
        let snapshot = makeSnapshot()
        try cache.write(snapshot)

        // The parent directory did not exist before the write.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        let loaded = try XCTUnwrap(cache.read())
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.tracks.first?.dateAdded, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(loaded.tracks.first?.playedDate, Date(timeIntervalSince1970: 1_700_000_950))
    }

    func testOverwriteReplacesSnapshot() throws {
        let url = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let cache = MusicLibraryCache(url: url)
        try cache.write(makeSnapshot())
        try cache.write(MusicLibrarySnapshot(tracks: [], playlists: [], fetchedAt: Date(timeIntervalSince1970: 1_700_002_000)))

        let loaded = try XCTUnwrap(cache.read())
        XCTAssertTrue(loaded.tracks.isEmpty)
        XCTAssertTrue(loaded.playlists.isEmpty)
        XCTAssertEqual(loaded.fetchedAt, Date(timeIntervalSince1970: 1_700_002_000))
        XCTAssertNil(loaded.musicVersion)
    }

    func testOldPlaylistJSONWithoutPersistentIDStillDecodes() throws {
        let data = Data(#"{"id":"road","name":"Road","trackCount":1,"specialKind":"none","isFolder":false,"trackIDs":[7]}"#.utf8)
        let playlist = try JSONDecoder().decode(MusicPlaylist.self, from: data)
        XCTAssertEqual(playlist.persistentID, "")
        XCTAssertEqual(playlist.id, "road")
    }

    func testCorruptCacheReturnsNil() throws {
        let url = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("definitely not json".utf8).write(to: url)

        XCTAssertNil(MusicLibraryCache(url: url).read())
    }

    func testEmptyFileReturnsNil() throws {
        let url = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)

        XCTAssertNil(MusicLibraryCache(url: url).read())
    }

    /// One writer and many readers may use the same cache instance at once;
    /// every read must still return a complete snapshot.
    func testConcurrentReadsAndWritesNeverCorrupt() throws {
        let url = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let cache = MusicLibraryCache(url: url)
        try cache.write(makeSnapshot())

        let group = DispatchGroup()
        let queue = DispatchQueue.global()
        for _ in 0..<20 {
            group.enter()
            queue.async {
                XCTAssertNotNil(cache.read())
                group.leave()
            }
        }
        for _ in 0..<5 {
            group.enter()
            queue.async {
                try? cache.write(MusicLibrarySnapshot(tracks: [], playlists: [], fetchedAt: Date(timeIntervalSince1970: 1_700_000_001)))
                group.leave()
            }
        }
        group.wait()

        XCTAssertNotNil(cache.read())
    }
}
