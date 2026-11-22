import AppKit
import CadenceCore
import Foundation

struct NowPlayingSnapshot {
    var source: PlaybackSource
    var title: String
    var subtitle: String
    var album: String
    var artwork: NSImage?
    var artworkKey: String
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var canSeek: Bool
    var canSkip: Bool
    var isFavorite: Bool
    var volume: Double

    var progress: Double {
        guard duration > 0, duration.isFinite else { return 0 }
        return max(0, min(1, position / duration))
    }
}

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var snapshot: NowPlayingSnapshot?
    @Published private(set) var activeSource: PlaybackSource = .music

    var onRequestSource: ((PlaybackSource) -> Void)?

    weak var music: MusicController?
    private let artwork: ArtworkStore

    private var musicState: MusicPlaybackState?
    private var artworkTask: Task<Void, Never>?
    private var currentArtworkKey: String = ""
    private var lastArtworkRevision = -1

    init(artwork: ArtworkStore) {
        self.artwork = artwork
    }

    func connect(music: MusicController) {
        self.music = music
    }

    func ingestMusic(_ state: MusicPlaybackState) {
        musicState = state
        activeSource = .music
        rebuild()
    }

    private func rebuild() {
        activeSource = .music
        buildMusicSnapshot()
    }

    private func buildMusicSnapshot() {
        guard let state = musicState, state.hasTrack else {
            snapshot = nil
            return
        }
        let key = state.artworkKey
        let image = artwork.cachedImage(for: key)
        snapshot = NowPlayingSnapshot(
            source: .music,
            title: state.displayTitle,
            subtitle: state.displayArtist,
            album: state.album,
            artwork: image,
            artworkKey: key,
            isPlaying: state.isPlaying,
            position: state.position,
            duration: state.duration,
            canSeek: state.duration > 0,
            canSkip: false,
            isFavorite: state.favorited,
            volume: state.volume
        )
        loadArtworkIfNeeded(key: key, musicState: state)
    }

    private func loadArtworkIfNeeded(key: String, musicState: MusicPlaybackState) {
        if artwork.revision != lastArtworkRevision {
            lastArtworkRevision = artwork.revision
            currentArtworkKey = ""
            artworkTask?.cancel()
            artworkTask = nil
        }
        if key == currentArtworkKey, snapshot?.artwork != nil { return }
        if key == currentArtworkKey, artworkTask != nil { return }
        currentArtworkKey = key
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let image = await self.artwork.image(
                forAlbumKey: musicState.artworkKey,
                trackID: musicState.databaseID
            )
            guard !Task.isCancelled, let image else { return }
            await MainActor.run {
                guard var snapshot = self.snapshot, snapshot.artworkKey == key else { return }
                snapshot.artwork = image
                self.snapshot = snapshot
            }
        }
    }

    // MARK: - Transport

    func toggle() { music?.toggle() }
    func resume() { if musicState?.isPlaying != true { music?.toggle() } }
    func pause() { music?.pause() }
    func next() { music?.next() }
    func previous() { music?.previous() }
    func seek(to position: TimeInterval) { music?.seek(to: position) }
    func skip(_ interval: TimeInterval) { music?.seek(to: max(0, (musicState?.position ?? 0) + interval)) }
    func setVolume(_ volume: Double) { music?.setVolume(volume) }
    func toggleFavorite() { music?.toggleFavorite() }
    func revealCurrentInMusic() { music?.revealCurrentTrack() }

    func openSource() {
        onRequestSource?(.music)
    }
}
