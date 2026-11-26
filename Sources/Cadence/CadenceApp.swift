import AppKit
import CadenceCore
import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updater = GitHubCommitUpdater(
        repository: "alexandryasukaitisss-cmd/cadence-macos",
        bundleName: "Cadence.app",
        executableName: "Cadence"
    )

    var body: some Scene {
        WindowGroup("Cadence", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.playback)
                .environmentObject(model.music)
                .environmentObject(model.artwork)
                .environmentObject(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CadenceCommands(model: model, updater: updater)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.playback)
                .environmentObject(model.music)
                .environmentObject(model.artwork)
                .environmentObject(updater)
        }

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(model)
                .environmentObject(model.playback)
                .environmentObject(model.music)
                .environmentObject(updater)
        } label: {
            Label("Cadence", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        model.playback.snapshot?.isPlaying == true ? "waveform" : "music.note"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isEmpty, event.charactersIgnoringModifiers == " " else {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder {
                let name = String(describing: type(of: responder))
                if responder is NSTextView || name.contains("WKContent") || name.contains("TextField") {
                    return event
                }
            }
            NotificationCenter.default.post(name: .cadenceTogglePlayback, object: nil)
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

struct CadenceCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: GitHubCommitUpdater

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .appInfo) {
            if let candidate = updater.availableUpdate {
                Button("Обновить до коммита \(candidate.shortSHA)…") {
                    updater.installAvailableUpdate()
                }
            } else {
                Button("Проверить обновления…") {
                    updater.checkForUpdates(manual: true)
                    model.openSettings()
                }
            }
        }

        CommandMenu("Воспроизведение") {
            Button(model.playback.snapshot?.isPlaying == true ? "Пауза" : "Играть") {
                model.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Следующий трек") { model.nextTrack() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Предыдущий трек") { model.previousTrack() }
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button(model.showMiniPlayer ? "Скрыть мини-плеер" : "Показать мини-плеер") {
                model.toggleMiniPlayer()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Показать текущий трек в Music") {
                model.playback.revealCurrentInMusic()
            }
        }

        CommandMenu("Переход") {
            Button("Music") { model.selectSource(.music) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Подкасты") { model.selectSource(.podcasts) }
                .keyboardShortcut("2", modifiers: .command)

            Divider()

            Button("Поиск в медиатеке") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Командная палитра") { model.togglePalette() }
                .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Песни") { model.selectMusic(.songs) }
            Button("Альбомы") { model.selectMusic(.albums) }
            Button("Исполнители") { model.selectMusic(.artists) }
            Button("Плейлисты") { model.selectMusic(.playlists) }

            Divider()

            Button(model.showSidebar ? "Скрыть боковое меню" : "Показать боковое меню") {
                model.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Обновить медиатеку") {
                Task { await model.refreshLibrary() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

private struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var updater: GitHubCommitUpdater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.musicAccent, Theme.podcastAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Cadence")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let source = playback.snapshot?.source {
                    Text(source.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(source.accent)
                }
            }

            if let snapshot = playback.snapshot {
                HStack(spacing: 10) {
                    ArtworkImage(
                        image: snapshot.artwork,
                        seed: snapshot.artworkKey,
                        size: 48,
                        cornerRadius: 8,
                        systemImage: snapshot.source == .music ? "music.note" : "mic.fill"
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(snapshot.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        playback.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    Button {
                        playback.toggle()
                    } label: {
                        Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 24, height: 24)
                            .background(snapshot.source.accent, in: Circle())
                            .foregroundStyle(.white)
                    }
                    Button {
                        playback.next()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    Spacer()
                    Text("\(snapshot.position.musicDurationText) / \(snapshot.duration.musicDurationText)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Ничего не играет")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Открыть Cadence") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Button(model.showMiniPlayer ? "Скрыть мини-плеер" : "Показать мини-плеер") {
                model.toggleMiniPlayer()
            }
            Button("Настройки…") {
                model.openSettings()
            }
            if let candidate = updater.availableUpdate {
                Button("Обновить до \(candidate.shortSHA)…") {
                    updater.installAvailableUpdate()
                }
            }
            Divider()
            Button("Выйти из Cadence") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
