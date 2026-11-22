import AppKit
import Foundation

/// Loads the user's Music.app library through AppleScript.
///
/// The library is read with a single script that fetches every field of every
/// track as a parallel property list, so 1,000 tracks cost one AppleScript
/// execution rather than one round trip per track. Scripts always run on a
/// private serial queue, and a previously cached snapshot is served with a
/// warning whenever a fresh load fails. The service is read-only: it never
/// modifies the Music library.
///
/// The class is `@unchecked Sendable` because all stored state is immutable
/// and script execution is confined to a serial queue.
public final class AppleScriptMusicLibraryService: MusicLibraryProviding, @unchecked Sendable {
    private static let musicBundleIdentifier = "com.apple.Music"
    /// How long to wait for Music to finish launching before querying it.
    private static let launchTimeout: TimeInterval = 5
    /// Poll interval while waiting for Music to launch.
    private static let launchPollInterval: UInt64 = 250_000_000

    private let cache: MusicLibraryCache?
    private let launchesMusicIfNeeded: Bool
    private let scriptQueue: DispatchQueue

    /// - Parameters:
    ///   - cache: Snapshot cache served with `isStale == true` when a fresh load fails.
    ///   - launchMusicIfNeeded: When true, Music is launched in the background if it is not running.
    public init(cache: MusicLibraryCache? = nil, launchMusicIfNeeded: Bool = true) {
        self.cache = cache
        self.launchesMusicIfNeeded = launchMusicIfNeeded
        self.scriptQueue = DispatchQueue(label: "Cadence.AppleScriptMusicLibraryService")
    }

    public func loadLibrary() async throws -> MusicLibraryLoadResult {
        try await loadLibrary(launchMusicIfNeeded: nil)
    }

    /// `launchMusicIfNeeded` overrides the instance default. The app uses
    /// `false` on startup so opening Cadence does not launch Music; an explicit
    /// Play/Connect passes `true`.
    public func loadLibrary(launchMusicIfNeeded: Bool?) async throws -> MusicLibraryLoadResult {
        do {
            let fresh = try await fetchFreshSnapshot(launchMusicIfNeeded: launchMusicIfNeeded ?? launchesMusicIfNeeded)
            var snapshot = fresh.snapshot
            var warning = fresh.warning
            if fresh.playlistFailed,
               let cached = cache?.read(),
               !cached.playlists.isEmpty {
                snapshot = MusicLibrarySnapshot(
                    tracks: snapshot.tracks,
                    playlists: cached.playlists,
                    fetchedAt: snapshot.fetchedAt,
                    musicVersion: snapshot.musicVersion
                )
                warning = "Плейлисты Music не обновились — показаны сохранённые плейлисты. Причина: \(warning ?? "неизвестна")"
            }
            if let cache {
                // A failing cache write must not fail an otherwise successful load.
                try? cache.write(snapshot)
            }
            return MusicLibraryLoadResult(snapshot: snapshot, isStale: false, warning: warning)
        } catch {
            // Cancellation should surface, not silently serve stale data.
            if error is CancellationError { throw error }
            if let cache, let cachedSnapshot = cache.read() {
                let warning = "Не удалось обновить медиатеку Music — показаны сохранённые данные. Причина: \(error.localizedDescription)"
                return MusicLibraryLoadResult(snapshot: cachedSnapshot, isStale: true, warning: warning)
            }
            throw error
        }
    }

    // MARK: - Fresh load

    private func fetchFreshSnapshot(launchMusicIfNeeded: Bool) async throws -> (snapshot: MusicLibrarySnapshot, warning: String?, playlistFailed: Bool) {
        try await ensureMusicIsRunning(allowLaunch: launchMusicIfNeeded)

        let metadataRoot = try await AppleScriptRunner.run(Self.trackMetadataScript, on: scriptQueue)
        // A valid empty library still returns all 18 columns. A shorter root
        // means a malformed/partial response, not a library with zero tracks.
        guard metadataRoot.numberOfItems >= 18 else {
            throw MusicLibraryError.appleScript(
                code: -1,
                message: "Music вернул неполный список треков; сохранён предыдущий кэш."
            )
        }
        let metadata = MusicLibraryAppleScriptParser.trackMetadata(from: metadataRoot)

        // Playlist metadata is best effort: the song list must load even when
        // one odd playlist makes the second script fail. The warning makes the
        // degradation visible to the UI instead of silent.
        var playlists: [MusicPlaylist] = []
        var playlistWarning: String?
        var playlistFailed = false
        do {
            let playlistRoot = try await AppleScriptRunner.run(Self.playlistScript, on: scriptQueue)
            playlists = MusicLibraryAppleScriptParser.playlists(from: playlistRoot)
        } catch {
            playlistFailed = true
            playlistWarning = "Не удалось загрузить плейлисты Music — показаны только песни. Причина: \(error.localizedDescription)"
        }

        // A successful script can still return an empty list when Music or the
        // bridge degraded. Do not overwrite a non-empty cached playlist set
        // without showing that the refresh was degraded.
        if !playlistFailed,
           playlists.isEmpty,
           !metadata.tracks.isEmpty,
           let cached = cache?.read(),
           !cached.playlists.isEmpty {
            playlistFailed = true
            playlistWarning = "Music вернул пустой список плейлистов — показаны сохранённые плейлисты. Причина: неполный ответ Music."
        }

        let snapshot = MusicLibrarySnapshot(
            tracks: metadata.tracks,
            playlists: playlists,
            fetchedAt: Date(),
            musicVersion: metadata.musicVersion
        )
        return (snapshot, playlistWarning, playlistFailed)
    }

