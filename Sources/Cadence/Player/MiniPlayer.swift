import AppKit
import SwiftUI

final class MiniPlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MiniPlayerWindowController: NSObject {
    private weak var model: AppModel?
    private var panel: MiniPlayerPanel?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let model else { return }
        if panel == nil {
            let panel = MiniPlayerPanel(
                contentRect: NSRect(x: 0, y: 0, width: 386, height: 118),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.title = "Cadence Mini Player"

            let host = NSHostingView(
                rootView: MiniPlayerView()
                    .environmentObject(model)
                    .environmentObject(model.playback)
                    .environmentObject(model.music)
                    .environmentObject(model.artwork)
            )
            host.frame = panel.contentLayoutRect
            host.autoresizingMask = [.width, .height]
            panel.contentView = host

            if !panel.setFrameUsingName("CadenceMiniPlayerPanel") {
                if let screen = NSScreen.main {
                    let visible = screen.visibleFrame
                    let origin = NSPoint(
                        x: visible.maxX - 386 - 22,
                        y: visible.maxY - 118 - 62
                    )
                    panel.setFrameOrigin(origin)
                }
            }
            panel.setFrameAutosaveName("CadenceMiniPlayerPanel")
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct MiniPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = playback.snapshot {
                content(snapshot)
            } else {
                empty
            }
        }
        .frame(width: 386, height: 118)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if let accent = playback.snapshot?.source.accent {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent)
                    .frame(width: 56, height: 2)
                    .padding(.top, 1)
                    .opacity(0.8)
            }
        }
    }

    private func content(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkImage(
                    image: snapshot.artwork,
                    seed: snapshot.artworkKey,
                    size: 68,
                    cornerRadius: 10,
                    systemImage: snapshot.source == .music ? "music.note" : "mic.fill"
                )
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(snapshot.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.source.icon)
                            .font(.system(size: 8, weight: .bold))
                        Text(snapshot.source.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(snapshot.source.accent)
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    IconButton(systemName: "backward.fill", help: "Предыдущий", size: 24) {
                        playback.previous()
                    }
                    Button {
                        playback.toggle()
                    } label: {
                        Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(snapshot.source.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(snapshot.isPlaying ? "Пауза" : "Играть")
                    IconButton(systemName: "forward.fill", help: "Следующий", size: 24) {
                        playback.next()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(snapshot.source.accent)
                        .frame(width: max(0, proxy.size.width * snapshot.progress))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.hideMiniPlayer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Закрыть мини-плеер")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.selectSource(snapshot.source)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    private var empty: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 68, height: 68)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Ничего не играет")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Выберите трек или подкаст в Cadence")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.hideMiniPlayer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Закрыть мини-плеер")
        }
        .padding(12)
    }
}
