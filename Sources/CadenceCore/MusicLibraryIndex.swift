import Foundation

public struct MusicAlbum: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let year: Int
    public let tracks: [MusicTrack]
    public let dateAdded: Date?
    public let playedCount: Int

    public var trackCount: Int { tracks.count }
    public var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
    public var artworkTrackID: Int? { tracks.first?.id }
    public var isSingle: Bool { tracks.count <= 2 }
}

public struct MusicArtist: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let albums: [MusicAlbum]
    public let tracks: [MusicTrack]

    public var trackCount: Int { tracks.count }
    public var albumCount: Int { albums.count }
}

public enum MusicSearchResult: Identifiable, Hashable, Sendable {
    case track(MusicTrack)
    case album(MusicAlbum)
    case artist(MusicArtist)
    case playlist(MusicPlaylist)

    public var id: String {
        switch self {
        case let .track(track): return "track-\(track.id)"
        case let .album(album): return "album-\(album.id)"
        case let .artist(artist): return "artist-\(artist.id)"
        case let .playlist(playlist): return "playlist-\(playlist.id)"
        }
    }
}

/// In-memory, fast index over a Music library snapshot.
/// All grouping and searching happens on the main actor after the snapshot is loaded.
public struct MusicLibraryIndex: Sendable {
    public let snapshot: MusicLibrarySnapshot
    public let songs: [MusicTrack]
    public let albums: [MusicAlbum]
    public let artists: [MusicArtist]
    public let userPlaylists: [MusicPlaylist]
    public let favoriteTracks: [MusicTrack]
    public let frequentlyPlayed: [MusicTrack]
    public let recentlyAddedAlbums: [MusicAlbum]
    public let recentlyPlayedTracks: [MusicTrack]
    public let totalDuration: TimeInterval

    private let tracksByID: [Int: MusicTrack]
    private let albumsByKey: [String: MusicAlbum]