    // MARK: - Music launch

    private func ensureMusicIsRunning(allowLaunch: Bool) async throws {
        if Self.isMusicRunning { return }
        guard allowLaunch else { throw MusicLibraryError.musicNotRunning }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.musicBundleIdentifier) else {
            throw MusicLibraryError.musicNotRunning
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
        } catch {
            throw MusicLibraryError.musicNotRunning
        }

        // Give Music up to 5 seconds to finish launching before querying it.
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while !Self.isMusicRunning {
            guard Date() < deadline else { throw MusicLibraryError.musicNotRunning }
            try await Task.sleep(nanoseconds: Self.launchPollInterval)
        }
    }

    private static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleIdentifier).isEmpty
    }

    // MARK: - Scripts

    /// One AppleScript round trip: every field of every library track comes
    /// back as a parallel list, plus Music's version. Both date fetches are
    /// wrapped in `try`, and single tracks may return `missing value` for a
    /// date: neither may fail the load. Dates cross the bridge as Music
    /// long-date-time descriptors, which the parser reads back exactly.
    /// Column variables must not be Music dictionary terms: `names`,
    /// `artists`, and `albums` are enumerators of Music's search-area
    /// enumeration (macOS 27 dictionary), and `set names to …` refuses to
    /// compile with error -10003.
    private static let trackMetadataScript = """
        tell application "Music"
            set lib to library playlist 1
            set ids to database ID of every track of lib
            set pids to persistent ID of every track of lib
            set trackNames to name of every track of lib
            set trackArtists to artist of every track of lib
            set trackAlbums to album of every track of lib
            set albumArtists to album artist of every track of lib
            set durations to duration of every track of lib
            set trackNumbers to track number of every track of lib
            set discNumbers to disc number of every track of lib
            set years to year of every track of lib
            set genres to genre of every track of lib
            set playedCounts to played count of every track of lib
            set favoritedFlags to favorited of every track of lib
            set cloudStatuses to cloud status of every track of lib
            set kinds to kind of every track of lib
            set addedDates to {}
            set playedDates to {}
            try
                set addedDates to date added of every track of lib
            end try
            try
                set playedDates to played date of every track of lib
            end try
            set appVersion to missing value
            try
                set appVersion to version
            end try
            return {ids, pids, trackNames, trackArtists, trackAlbums, albumArtists, durations, trackNumbers, discNumbers, years, genres, playedCounts, favoritedFlags, cloudStatuses, kinds, addedDates, playedDates, appVersion}
        end tell
        """

    /// Second round trip: playlist metadata. Folders and the Library/Music
    /// special playlists return only a track count; their track ID lists stay
    /// empty because the IDs would just duplicate the whole library. Every
    /// per-playlist statement is wrapped in `try` so one odd playlist cannot
    /// fail the rest.
    private static let playlistScript = """
        tell application "Music"
            set output to {}
            set allPlaylists to every playlist
            repeat with p in allPlaylists
                set pName to ""
                try
                    set pName to name of p
                end try
                set pKind to "none"
                try
                    set pKind to (special kind of p) as text
                end try
                set pIsFolder to (pKind is "folder")
                set pCount to 0
                set pIDs to {}
                set pPID to ""
                try
                    set pPID to persistent ID of p
                end try
                if pIsFolder or pKind is "Music" or pKind is "Library" then
                    try
                        set pCount to count of tracks of p
                    end try
                else
                    try
                        set pIDs to database ID of every track of p
                        set pCount to count of pIDs
                    end try
                end if
                set end of output to {pName, pCount, pKind, pIsFolder, pIDs, pPID}
            end repeat
            return output
        end tell
        """
}
