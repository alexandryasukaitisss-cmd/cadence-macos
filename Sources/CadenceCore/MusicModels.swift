import Foundation

/// A stable, normalized view of one track in the user's Music library.
public struct MusicTrack: Codable, Hashable, Identifiable, Sendable {
    /// The Music.app database ID. Used to address the track through AppleScript.
    public let id: Int
    public let persistentID: String
    public let title: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let duration: TimeInterval
    public let trackNumber: Int
    public let discNumber: Int
    public let year: Int
    public let genre: String
    public let playedCount: Int
    public let favorited: Bool
    public let cloudStatus: String
    public let kind: String
    public let dateAdded: Date?
    public let playedDate: Date?

    public init(
        id: Int,
        persistentID: String,
        title: String,
        artist: String,
        album: String,
        albumArtist: String,
        duration: TimeInterval,
        trackNumber: Int = 0,
        discNumber: Int = 0,
        year: Int = 0,
        genre: String = "",
        playedCount: Int = 0,
        favorited: Bool = false,
        cloudStatus: String = "",
        kind: String = "",
        dateAdded: Date? = nil,
        playedDate: Date? = nil
    ) {
        self.id = id
        self.persistentID = persistentID
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.duration = duration
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.playedCount = playedCount
        self.favorited = favorited
        self.cloudStatus = cloudStatus
        self.kind = kind
        self.dateAdded = dateAdded
        self.playedDate = playedDate
    }

    public var displayArtist: String {
        artist.isEmpty ? albumArtist : artist
    }

    public var displayAlbum: String {
        album.isEmpty ? "Сингл" : album
    }

    public var albumKey: String {
        let albumName = album.isEmpty ? title : album
        let artistName = albumArtist.isEmpty ? artist : albumArtist
        return MusicText.normalized(albumName) + "\u{1F}" + MusicText.normalized(artistName)
    }

    public var artworkKey: String {
        albumKey
    }

    public var isMissing: Bool {
        let status = cloudStatus.lowercased()
        return status.contains("no longer") || status.contains("removed") || status.contains("error")
    }
}

public struct MusicPlaylist: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let persistentID: String
    public let name: String
    public let trackCount: Int
    public let specialKind: String
    public let isFolder: Bool
    public let trackIDs: [Int]

    public init(
        id: String? = nil,
        persistentID: String = "",
        name: String,
        trackCount: Int,
        specialKind: String = "none",
        isFolder: Bool = false,
        trackIDs: [Int] = []
    ) {
        self.persistentID = persistentID
        self.id = id ?? (persistentID.isEmpty ? MusicText.normalized(name) : persistentID)
        self.name = name
        self.trackCount = trackCount
        self.specialKind = specialKind
        self.isFolder = isFolder
        self.trackIDs = trackIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, persistentID, name, trackCount, specialKind, isFolder, trackIDs
    }

    /// Older caches stored playlists without a persistent ID. Decode them with
    /// an empty ID instead of discarding the whole library snapshot.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            persistentID: try container.decodeIfPresent(String.self, forKey: .persistentID) ?? "",
            name: try container.decode(String.self, forKey: .name),
            trackCount: try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0,
            specialKind: try container.decodeIfPresent(String.self, forKey: .specialKind) ?? "none",
            isFolder: try container.decodeIfPresent(Bool.self, forKey: .isFolder) ?? false,
            trackIDs: try container.decodeIfPresent([Int].self, forKey: .trackIDs) ?? []
        )
    }

    public var isLibrary: Bool {
        specialKind.caseInsensitiveCompare("Library") == .orderedSame
    }

    public var isMusic: Bool {
        specialKind.caseInsensitiveCompare("Music") == .orderedSame
    }

    public var isFavoriteSongs: Bool {
        name.caseInsensitiveCompare("Favourite Songs") == .orderedSame
            || name.caseInsensitiveCompare("Favorite Songs") == .orderedSame
            || name.caseInsensitiveCompare("Любимые песни") == .orderedSame
    }
}

public struct MusicLibrarySnapshot: Codable, Hashable, Sendable {
    public let tracks: [MusicTrack]
    public let playlists: [MusicPlaylist]
    public let fetchedAt: Date
    public let musicVersion: String?

    public init(tracks: [MusicTrack], playlists: [MusicPlaylist], fetchedAt: Date = Date(), musicVersion: String? = nil) {
        self.tracks = tracks
        self.playlists = playlists
        self.fetchedAt = fetchedAt
        self.musicVersion = musicVersion
    }
}

public struct MusicLibraryLoadResult: Sendable {
    public let snapshot: MusicLibrarySnapshot
    public let isStale: Bool
    public let warning: String?

    public init(snapshot: MusicLibrarySnapshot, isStale: Bool, warning: String? = nil) {
        self.snapshot = snapshot
        self.isStale = isStale
        self.warning = warning
    }
}

public enum MusicLibraryError: LocalizedError, Sendable {
    case musicNotRunning
    case notAuthorized
    case appleScript(code: Int, message: String)
    case cacheUnavailable

    public var errorDescription: String? {
        switch self {
        case .musicNotRunning:
            return "Music не запущен."
        case .notAuthorized:
            return "Нет доступа к Music. Разрешите управление в «Системные настройки → Конфиденциальность и безопасность → Автоматизация»."
        case let .appleScript(code, message):
            return "Music вернул ошибку \(code): \(message)"
        case .cacheUnavailable:
            return "Не удалось прочитать кэш медиатеки."
        }
    }
}

public protocol MusicLibraryProviding: AnyObject {
    func loadLibrary() async throws -> MusicLibraryLoadResult
}

public protocol MusicArtworkProviding: AnyObject {
    /// Returns JPEG/PNG data for the track artwork, or nil when the track has no artwork.
    func artworkData(for trackID: Int) async throws -> Data?
}

public enum MusicText {
    public static func folded(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }

    public static func normalized(_ value: String) -> String {
        folded(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func tokens(_ value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