    public init(snapshot: MusicLibrarySnapshot) {
        let songs = snapshot.tracks.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        var grouped: [String: [MusicTrack]] = [:]
        for track in snapshot.tracks where !track.album.isEmpty {
            grouped[track.albumKey, default: []].append(track)
        }
        let albumsByKey: [String: MusicAlbum] = grouped.mapValues { tracks in
            let sorted = tracks.sorted { lhs, rhs in
                if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
                if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            let first = sorted[0]
            let title = sorted.map(\.album).max { $0.count < $1.count } ?? first.album
            let artist = sorted
                .map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist }
                .max { $0.count < $1.count } ?? first.displayArtist
            let year = sorted.map(\.year).max() ?? 0
            let added = sorted.compactMap(\.dateAdded).max()
            return MusicAlbum(
                id: first.albumKey,
                title: title,
                artist: artist,
                year: year,
                tracks: sorted,
                dateAdded: added,
                playedCount: sorted.reduce(0) { $0 + $1.playedCount }
            )
        }
        let albums = albumsByKey.values.sorted {
            if $0.artist.localizedStandardCompare($1.artist) != .orderedSame {
                return $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        var artistGroups: [String: [MusicTrack]] = [:]
        for track in snapshot.tracks {
            let name = track.displayArtist
            guard !name.isEmpty else { continue }
            artistGroups[name, default: []].append(track)
        }
        let artists = artistGroups.map { name, tracks in
            let keys = Set(tracks.map(\.albumKey))
            let artistAlbums = keys.compactMap { albumsByKey[$0] }.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return MusicArtist(
                id: MusicText.normalized(name),
                name: name,
                albums: artistAlbums,
                tracks: tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let playlists = snapshot.playlists
            .filter { !$0.isFolder && !$0.isLibrary && !$0.isMusic && $0.trackCount > 0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let tracksByID = Dictionary(
            snapshot.tracks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let favoriteTracks = songs.filter(\.favorited)
        let frequentlyPlayed = snapshot.tracks
            .filter { $0.playedCount > 0 }
            .sorted { $0.playedCount > $1.playedCount }
            .prefix(20)
            .map { $0 }
        let recentlyAddedAlbums: [MusicAlbum]
        let datedAlbums = albums.filter { $0.dateAdded != nil }
        if datedAlbums.count >= 4 {
            recentlyAddedAlbums = datedAlbums.sorted {
                ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
            }
        } else {
            var seen = Set<String>()
            var result: [MusicAlbum] = []
            for track in snapshot.tracks.reversed() where !track.album.isEmpty {
                guard seen.insert(track.albumKey).inserted else { continue }
                if let album = albumsByKey[track.albumKey] {
                    result.append(album)
                }
                if result.count == 12 { break }
            }
            recentlyAddedAlbums = result
        }
        let recentlyPlayedTracks: [MusicTrack]
        let datedTracks = snapshot.tracks.filter { $0.playedDate != nil }
        if datedTracks.isEmpty {
            recentlyPlayedTracks = frequentlyPlayed
        } else {
            recentlyPlayedTracks = Array(
                datedTracks.sorted {
                    ($0.playedDate ?? .distantPast) > ($1.playedDate ?? .distantPast)
                }.prefix(20)
            )
        }
        let totalDuration = snapshot.tracks.reduce(0) { $0 + $1.duration }

        self.snapshot = snapshot
        self.songs = songs
        self.albums = albums
        self.albumsByKey = albumsByKey
        self.artists = artists
        self.userPlaylists = playlists
        self.favoriteTracks = favoriteTracks
        self.frequentlyPlayed = frequentlyPlayed
        self.recentlyAddedAlbums = recentlyAddedAlbums
        self.recentlyPlayedTracks = recentlyPlayedTracks
        self.totalDuration = totalDuration
        self.tracksByID = tracksByID
    }

    public func album(forKey key: String) -> MusicAlbum? {
        albumsByKey[key]
    }

    public func artist(named name: String) -> MusicArtist? {
        let normalized = MusicText.normalized(name)
        return artists.first { $0.id == normalized }
    }

    public func tracks(in album: MusicAlbum) -> [MusicTrack] {
        album.tracks
    }

    public func tracks(in playlist: MusicPlaylist) -> [MusicTrack] {
        let byID = playlist.trackIDs.compactMap { tracksByID[$0] }
        if !byID.isEmpty || playlist.trackIDs.isEmpty {
            return byID
        }
        return []
    }

    public func playlist(named name: String) -> MusicPlaylist? {
        let normalized = MusicText.normalized(name)
        return userPlaylists.first { MusicText.normalized($0.name) == normalized }
    }

    public func search(_ query: String, limit: Int = 40) -> [MusicSearchResult] {
        let normalized = MusicText.normalized(query)
        guard normalized.count >= 1 else { return [] }
        let queryTokens = MusicText.tokens(normalized)

        func matchesAllTokens(_ haystack: String) -> Bool {
            let folded = MusicText.normalized(haystack)
            return queryTokens.allSatisfy { folded.contains($0) }
        }

        func score(title: String, secondary: String, tertiary: String = "") -> Double {
            let titleText = MusicText.normalized(title)
            let secondaryText = MusicText.normalized(secondary)
            let tertiaryText = MusicText.normalized(tertiary)

            var value = 0.0
            if titleText == normalized { value += 1000 }
            else if titleText.hasPrefix(normalized) { value += 720 }
            else if titleText.contains(normalized) { value += 520 }
            if secondaryText == normalized { value += 500 }
            else if secondaryText.hasPrefix(normalized) { value += 380 }
            else if secondaryText.contains(normalized) { value += 260 }
            if tertiaryText.contains(normalized) { value += 140 }

            for token in queryTokens {
                if titleText.hasPrefix(token) { value += 80 }
                else if titleText.contains(token) { value += 50 }
                if secondaryText.contains(token) { value += 30 }
            }
            if value == 0 && !matchesAllTokens(title + " " + secondary + " " + tertiary) {
                return 0
            }
            // Prefer tight matches when scores are otherwise close.
            value += max(0, 24 - Double(titleText.count)) * 0.2
            return value
        }

        let trackResults = songs.compactMap { track -> (MusicTrack, Double)? in
            let value = score(title: track.title, secondary: track.displayArtist, tertiary: track.album)
            return value > 0 ? (track, value) : nil
        }.sorted { $0.1 > $1.1 }.prefix(12).map { MusicSearchResult.track($0.0) }

        let albumResults = albums.compactMap { album -> (MusicAlbum, Double)? in
            let value = score(title: album.title, secondary: album.artist)
            return value > 0 ? (album, value) : nil
        }.sorted { $0.1 > $1.1 }.prefix(8).map { MusicSearchResult.album($0.0) }

        let artistResults = artists.compactMap { artist -> (MusicArtist, Double)? in
            let value = score(title: artist.name, secondary: "")
            return value > 0 ? (artist, value) : nil
        }.sorted { $0.1 > $1.1 }.prefix(6).map { MusicSearchResult.artist($0.0) }

        let playlistResults = userPlaylists.compactMap { playlist -> (MusicPlaylist, Double)? in
            let value = score(title: playlist.name, secondary: "")
            return value > 0 ? (playlist, value) : nil
        }.sorted { $0.1 > $1.1 }.prefix(4).map { MusicSearchResult.playlist($0.0) }

        let combined = trackResults + albumResults + artistResults + playlistResults
        return Array(combined.prefix(limit))
    }
}

public extension TimeInterval {
    var musicDurationText: String {
        guard isFinite, self > 0 else { return "--:--" }
        let total = Int(self.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
