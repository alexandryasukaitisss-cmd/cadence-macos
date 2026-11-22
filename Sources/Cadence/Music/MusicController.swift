import AppKit
import CadenceCore
import Combine
import Foundation

struct MusicPlaybackState: Equatable, Sendable {
    var hasTrack: Bool
    var isPlaying: Bool
    var isPaused: Bool
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var persistentID: String
    var databaseID: Int
    var volume: Double
    var shuffle: Bool
    var repeatMode: String
    var favorited: Bool
    var albumArtist: String

    static let idle = MusicPlaybackState(
        hasTrack: false,
        isPlaying: false,
        isPaused: false,
        title: "",
        artist: "",
        album: "",
        duration: 0,
        position: 0,
        persistentID: "",
        databaseID: 0,
        volume: 0.7,
        shuffle: false,
        repeatMode: "off",
        favorited: false,
        albumArtist: ""
    )

    var displayTitle: String {
        title.isEmpty ? "Music" : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Apple Music" : artist
    }

    var artworkKey: String {
        let albumName = album.isEmpty ? title : album
        let artistName = albumArtist.isEmpty ? artist : albumArtist
        return MusicText.normalized(albumName) + "\u{1F}" + MusicText.normalized(artistName)
    }
}

struct MusicScriptError: Error, Sendable {
    let code: Int
    let message: String

    var isNotAuthorized: Bool { code == -1743 }
    var isNotRunning: Bool { code == -600 }

    var localizedDescription: String {
        if isNotAuthorized {
            return "Нет доступа к Music. Разрешите управление в «Системные настройки → Конфиденциальность и безопасность → Автоматизация»."
        }
        if isNotRunning {
            return "Music не запущен."
        }
        return message
    }
}

/// Serial AppleScript bridge for playback and now-playing polling.
/// All NSAppleScript objects live and execute on one private queue.
final class MusicScriptRunner {
    private let queue = DispatchQueue(label: "com.cadence.music.applescript", qos: .userInitiated)
    private var pollScript: NSAppleScript?

    private static let pollSource = """
    tell application "Music"
      set isPlaying to (player state is playing)
      set isPaused to (player state is paused)
      set vol to sound volume
      set shuf to shuffle enabled
      set rep to song repeat as text
      try
        set t to current track
        set hasTrack to true
        set nm to name of t
        set ar to artist of t
        set al to album of t
      on error
        set hasTrack to false
        set nm to ""
        set ar to ""
        set al to ""
      end try
      if hasTrack then
        try
          set dur to duration of t
        on error
          set dur to 0
        end try
        try
          set pos to player position
        on error
          set pos to 0
        end try
        try
          set pid to persistent ID of t
        on error
          set pid to ""
        end try
        try
          set dbid to database ID of t
        on error
          set dbid to 0
        end try
        try
          set fav to favorited of t
        on error
          set fav to false
        end try
        try
          set aa to album artist of t
        on error
          set aa to ""
        end try
      else
        set dur to 0
        set pos to 0
        set pid to ""
        set dbid to 0
        set fav to false
        set aa to ""
      end if
      return {hasTrack, isPlaying, isPaused, nm, ar, al, dur, pos, pid, dbid, vol, shuf, rep, fav, aa}
    end tell
    """

    func poll(completion: @escaping (Result<MusicPlaybackState, MusicScriptError>) -> Void) {
        queue.async {
            if self.pollScript == nil {
                self.pollScript = NSAppleScript(source: Self.pollSource)
            }
            guard let script = self.pollScript else {
                completion(.failure(MusicScriptError(code: -1, message: "Не удалось скомпилировать AppleScript.")))
                return
            }
            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if let error {
                completion(.failure(Self.mapError(error)))
                return
            }
            do {
                let state = try Self.parsePoll(descriptor)
                completion(.success(state))
            } catch let error as MusicScriptError {
                completion(.failure(error))
            } catch {
                completion(.failure(MusicScriptError(code: -1, message: error.localizedDescription)))
            }
        }
    }

    func run(_ source: String, completion: ((Result<Void, MusicScriptError>) -> Void)? = nil) {
        queue.async {
            guard let script = NSAppleScript(source: source) else {
                completion?(.failure(MusicScriptError(code: -1, message: "Не удалось скомпилировать AppleScript.")))
                return
            }
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            if let error {
                completion?(.failure(Self.mapError(error)))
            } else {
                completion?(.success(()))
            }
        }
    }

    private static func mapError(_ error: NSDictionary) -> MusicScriptError {
        let code = error["NSAppleScriptErrorNumber"] as? Int ?? -1
        let message = error["NSAppleScriptErrorMessage"] as? String ?? "Неизвестная ошибка Music."
        return MusicScriptError(code: code, message: message)
    }

