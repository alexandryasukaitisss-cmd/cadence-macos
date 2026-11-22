import AppKit
import CadenceCore
import SwiftUI

struct ArtworkImage: View {
    let image: NSImage?
    let seed: String
    var size: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.small
    var systemImage: String = "music.note"

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.artworkGradient(for: seed)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: max(11, size * 0.28), weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCoordinator
    @ObservedObject var music: MusicController

    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
            content
                .padding(.horizontal, 16)
                .frame(height: Theme.playerHeight)
        }
        .background(.ultraThinMaterial)
        .onChange(of: playback.snapshot?.position) { _, newValue in
            guard !isSeeking, let newValue else { return }
            seekValue = newValue
        }
        .onAppear {
            seekValue = playback.snapshot?.position ?? 0
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = playback.snapshot {
            HStack(spacing: 18) {
                trackSummary(snapshot)
                    .frame(width: 300, alignment: .leading)

                Spacer(minLength: 0)

                controls(snapshot)
                    .frame(maxWidth: 500)

                Spacer(minLength: 0)

                trailing(snapshot)
                    .frame(width: 300, alignment: .trailing)
            }
        } else {
            emptyState
        }
    }

    private func trackSummary(_ snapshot: NowPlayingSnapshot) -> some View {
        Button {
            playback.openSource()
        } label: {
            HStack(spacing: 10) {
                ArtworkImage(
                    image: snapshot.artwork,
                    seed: snapshot.artworkKey,
                    size: 46,
                    cornerRadius: 7,
                    systemImage: "music.note"
                )
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(snapshot.subtitle)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.source.icon)
                            .font(.system(size: 8, weight: .bold))
                        Text(snapshot.source.title)
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundStyle(snapshot.source.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(snapshot.source.accent.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Перейти к \(snapshot.source.title)")
        .accessibilityLabel("Сейчас играет: \(snapshot.title), \(snapshot.subtitle)")
    }

    private func controls(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 12) {
                IconButton(
                    systemName: music.state.shuffle ? "shuffle.circle.fill" : "shuffle",
                    help: "Перемешать",
                    size: 26,
                    accent: music.state.shuffle ? Theme.musicAccent : nil
                ) {
                    music.toggleShuffle()
                }
                IconButton(systemName: "backward.fill", help: "Предыдущий трек", size: 26) {
                    playback.previous()
                }

                Button {
                    playback.toggle()
                } label: {
                    Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(snapshot.source.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(snapshot.isPlaying ? "Пауза (⌘⇧P)" : "Играть (⌘⇧P)")
                .accessibilityLabel(snapshot.isPlaying ? "Пауза" : "Играть")

                IconButton(systemName: "forward.fill", help: "Следующий трек", size: 26) {
                    playback.next()
                }
                IconButton(
                    systemName: music.state.repeatMode == "one" ? "repeat.1" : "repeat",
                    help: "Повтор",
                    size: 26,
                    accent: music.state.repeatMode == "off" ? nil : Theme.musicAccent
                ) {
                    music.cycleRepeat()
                }
            }
            .frame(height: 32)

            HStack(spacing: 8) {
                Text(snapshot.position.musicDurationText)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)

                Slider(
                    value: $seekValue,
                    in: 0...max(snapshot.duration, 0.01),
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing {
                            playback.seek(to: seekValue)
                        }
                    }
                )
                .controlSize(.mini)
                .tint(snapshot.source.accent)
                .disabled(!snapshot.canSeek)

                Text(snapshot.duration.musicDurationText)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .leading)
            }
        }
    }

    private func trailing(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Slider(
                    value: Binding(
                        get: { playback.snapshot?.volume ?? 0.7 },
                        set: { playback.setVolume($0) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .frame(width: 72)
                .tint(snapshot.source.accent)
            }

            IconButton(
                systemName: snapshot.isFavorite ? "heart.fill" : "heart",
                help: snapshot.isFavorite ? "Убрать из любимых" : "В любимые",
                size: 26,
                accent: snapshot.isFavorite ? Theme.musicAccent : nil
            ) {
                playback.toggleFavorite()
            }

            IconButton(
                systemName: "pip",
                help: model.showMiniPlayer ? "Скрыть мини-плеер" : "Мини-плеер",
                size: 26,
                accent: model.showMiniPlayer ? snapshot.source.accent : nil
            ) {
                model.toggleMiniPlayer()
            }

            Menu {
                Button("Показать в Music") { playback.revealCurrentInMusic() }
                Button("Открыть Music") { model.openMusicApp() }
                Divider()
                Button("Мини-плеер") { model.toggleMiniPlayer() }
                Divider()
                Button("Настройки…") { model.openSettings() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Ещё")
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ничего не играет")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Выберите трек в медиатеке или включите подкаст")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Открыть поиск") {
                model.togglePalette()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5, weight: .medium))
        }
    }
}
