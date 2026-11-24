import AppKit
import CadenceCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Общие", systemImage: "gearshape") }
            MusicSettingsView()
                .tabItem { Label("Music", systemImage: "music.note") }
            PodcastSettingsView()
                .tabItem { Label("Подкасты", systemImage: "mic") }
            AboutSettingsView()
                .tabItem { Label("О Cadence", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 560)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Интерфейс") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Мини-плеер")
                        Text("Плавающее окно поверх всех приложений.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.showMiniPlayer ? "Скрыть" : "Открыть") {
                        model.toggleMiniPlayer()
                    }
                    .controlSize(.small)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Боковое меню")
                        Text("Медиатека, плейлисты и разделы.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showSidebar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            Section("Горячие клавиши") {
                shortcutRow("Командная палитра", "⌘K")
                shortcutRow("Поиск в медиатеке", "⌘F")
                shortcutRow("Music / Подкасты", "⌘1 / ⌘2")
                shortcutRow("Играть или пауза", "⌘⇧P")
                shortcutRow("Мини-плеер", "⌘⇧M")
                shortcutRow("Обновить медиатеку", "⌘⇧R")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, _ shortcut: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

private struct MusicSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Медиатека") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Состояние")
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isRefreshingLibrary {
                        ProgressView().controlSize(.small)
                    } else if !model.musicAccessGranted {
                        Button("Подключить") { model.connectMusic() }
                            .controlSize(.small)
                    } else {
                        Button("Обновить") {
                            Task { await model.refreshLibrary() }
                        }
                        .controlSize(.small)
                    }
                }
                if let library = model.library {
                    LabeledContent("Треки", value: "\(library.songs.count)")
                    LabeledContent("Альбомы", value: "\(library.albums.count)")
                    LabeledContent("Исполнители", value: "\(library.artists.count)")
                    LabeledContent("Плейлисты", value: "\(library.userPlaylists.count)")
                }
            }

            Section("Качество стриминга") {
                LabeledContent("Музыка", value: "Наследуется из Music.app")
                LabeledContent("Lossless", value: StreamingQuality.losslessEnabled ? "включён" : "выключен")
                LabeledContent("Dolby Atmos", value: StreamingQuality.atmosDownloadsEnabled ? "включён" : "выключен")
                Text("Профиль задаётся в Music → Настройки → Воспроизведение. Cadence его не меняет; подкасты Apple выбирает адаптивно.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("При запуске Cadence Music не открывается: показывается кэш. Music запускается скрыто по Play, «Подключить» или «Открыть Music».")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Открыть Music") { model.openMusicApp() }
                    .controlSize(.small)
            }

            Section("Music.app") {
                LabeledContent("Регион каталога", value: model.catalogCountry.uppercased())
                Text("Cadence управляет Music через AppleScript. AppleScript-доступ к медиатеке требует разрешения Automation; веб-каталог Apple Music в WKWebView пока не используется.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Открыть Music") { model.openMusicApp() }
                    Button("Настройки автоматизации") { model.openAutomationSettings() }
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch model.libraryStatus {
        case .idle: return model.musicAccessGranted ? "Не подключено" : "Music не подключён"
        case .loading: return "Читаем медиатеку…"
        case .ready: return "Обновлено \(refreshedText)"
        case .stale: return "Показан кэш · \(refreshedText)"
        case .error: return model.libraryError ?? "Ошибка"
        }
    }

    private var refreshedText: String {
        guard let date = model.lastLibraryRefresh else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}

private struct PodcastSettingsView: View {
    var body: some View {
        Form {
            Section("Apple Podcasts") {
                Text("Cadence не встраивает веб-плеер и не принимает данные аккаунта Apple. Кнопка открывает официальный каталог в браузере по умолчанию.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Открыть Apple Podcasts") {
                    if let url = URL(string: "https://podcasts.apple.com/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            Section("Границы версии") {
                Text("Встроенный плеер, вход, синхронизация подписок и продолжение эпизода появятся только после отдельной проверки правил Apple и реального сценария входа.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.musicAccent, Theme.podcastAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 12)

            Text("Cadence")
                .font(.system(size: 24, weight: .bold))
            Text("Версия 0.1.1 · нативная медиатека Apple Music")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                aboutRow("music.note", "Music играет через Music.app и AppleScript.")
                aboutRow("mic.fill", "Подкасты открываются в браузере, без встроенного входа.")
                aboutRow("lock.shield", "Без телеметрии и внешних серверов.")
                aboutRow("bolt.fill", "SwiftUI + AppKit. Без Electron.")
            }
            .padding(.top, 8)

            Spacer()

            Text("Cadence не аффилирован с Apple. Apple Music и Apple Podcasts — товарные знаки Apple Inc.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func aboutRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.musicAccent)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