    private static func parsePoll(_ descriptor: NSAppleEventDescriptor) throws -> MusicPlaybackState {
        func bool(_ index: Int) -> Bool {
            descriptor.atIndex(index)?.booleanValue ?? false
        }
        func text(_ index: Int) -> String {
            descriptor.atIndex(index)?.stringValue ?? ""
        }
        func number(_ index: Int) -> Double {
            descriptor.atIndex(index)?.doubleValue ?? 0
        }
        func integer(_ index: Int) -> Int {
            Int(descriptor.atIndex(index)?.int32Value ?? 0)
        }

        guard descriptor.numberOfItems >= 15 else {
            throw MusicScriptError(code: -1, message: "Music вернул неполное состояние плеера.")
        }

        return MusicPlaybackState(
            hasTrack: bool(1),
            isPlaying: bool(2),
            isPaused: bool(3),
            title: text(4),
            artist: text(5),
            album: text(6),
            duration: number(7),
            position: number(8),
            persistentID: text(9),
            databaseID: integer(10),
            volume: max(0, min(1, number(11) / 100.0)),
            shuffle: bool(12),
            repeatMode: text(13).lowercased(),
            favorited: bool(14),
            albumArtist: text(15)
        )
    }
}

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var state: MusicPlaybackState = .idle
    @Published private(set) var permissionDenied = false
    @Published private(set) var lastError: String?
    @Published private(set) var isCommandInFlight = false

    var onStateChange: ((MusicPlaybackState) -> Void)?

    private let runner = MusicScriptRunner()
    private var timer: Timer?
    private var isPolling = false
    private var pollInFlight = false
    private var started = false
    private var permissionBlockedUntil: Date?

    /// Called when a multi-track selection falls back to a single track.
    var onNotice: ((String) -> Void)?

    init() {
        state = .idle
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        if started {
            pollIfPossible()
            return
        }
        started = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollIfPossible()
            }
        }
        timer?.tolerance = 0.2
        pollIfPossible()
    }

    /// Retries after the user grants Automation in System Settings.
    func requestAccess() {
        permissionDenied = false
        permissionBlockedUntil = nil
        start()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
    }

    var isPlaying: Bool { state.isPlaying }

    private var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    private func pollIfPossible() {
        if let permissionBlockedUntil, Date() < permissionBlockedUntil {
            return
        }
        guard !pollInFlight else { return }
        guard isMusicRunning else {
            if state != .idle {
                state = .idle
                onStateChange?(state)
            }
            return
        }
        pollInFlight = true
        runner.poll { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.pollInFlight = false
                switch result {
                case let .success(state):
                    self.permissionDenied = false
                    self.permissionBlockedUntil = nil
                    self.lastError = nil
                    let changed = state != self.state
                    self.state = state
                    if changed {
                        self.onStateChange?(state)
                    }
                case let .failure(error):
                    if error.isNotAuthorized {
                        self.permissionDenied = true
                        self.permissionBlockedUntil = Date().addingTimeInterval(30)
                    }
                    if error.isNotRunning {
                        self.state = .idle
                        self.onStateChange?(self.state)
                    } else if !error.isNotAuthorized {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    func refreshNow() {
        permissionBlockedUntil = nil
        pollIfPossible()
    }

    // MARK: - Playback commands

    func play(track: MusicTrack) {
        ensureMusicRunning { [weak self] running in
            guard let self, running else { return }
            self.run("""
            tell application "Music"
              play (\(self.trackSelector(track)))
            end tell
            """)
            self.scheduleRefresh()
        }
    }

    /// Cadence no longer writes to the user's Music playlists. A multi-track
    /// selection starts with its first track; continuous album/shuffle playback
    /// stays a Music.app feature.
    func play(queue tracks: [MusicTrack], shuffle: Bool? = nil) {
        guard let first = tracks.first else { return }
        onNotice?("Cadence играет первый трек. Альбом целиком и перемешивание — в Music.")
        play(track: first)
    }

    func playLibrary(shuffle: Bool? = nil) {
        ensureMusicRunning { [weak self] running in
            guard let self, running else { return }
            let shuffleLine: String
            if let shuffle {
                shuffleLine = "set shuffle enabled to \(shuffle ? "true" : "false")"
            } else {
                shuffleLine = ""
            }
            self.run("""
            tell application "Music"
              \(shuffleLine)
              play library playlist 1
            end tell
            """)
            self.scheduleRefresh()
        }
    }

    func reveal(track: MusicTrack) {
        ensureMusicRunning { [weak self] running in
            guard let self, running else { return }
            self.run("""
            tell application "Music"
              activate
              try
                reveal (\(self.trackSelector(track)))
              end try
            end tell
            """)
        }
    }

    func play(playlistID: String) {
        ensureMusicRunning { [weak self] running in
            guard let self, running else { return }
            let id = self.appleScriptLiteral(playlistID)
            self.run("""
            tell application "Music"
              play (first user playlist whose persistent ID is "\(id)")
            end tell
            """)
            self.scheduleRefresh()
        }
    }

    private func appleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Prefer the stable persistent ID. A cached database ID can point at a
    /// different track after Music rebuilds its library.
    private func trackSelector(_ track: MusicTrack) -> String {
        if track.persistentID.isEmpty {
            return "first track of library playlist 1 whose database ID is \(track.id)"
        }
        return "first track of library playlist 1 whose persistent ID is \"\(appleScriptLiteral(track.persistentID))\""
    }

    func toggle() {
        ensureMusicRunning { [weak self] running in
            guard let self, running else { return }
            self.run("""
            tell application "Music"
              playpause
            end tell
            """)
            self.scheduleRefresh()
        }
    }

    func pause() {
        guard state.isPlaying else { return }
        runner.run("""
        tell application "Music"
          pause
        end tell
        """)
        scheduleRefresh()
    }

    func next() {
        runner.run("""
        tell application "Music"
          next track
        end tell
        """)
        scheduleRefresh()
    }

    func previous() {
        if state.position > 3.0 {
            seek(to: 0)
            return
        }
        runner.run("""
        tell application "Music"
          previous track
        end tell
        """)
        scheduleRefresh()
    }

    func seek(to position: TimeInterval) {
        let clamped = max(0, min(position, max(0, state.duration - 0.2)))
        runner.run("""
        tell application "Music"
          set player position to \(clamped)
        end tell
        """)
        var optimistic = state
        optimistic.position = clamped
        state = optimistic
        onStateChange?(state)
    }

    func setVolume(_ volume: Double) {
        let clamped = max(0, min(1, volume))
        var optimistic = state
        optimistic.volume = clamped
        state = optimistic
        onStateChange?(state)
        runner.run("""
        tell application "Music"
          set sound volume to \(Int((clamped * 100).rounded()))
        end tell
        """)
    }

    func toggleShuffle() {
        let nextValue = !state.shuffle
        var optimistic = state
        optimistic.shuffle = nextValue
        state = optimistic
        onStateChange?(state)
        runner.run("""
        tell application "Music"
          set shuffle enabled to \(nextValue ? "true" : "false")
        end tell
        """)
        scheduleRefresh()
    }

    func cycleRepeat() {
        let nextMode: String
        switch state.repeatMode {
        case "off": nextMode = "all"
        case "all": nextMode = "one"
        default: nextMode = "off"
        }
        runner.run("""
        tell application "Music"
          set song repeat to \(nextMode)
        end tell
        """)
        var optimistic = state
        optimistic.repeatMode = nextMode
        state = optimistic
        onStateChange?(state)
        scheduleRefresh(delay: 0.25)
    }

    func toggleFavorite() {
        guard state.hasTrack else { return }
        let nextValue = !state.favorited
        var optimistic = state
        optimistic.favorited = nextValue
        state = optimistic
        onStateChange?(state)
        runner.run("""
        tell application "Music"
          set favorited of current track to \(nextValue ? "true" : "false")
        end tell
        """)
        scheduleRefresh()
    }

    func revealCurrentTrack() {
        runner.run("""
        tell application "Music"
          activate
          try
            reveal current track
          end try
        end tell
        """)
    }

    // MARK: - Helpers

    private func scheduleRefresh(delay: TimeInterval = 0.15) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollIfPossible()
        }
    }

    private func ensureMusicRunning(completion: @escaping (Bool) -> Void) {
        if isMusicRunning {
            completion(true)
            return
        }
        let url = URL(fileURLWithPath: "/System/Applications/Music.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }
                if let error {
                    self.lastError = error.localizedDescription
                    completion(false)
                    return
                }
                self.permissionDenied = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    completion(app != nil)
                }
            }
        }
    }

    private func run(_ source: String) {
        isCommandInFlight = true
        runner.run(source) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isCommandInFlight = false
                switch result {
                case .success:
                    self.permissionDenied = false
                case let .failure(error):
                    if error.isNotAuthorized {
                        self.permissionDenied = true
                        self.permissionBlockedUntil = Date().addingTimeInterval(30)
                    } else {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
    }
}
