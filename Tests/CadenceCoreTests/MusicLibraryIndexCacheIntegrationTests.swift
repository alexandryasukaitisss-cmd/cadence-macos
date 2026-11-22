import XCTest
@testable import CadenceCore

/// Loads a fixture snapshot through the real cache file and runs the index
/// over it, checking that caching does not disturb albums, playlists, or search.
final class MusicLibraryIndexCacheIntegrationTests: XCTestCase {
    private func track(
        id: Int,
        title: String,
        artist: String,
        album: String,
        trackNumber: Int = 1,
        favorited: Bool = false,
        playedCount: Int = 0
    ) -> MusicTrack {
        MusicTrack(
            id: id,
            persistentID: String(format: "%08X", id),
            title: title,
            artist: artist,
            album: album,
            albumArtist: artist,
            duration: 180,
            trackNumber: trackNumber,
            discNumber: 1,
            year: 2026,
            genre: "Pop",
            playedCount: playedCount,
            favorited: favorited,
            cloudStatus: "subscription",
            kind: "AAC",
            dateAdded: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + id)),
            playedDate: nil
        )
    }

    func testIndexSurvivesCacheRoundTrip() throws {
        let tracks = [
            track(id: 1, title: "Alpha", artist: "Artist X", album: "Debut", trackNumber: 2, favorited: true, playedCount: 9),
            track(id: 2, title: "Beta", artist: "Artist X", album: "Debut", trackNumber: 1),
            track(id: 3, title: "Gamma", artist: "Artist Y", album: "Second", trackNumber: 1),
            track(id: 4, title: "Delta", artist: "Artist Y", album: "", trackNumber: 0)
        ]
        let playlists = [
            MusicPlaylist(name: "Library", trackCount: 4, specialKind: "Library", isFolder: false, trackIDs: [1, 2, 3, 4]),
            MusicPlaylist(name: "Папка", trackCount: 0, specialKind: "folder", isFolder: true, trackIDs: []),
            MusicPlaylist(name: "Road", trackCount: 2, specialKind: "none", isFolder: false, trackIDs: [3, 1])
        ]
        let snapshot = MusicLibrarySnapshot(
            tracks: tracks,
            playlists: playlists,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            musicVersion: "1.5.7"
        )

        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceIndexTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let cache = MusicLibraryCache(url: cacheURL)
        try cache.write(snapshot)

        let loaded = try XCTUnwrap(cache.read())
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.musicVersion, "1.5.7")
        let index = MusicLibraryIndex(snapshot: loaded)

        // "Debut" keeps track-number order, "Second" has one track, and the
        // album-less track forms no album.
        XCTAssertEqual(index.albums.count, 2)
        let debut = try XCTUnwrap(index.albums.first { $0.title == "Debut" })
        XCTAssertEqual(debut.artist, "Artist X")
        XCTAssertEqual(debut.tracks.map(\.id), [2, 1])
        XCTAssertEqual(debut.playedCount, 9)

        XCTAssertEqual(index.artists.count, 2)

        // The Library special playlist and the folder are filtered out of
        // user playlists; the user playlist's track order survives the cache.
        XCTAssertEqual(index.userPlaylists.map(\.name), ["Road"])
        let road = try XCTUnwrap(index.userPlaylists.first)
        XCTAssertEqual(road.trackIDs, [3, 1])
        XCTAssertEqual(index.tracks(in: road).map(\.id), [3, 1])

        XCTAssertEqual(index.favoriteTracks.map(\.id), [1])
        XCTAssertEqual(index.frequentlyPlayed.first?.id, 1)

        let searchResults = index.search("beta")
        XCTAssertEqual(searchResults.first, .track(tracks[1]))
    }
}
