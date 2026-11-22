import AppKit
import CadenceCore
import Combine
import Foundation
import SwiftUI

enum MusicDestination: Hashable {
    case home
    case songs
    case albums
    case artists
    case playlists
    case album(String)
    case artist(String)
    case playlist(String)
}

enum LibraryStatus: Equatable {
    case idle
    case loading
    case ready
    case stale
    case error
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var source: PlaybackSource = .music
    @Published var musicDestination: MusicDestination = .home
    @Published var showSidebar = true
    @Published var isPalettePresented = false
    @Published var searchText = ""
    @Published var searchFocusToken = 0
    @Published var library: MusicLibraryIndex?
    @Published var libraryStatus: LibraryStatus = .idle
    @Published var libraryError: String?
    @Published var libraryWarning: String?
    @Published var isRefreshingLibrary = false
    @Published var lastLibraryRefresh: Date?
    @Published var showOnboarding = false
    @Published var showMiniPlayer = false
    @Published var wantsMusic = false
    @Published var musicAccessGranted = false
    @Published var catalogItems: [CatalogItem] = []
    @Published var catalogQuery: String?
    @Published var isCatalogLoading = false
    @Published var catalogError: String?
    @Published var showCatalog = false
    @Published var toast: ToastMessage?

    let music: MusicController
    let playback: PlaybackCoordinator
    let artwork: ArtworkStore
    let catalog: CatalogSearchService
    let catalogCountry: String
    let libraryService: AppleScriptMusicLibraryService
    let cache: MusicLibraryCache

    private var miniPlayerWindow: MiniPlayerWindowController?
    private var didBootstrap = false
    private var cancellables = Set<AnyCancellable>()
    private var hasSeenOnboarding = false

