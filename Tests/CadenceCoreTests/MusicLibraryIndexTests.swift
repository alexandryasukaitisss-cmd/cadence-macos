import XCTest
@testable import CadenceCore

final class MusicLibraryIndexTests: XCTestCase {
    private func track(
        id: Int,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval = 180,
        trackNumber: Int = 1
    ) -> MusicTrack {
        MusicTrack(
            id: id,
            persistentID: "pid-\(id)",
            title: title,
            artist: artist,
            album: album,
            albumArtist: artist,
            duration: duration,
            trackNumber: trackNumber,
            discNumber: 1,
            year: 2026,
            genre: "Pop",
            playedCount: 0,
            favorited: false,
            cloudStatus: "subscription",
            kind: "AAC",
            dateAdded: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + id)),
            playedDate: nil
        )
    }

    func testAlbumsAndPlaylistResolution() throws {
        let tracks = [
            track(id: 1, title: "Alpha", artist: "Artist", album: "Album", trackNumber: 1),
            track(id: 2, title: "Beta", artist: "Artist", album: "Album", trackNumber: 2),
            track(id: 3, title: "Gamma", artist: "Other", album: "Second", trackNumber: 1)
        ]
        let playlist = MusicPlaylist(name: "Favourite Songs", trackCount: 2, trackIDs: [3, 1])
        let index = MusicLibraryIndex(
            snapshot: MusicLibrarySnapshot(tracks: tracks, playlists: [playlist])
        )

        XCTAssertEqual(index.albums.count, 2)
        XCTAssertEqual(index.artists.count, 2)
        XCTAssertEqual(index.userPlaylists.count, 1)
        XCTAssertEqual(index.tracks(in: playlist).map(\.id), [3, 1])
        let secondAlbum = try XCTUnwrap(index.albums.first { $0.title == "Second" })
        XCTAssertEqual(index.tracks(in: secondAlbum).map(\.id), [3])
    }

    func testSearchFindsTrackByTitleAndArtist() {
        let tracks = [
            track(id: 1, title: "Go Easy", artist: "Dua Lipa", album: "Radical Optimism"),
            track(id: 2, title: "Love Again", artist: "Dua Lipa", album: "Future Nostalgia")
        ]
        let index = MusicLibraryIndex(
            snapshot: MusicLibrarySnapshot(tracks: tracks, playlists: [])
        )

        let byTitle = index.search("go eas")
        XCTAssertEqual(byTitle.first, .track(tracks[0]))

        let byArtist = index.search("dua")
        let trackResults = byArtist.filter {
            if case .track = $0 { return true }
            return false
        }
        XCTAssertEqual(trackResults.count, 2)
    }
}
