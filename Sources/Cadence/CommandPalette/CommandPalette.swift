import AppKit
import CadenceCore
import SwiftUI

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?
    let accent: Color?
    let action: () -> Void
}

struct CommandPaletteOverlay: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var music: MusicController

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var commands: [PaletteCommand] {
        buildCommands()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture { model.closePalette() }

            panel
                .padding(.top, 84)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            resultList
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            footer
        }
        .frame(width: 590)
        .frame(maxHeight: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        .onAppear {
            DispatchQueue.main.async {
                focused = true
            }
        }
        .onChange(of: query) { _, _ in
            selection = 0
        }
        .onChange(of: commands.count) { _, newCount in
            if selection >= newCount {
                selection = max(0, newCount - 1)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Найти трек, альбом или команду…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .focused($focused)
                .onSubmit { execute() }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.closePalette()
                    return .handled
                }
            Text("esc")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        commandRow(command, selected: index == selection)
                            .id(command.id)
                            .onTapGesture {
                                selection = index
                                execute()
                            }
                    }
                }
            }
            .frame(maxHeight: 350)
            .onChange(of: selection) { _, newValue in
                if commands.indices.contains(newValue) {
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo(commands[newValue].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func commandRow(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: command.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? (command.accent ?? .white) : (command.accent ?? .secondary))
                .frame(width: 26, height: 26)
                .background(
                    (selected ? (command.accent ?? Theme.musicAccent).opacity(0.14) : Color.primary.opacity(0.05)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if !command.subtitle.isEmpty {
                    Text(command.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 45)
        .background(selected ? Color.primary.opacity(0.065) : Color.clear)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↑↓ выбрать")
            Text("↵ открыть")
            Text("esc закрыть")
            Spacer()
            Text("Cadence")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .frame(height: 31)
    }

    private func moveSelection(_ delta: Int) {
        guard !commands.isEmpty else { return }
        let count = commands.count
        selection = (selection + delta + count) % count
    }

    private func execute() {
        guard commands.indices.contains(selection) else { return }
        let action = commands[selection].action
        model.closePalette()
        action()
    }

    private func buildCommands() -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return quickCommands
        }

        var result: [PaletteCommand] = []

        if let library = model.library {
            let matches = library.search(trimmed, limit: 18)
            for match in matches {
                switch match {
                case let .track(track):
                    result.append(PaletteCommand(
                        id: "track-\(track.id)",
                        title: track.title,
                        subtitle: "\(track.displayArtist) · \(track.displayAlbum)",
                        icon: "music.note",
                        shortcut: nil,
                        accent: Theme.musicAccent,
                        action: { model.play(track: track) }
                    ))
                case let .album(album):
                    result.append(PaletteCommand(
                        id: "album-\(album.id)",
                        title: album.title,
                        subtitle: "Альбом · \(album.artist)",
                        icon: "square.stack",
                        shortcut: nil,
                        accent: Theme.musicAccent,
                        action: { model.selectMusic(.album(album.id)) }
                    ))
                case let .artist(artist):
                    result.append(PaletteCommand(
                        id: "artist-\(artist.id)",
                        title: artist.name,
                        subtitle: "Исполнитель · \(RU.albums(artist.albumCount))",
                        icon: "person.2",
                        shortcut: nil,
                        accent: Theme.musicAccent,
                        action: { model.selectMusic(.artist(artist.name)) }
                    ))
                case let .playlist(playlist):
                    result.append(PaletteCommand(
                        id: "playlist-\(playlist.id)",
                        title: playlist.name,
                        subtitle: "Плейлист · \(RU.tracks(playlist.trackCount))",
                        icon: "music.note.list",
                        shortcut: nil,
                        accent: Theme.musicAccent,
                        action: {
                            model.selectSource(.music)
                            model.selectMusic(.playlist(playlist.id))
                        }
                    ))
                }
            }
        }

        let normalized = MusicText.normalized(trimmed)
        for command in quickCommands where MusicText.normalized(command.title).contains(normalized) {
            result.append(command)
        }

        result.append(PaletteCommand(
            id: "search-apple-music",
            title: "Искать «\(trimmed)» в Apple Music",
            subtitle: "Открыть результаты каталога",
            icon: "globe",
            shortcut: nil,
            accent: Theme.musicAccent,
            action: {
                model.selectSource(.music)
                model.searchText = trimmed
                model.searchAppleMusic()
            }
        ))

        result.append(PaletteCommand(
            id: "search-podcasts",
            title: "Искать «\(trimmed)» в подкастах",
            subtitle: "Apple Podcasts",
            icon: "mic.fill",
            shortcut: nil,
            accent: Theme.podcastAccent,
            action: { model.openPodcastSearch(trimmed) }
        ))

        return Array(result.prefix(22))
    }

    private var quickCommands: [PaletteCommand] {
        let isPlaying = playback.snapshot?.isPlaying == true
        return [
            PaletteCommand(
                id: "playpause",
                title: isPlaying ? "Пауза" : "Играть",
                subtitle: "Текущий источник",
                icon: isPlaying ? "pause.fill" : "play.fill",
                shortcut: "⌘⇧P",
                accent: playback.activeSource.accent,
                action: { model.togglePlayPause() }
            ),
            PaletteCommand(
                id: "next",
                title: "Следующий трек",
                subtitle: "Или вперёд на 30 секунд",
                icon: "forward.fill",
                shortcut: "⌘→",
                accent: nil,
                action: { model.nextTrack() }
            ),
            PaletteCommand(
                id: "previous",
                title: "Предыдущий трек",
                subtitle: "Или назад на 15 секунд",
                icon: "backward.fill",
                shortcut: "⌘←",
                accent: nil,
                action: { model.previousTrack() }
            ),
            PaletteCommand(
                id: "mini-player",
                title: model.showMiniPlayer ? "Скрыть мини-плеер" : "Показать мини-плеер",
                subtitle: "Поверх всех окон",
                icon: "pip",
                shortcut: "⌘⇧M",
                accent: nil,
                action: { model.toggleMiniPlayer() }
            ),
            PaletteCommand(
                id: "music",
                title: "Music",
                subtitle: "Медиатека Apple Music",
                icon: "music.note",
                shortcut: "⌘1",
                accent: Theme.musicAccent,
                action: { model.selectSource(.music) }
            ),
            PaletteCommand(
                id: "podcasts",
                title: "Подкасты",
                subtitle: "Apple Podcasts",
                icon: "mic.fill",
                shortcut: "⌘2",
                accent: Theme.podcastAccent,
                action: { model.selectSource(.podcasts) }
            ),
            PaletteCommand(
                id: "songs",
                title: "Все песни",
                subtitle: model.library.map { RU.tracks($0.songs.count) } ?? "Медиатека",
                icon: "music.note.list",
                shortcut: nil,
                accent: nil,
                action: { model.selectMusic(.songs) }
            ),
            PaletteCommand(
                id: "albums",
                title: "Альбомы",
                subtitle: model.library.map { RU.albums($0.albums.count) } ?? "Медиатека",
                icon: "square.stack",
                shortcut: nil,
                accent: nil,
                action: { model.selectMusic(.albums) }
            ),
            PaletteCommand(
                id: "artists",
                title: "Исполнители",
                subtitle: "Медиатека",
                icon: "person.2",
                shortcut: nil,
                accent: nil,
                action: { model.selectMusic(.artists) }
            ),
            PaletteCommand(
                id: "refresh-library",
                title: "Обновить медиатеку",
                subtitle: "Перечитать данные из Music",
                icon: "arrow.clockwise",
                shortcut: "⌘⇧R",
                accent: nil,
                action: { Task { await model.refreshLibrary() } }
            ),
            PaletteCommand(
                id: "open-music",
                title: "Открыть Music",
                subtitle: "Системное приложение",
                icon: "arrow.up.forward.app",
                shortcut: nil,
                accent: nil,
                action: { model.openMusicApp() }
            ),
            PaletteCommand(
                id: "settings",
                title: "Настройки",
                subtitle: "Cadence",
                icon: "gearshape",
                shortcut: "⌘,",
                accent: nil,
                action: { model.openSettings() }
            )
        ]
    }
}
