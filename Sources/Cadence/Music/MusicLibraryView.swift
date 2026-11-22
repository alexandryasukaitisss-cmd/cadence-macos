import AppKit
import CadenceCore
import SwiftUI

struct MusicLibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            if model.showSidebar {
                MusicSidebar()
                    .frame(width: Theme.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
            }
            VStack(spacing: 0) {
                MusicTopBar()
                bannerArea
                MusicContentRouter()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.18), value: model.showSidebar)
    }

    @ViewBuilder
    private var bannerArea: some View {
        VStack(spacing: 8) {
            if !model.musicAccessGranted && model.wantsMusic {
                BannerView(
                    kind: .warning,
                    message: "Music ещё не подключён. Нажмите «Подключить» и разрешите управление Music в системном запросе.",
                    actionTitle: "Подключить"
                ) {
                    model.connectMusic()
                }
            } else if let error = model.libraryError {
                BannerView(
                    kind: .error,
                    message: error,
                    actionTitle: "Повторить"
                ) {
                    Task { await model.refreshLibrary() }
                }
            } else if let warning = model.libraryWarning {
                BannerView(
                    kind: .info,
                    message: warning,
                    actionTitle: model.musicIsRunning ? "Обновить" : "Открыть Music"
                ) {
                    if model.musicIsRunning {
                        Task { await model.refreshLibrary() }
                    } else {
                        model.openMusicApp()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, bannerPadding)
    }

    private var bannerPadding: CGFloat {
        if (!model.musicAccessGranted && model.wantsMusic) || model.libraryError != nil || model.libraryWarning != nil {
            return 12
        }
        return 0
    }
}

private struct MusicSidebar: View {
    @EnvironmentObject private var model: AppModel

    private var selection: Binding<MusicDestination?> {
        Binding(
            get: {
                switch model.musicDestination {
                case .album: return .albums
                case .artist: return .artists
                default: return model.musicDestination
                }
            },
            set: { newValue in
                if let newValue {
                    model.selectMusic(newValue)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                Section {
                    sidebarRow(.home, title: "Обзор", icon: "home")
                    sidebarRow(.songs, title: "Песни", icon: "music.note.list", count: model.library?.songs.count)
                    sidebarRow(.albums, title: "Альбомы", icon: "square.stack", count: model.library?.albums.count)
                    sidebarRow(.artists, title: "Исполнители", icon: "person.2", count: model.library?.artists.count)
                } header: {
                    sectionHeader("Медиатека")
                }

                Section {
                    sidebarRow(.playlists, title: "Все плейлисты", icon: "music.note.list", count: model.library?.userPlaylists.count)
                    if let playlists = model.library?.userPlaylists {
                        ForEach(playlists) { playlist in
                            HStack(spacing: 8) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.podcastAccent)
                                    .frame(width: 16)
                                Text(playlist.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(playlist.trackCount)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .tag(MusicDestination.playlist(playlist.id))
                        }
                    }
                } header: {
                    sectionHeader("Плейлисты")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)

            sidebarFooter
        }
        .background(.regularMaterial)
    }

    private func sidebarRow(_ destination: MusicDestination, title: String, icon: String, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(model.musicDestination == destination ? Theme.musicAccent : .secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .tag(destination)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let library = model.library {
                        Text(RU.tracks(library.snapshot.tracks.count))
                            .font(.system(size: 10.5, weight: .medium))
                        Text("\(RU.albums(library.albums.count)) · \(RU.playlists(library.userPlaylists.count))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    } else if model.libraryStatus == .loading {
                        Text("Читаем медиатеку…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Медиатека не подключена")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if model.isRefreshingLibrary {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 24, height: 24)
                } else {
                    IconButton(systemName: "arrow.clockwise", help: "Обновить медиатеку", size: 24) {
                        Task { await model.refreshLibrary() }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

private struct MusicTopBar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconButton(
                systemName: "sidebar.left",
                help: model.showSidebar ? "Скрыть меню (⌘⇧S)" : "Показать меню (⌘⇧S)",
                size: 26
            ) {
                model.toggleSidebar()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("Поиск в медиатеке", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onSubmit {
                        searchFocused = false
                    }
                    .onKeyPress(.escape) {
                        if !model.searchText.isEmpty {
                            model.searchText = ""
                            return .handled
                        }
                        searchFocused = false
                        return .handled
                    }
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Очистить поиск")
                }
            }
            .padding(.horizontal, 9)
            .frame(width: 300, height: 26)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))

            Spacer(minLength: 8)

            if musicPermissionNeedsAttention {
                Button("Подключить Music") {
                    model.connectMusic()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            IconButton(systemName: "music.note.house", help: "Открыть Music", size: 26) {
                model.openMusicApp()
            }

            if model.isRefreshingLibrary {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 26)
            } else {
                IconButton(systemName: "arrow.clockwise", help: "Обновить медиатеку (⌘⇧R)", size: 26) {
                    Task { await model.refreshLibrary() }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.82))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
        .onChange(of: model.searchFocusToken) { _, _ in
            searchFocused = true
        }
    }

    private var musicPermissionNeedsAttention: Bool {
        !model.musicAccessGranted
    }
}

private struct MusicContentRouter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MusicSearchView()
            } else {
                switch model.musicDestination {
                case .home:
                    MusicHomeView()
                case .songs:
                    MusicSongsView()
                case .albums:
                    MusicAlbumsView()
                case .artists:
                    MusicArtistsView()
                case .playlists:
                    MusicPlaylistsView()
                case let .album(id):
                    if let album = model.library?.album(forKey: id) {
                        AlbumDetailView(album: album)
                    } else {
                        EmptyStateView(
                            systemImage: "square.stack",
                            title: "Альбом не найден",
                            message: "Возможно, медиатека изменилась. Вернитесь к списку альбомов.",
                            actionTitle: "К альбомам"
                        ) {
                            model.selectMusic(.albums)
                        }
                    }
                case let .artist(name):
                    if let artist = model.library?.artist(named: name) {
                        ArtistDetailView(artist: artist)
                    } else {
                        EmptyStateView(
                            systemImage: "person.2",
                            title: "Исполнитель не найден",
                            message: "Возможно, медиатека изменилась.",
                            actionTitle: "К исполнителям"
                        ) {
                            model.selectMusic(.artists)
                        }
                    }
                case let .playlist(id):
                    if let playlist = model.library?.userPlaylists.first(where: { $0.id == id }) {
                        PlaylistDetailView(playlist: playlist)
                    } else {
                        EmptyStateView(
                            systemImage: "music.note.list",
                            title: "Плейлист не найден",
                            message: "Возможно, плейлист был переименован или удалён.",
                            actionTitle: "К плейлистам"
                        ) {
                            model.selectMusic(.playlists)
                        }
                    }
                }
            }
        }
    }
}
