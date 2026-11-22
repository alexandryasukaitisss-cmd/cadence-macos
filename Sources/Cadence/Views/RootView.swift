import AppKit
import CadenceCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCoordinator
    @State private var didAppear = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                AppTitleBar()
                ZStack {
                    MusicLibraryView()
                        .opacity(model.source == .music ? 1 : 0)
                        .allowsHitTesting(model.source == .music)
                        .accessibilityHidden(model.source != .music)
                    PodcastsExternalView()
                        .opacity(model.source == .podcasts ? 1 : 0)
                        .allowsHitTesting(model.source == .podcasts)
                        .accessibilityHidden(model.source != .podcasts)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                NowPlayingBar(music: model.music)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            if let toast = model.toast {
                Text(toast.text)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                    .padding(.bottom, Theme.playerHeight + 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if model.isPalettePresented {
                CommandPaletteOverlay()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.toast?.id)
        .animation(.easeOut(duration: 0.14), value: model.isPalettePresented)
        .frame(minWidth: 980, minHeight: 680)
        .background(WindowConfigurator())
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environmentObject(model)
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            DebugSupport.log("RootView.onAppear")
            model.bootstrap()
            DebugSupport.scheduleSnapshotIfRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceFocusSearch)) { _ in
            model.focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceTogglePlayback)) { _ in
            model.togglePlayPause()
        }
        .onChange(of: model.source) { _, _ in
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

extension Notification.Name {
    static let cadenceFocusSearch = Notification.Name("CadenceFocusSearch")
    static let cadenceTogglePlayback = Notification.Name("CadenceTogglePlayback")
}

private struct AppTitleBar: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 12) {
            BrandMark()
                .padding(.leading, 76)

            Spacer(minLength: 8)

            SourceSwitcher(namespace: namespace)
                .frame(width: 248)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    model.togglePalette()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Поиск")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("⌘K")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Поиск и команды (⌘K)")

                IconButton(
                    systemName: "pip",
                    help: model.showMiniPlayer ? "Скрыть мини-плеер" : "Мини-плеер (⌘⇧M)",
                    accent: model.showMiniPlayer ? model.source.accent : nil
                ) {
                    model.toggleMiniPlayer()
                }

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Настройки (⌘,)")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.headerHeight)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }
}

private struct BrandMark: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.musicAccent, Theme.podcastAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("Cadence")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cadence")
    }
}

private struct SourceSwitcher: View {
    @EnvironmentObject private var model: AppModel
    let namespace: NamespaceID

    var body: some View {
        HStack(spacing: 2) {
            switcherButton(.music, title: "Music", icon: "music.note")
            switcherButton(.podcasts, title: "Подкасты", icon: "mic.fill")
        }
        .padding(3)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func switcherButton(_ source: PlaybackSource, title: String, icon: String) -> some View {
        let selected = model.source == source
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                model.selectSource(source)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background {
                if selected {
                    Capsule()
                        .fill(source.accent)
                        .matchedGeometryEffect(id: "source-pill", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private typealias NamespaceID = Namespace.ID

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = "Cadence"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .windowBackgroundColor
            window.minSize = NSSize(width: 980, height: 680)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