    var musicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }

    init() {
        let cacheURL = Self.defaultCacheURL()
        let cache = MusicLibraryCache(url: cacheURL)
        self.cache = cache
        self.libraryService = AppleScriptMusicLibraryService(cache: cache, launchMusicIfNeeded: false)
        let artwork = ArtworkStore()
        artwork.configure(service: AppleScriptMusicArtworkService())
        self.artwork = artwork
        let catalogCountry = Locale.current.region?.identifier.lowercased() ?? "us"
        self.catalogCountry = catalogCountry
        self.catalog = CatalogSearchService(country: catalogCountry)
        self.music = MusicController()
        self.playback = PlaybackCoordinator(artwork: artwork)
        self.playback.connect(music: music)

        let defaults = UserDefaults.standard
        let legacySeen = defaults.object(forKey: "hasCompletedOnboarding") as? Bool
        let seen = defaults.object(forKey: "hasSeenOnboarding") as? Bool ?? legacySeen ?? false
        self.hasSeenOnboarding = seen
        self.wantsMusic = defaults.object(forKey: "wantsMusic") as? Bool ?? seen
        self.musicAccessGranted = defaults.object(forKey: "musicAccessGranted") as? Bool ?? false

        music.onStateChange = { [weak self] state in
            guard let self else { return }
            if state.hasTrack {
                self.markMusicGranted(true)
            }
            self.playback.ingestMusic(state)
        }
        music.onNotice = { [weak self] message in
            Task { @MainActor in self?.showToast(message) }
        }
        music.$permissionDenied
            .sink { [weak self] denied in
                guard denied else { return }
                Task { @MainActor in
                    self?.markMusicGranted(false)
                    self?.music.stop()
                }
            }
            .store(in: &cancellables)
        playback.onRequestSource = { [weak self] source in
            self?.selectSource(source)
        }
    }

    static func defaultCacheURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("Cadence", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        DebugSupport.log("AppModel.bootstrap cache=\(cache.read() != nil)")

        if let cached = cache.read() {
            apply(snapshot: cached, stale: true, warning: nil)
        }

        if DebugSupport.skipOnboarding {
            hasSeenOnboarding = true
        }
        if !hasSeenOnboarding {
            showOnboarding = true
        } else if wantsMusic, musicAccessGranted, !DebugSupport.disableMusicAutomation {
            music.start()
            // Opening Cadence must not launch Music. Refresh the library only
            // if Music is already running; otherwise the cache is enough.
            if musicIsRunning {
                Task { await refreshLibrary(launchMusic: false) }
            }
        }

        if DebugSupport.showPaletteAtLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.isPalettePresented = true
            }
        }
        if DebugSupport.showMiniPlayerAtLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.toggleMiniPlayer()
            }
        }

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            DispatchQueue.main.async {
                window.title = "Cadence"
            }
        }
    }

    func completeOnboarding() {
        hasSeenOnboarding = true
        wantsMusic = true
        persistMusicState()
        showOnboarding = false
        connectMusic()
    }

    func skipOnboarding() {
        hasSeenOnboarding = true
        wantsMusic = false
        persistMusicState()
        showOnboarding = false
        selectSource(.podcasts)
    }

    /// The one explicit place that asks macOS for Music Automation access.
    /// Onboarding, the connect banner and Settings all call this.
    func connectMusic() {
        wantsMusic = true
        persistMusicState()
        // Explicit setup may launch Music; polling starts only after a
        // successful library load, not before the Automation answer.
        Task { await refreshLibrary(launchMusic: true) }
    }

    private func persistMusicState() {
        let defaults = UserDefaults.standard
        defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding")
        defaults.set(wantsMusic, forKey: "wantsMusic")
        defaults.set(musicAccessGranted, forKey: "musicAccessGranted")
    }

    private func markMusicGranted(_ granted: Bool) {
        guard musicAccessGranted != granted else { return }
        musicAccessGranted = granted
        persistMusicState()
    }

    func refreshLibrary(launchMusic: Bool = false) async {
        guard !isRefreshingLibrary else { return }
        isRefreshingLibrary = true
        libraryError = nil
        if library == nil {
            libraryStatus = .loading
        }
        do {
            let result = try await libraryService.loadLibrary(launchMusicIfNeeded: launchMusic)
            apply(snapshot: result.snapshot, stale: result.isStale, warning: result.warning)
            // A stale cache can come from a library-script failure, not from
            // denied Automation. Only the live AppleScript poll is authoritative
            // for access; stale data must not stop that poll or revoke the flag.
            if !result.isStale {
                markMusicGranted(true)
                music.start()
            }
        } catch {
            libraryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case MusicLibraryError.notAuthorized = error {
                markMusicGranted(false)
                music.stop()
            }
            if library == nil {
                libraryStatus = .error
            }
        }
        isRefreshingLibrary = false
    }

    private func apply(snapshot: MusicLibrarySnapshot, stale: Bool, warning: String?) {
        artwork.allowServiceFetch = !stale
        let index = MusicLibraryIndex(snapshot: snapshot)
        library = index
        lastLibraryRefresh = snapshot.fetchedAt
        libraryWarning = warning
        libraryError = nil
        libraryStatus = stale ? .stale : .ready
        if let playlistID = currentPlaylistID, index.userPlaylists.contains(where: { $0.id == playlistID }) == false {
            musicDestination = .playlists
        }
    }

    var currentPlaylistID: String? {
        if case let .playlist(id) = musicDestination { return id }
        return nil
    }

    var selectedPlaylist: MusicPlaylist? {
        guard let id = currentPlaylistID else { return nil }
        return library?.userPlaylists.first { $0.id == id }
    }

    var selectedAlbum: MusicAlbum? {
        if case let .album(id) = musicDestination {
            return library?.album(forKey: id)
        }
        return nil
    }

    var selectedArtist: MusicArtist? {
        if case let .artist(name) = musicDestination {
            return library?.artist(named: name)
        }
        return nil
    }

    func selectSource(_ newSource: PlaybackSource) {
        guard source != newSource else { return }
        source = newSource
    }

    func selectMusic(_ destination: MusicDestination) {
        guard source != .music
            || musicDestination != destination
            || !searchText.isEmpty
            || showCatalog else { return }
        source = .music
        musicDestination = destination
        searchText = ""
        showCatalog = false
    }

    func goBackInMusic() {
        switch musicDestination {
        case .album: musicDestination = .albums
        case .artist: musicDestination = .artists
        case .playlist: musicDestination = .playlists
        default: break
        }
    }

    func focusSearch() {
        selectSource(.music)
        searchFocusToken += 1
    }

    // MARK: - Playback

    private func prepareMusicUse() {
        if !wantsMusic {
            wantsMusic = true
            persistMusicState()
        }
        music.start()
    }

    func play(track: MusicTrack) {
        selectSource(.music)
        prepareMusicUse()
        music.play(track: track)
    }

    func play(tracks: [MusicTrack], shuffle: Bool? = nil) {
        guard !tracks.isEmpty else { return }
        selectSource(.music)
        prepareMusicUse()
        music.play(queue: tracks, shuffle: shuffle)
    }

    func play(album: MusicAlbum, shuffle: Bool = false) {
        prepareMusicUse()
        music.play(queue: album.tracks, shuffle: shuffle)
        selectSource(.music)
    }

    func playAllSongs(shuffle: Bool = false) {
        selectSource(.music)
        prepareMusicUse()
        music.playLibrary(shuffle: shuffle)
    }

    func play(playlist: MusicPlaylist) {
        selectSource(.music)
        prepareMusicUse()
        guard !playlist.persistentID.isEmpty else {
            showToast("Обновите медиатеку: у плейлиста нет постоянного ID.")
            Task { await refreshLibrary(launchMusic: musicIsRunning) }
            return
        }
        music.play(playlistID: playlist.persistentID)
    }

    func togglePlayPause() {
        if playback.activeSource == .music {
            guard musicAccessGranted else { showToast("Сначала подключите Music."); return }
            music.start()
        }
        playback.toggle()
    }

    func nextTrack() {
        if playback.activeSource == .music {
            guard musicAccessGranted else { showToast("Сначала подключите Music."); return }
            music.start()
        }
        playback.next()
    }

    func previousTrack() {
        if playback.activeSource == .music {
            guard musicAccessGranted else { showToast("Сначала подключите Music."); return }
            music.start()
        }
        playback.previous()
    }

    // MARK: - UI actions

    func toggleSidebar() {
        showSidebar.toggle()
    }

    func togglePalette() {
        isPalettePresented.toggle()
    }

    func closePalette() {
        isPalettePresented = false
    }

    func toggleMiniPlayer() {
        if miniPlayerWindow == nil {
            miniPlayerWindow = MiniPlayerWindowController(model: self)
        }
        guard let miniPlayerWindow else { return }
        miniPlayerWindow.toggle()
        showMiniPlayer = miniPlayerWindow.isVisible
    }

    func hideMiniPlayer() {
        miniPlayerWindow?.hide()
        showMiniPlayer = false
    }

    func openMusicApp() {
        let url = URL(fileURLWithPath: "/System/Applications/Music.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(track: MusicTrack) {
        guard musicAccessGranted else { showToast("Сначала подключите Music."); return }
        music.start()
        music.reveal(track: track)
    }

    func openCatalogItem(_ item: CatalogItem) {
        guard let viewURL = item.viewURL else { return }
        let musicURL = URL(fileURLWithPath: "/System/Applications/Music.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([viewURL], withApplicationAt: musicURL, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.showToast("Не удалось открыть Music: \(error.localizedDescription)")
                }
            }
        }
    }

    func searchAppleMusic() {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !isCatalogLoading else { return }
        isCatalogLoading = true
        catalogError = nil
        showCatalog = true
        catalogQuery = term
        Task {
            do {
                let items = try await catalog.searchMusic(term: term, limit: 15)
                catalogItems = items
            } catch {
                catalogError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                catalogItems = []
            }
            isCatalogLoading = false
        }
    }

    func clearCatalogSearch() {
        showCatalog = false
        catalogQuery = nil
        catalogItems = []
        catalogError = nil
    }

    func openPodcastSearch(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty,
              let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://podcasts.apple.com/search?term=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    func showToast(_ text: String) {
        let message = ToastMessage(text: text)
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast?.id == message.id {
                toast = nil
            }
        }
    }

}
