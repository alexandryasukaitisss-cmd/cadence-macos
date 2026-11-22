import AppKit
import CadenceCore
import SwiftUI

private enum SongSort: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .album: return "По альбому"
        case .recent: return "Сначала новые"
        }
    }
}

struct MusicSongsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sort: SongSort = .title

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicPageHeader(
                "Песни",
                subtitle: subtitle
            ) {
                HStack(spacing: 8) {
                    if model.library != nil {
                        PillButton(title: "Играть", systemImage: "play.fill") {
                            model.playAllSongs()
                        }
                        PillButton(title: "Перемешать", systemImage: "shuffle", filled: false) {
                            model.playAllSongs(shuffle: true)
                        }
                    }
                    sortMenu
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            if let library = model.library {
                ScrollView {
                    TrackList(tracks: sorted(library.songs), showAlbum: true, showHeader: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            } else {
                EmptyStateView(
                    systemImage: "music.note.list",
                    title: "Песен пока нет",
                    message: "Подключите Music, чтобы Cadence прочитал вашу медиатеку.",
                    actionTitle: "Подключить Music"
                ) {
                    Task { await model.refreshLibrary() }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var subtitle: String {
        guard let library = model.library else { return "Медиатека не подключена" }
        return "\(RU.tracks(library.songs.count)) · \(library.totalDuration.musicDurationText)"
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SongSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if sort == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Сортировка")
    }

    private func sorted(_ tracks: [MusicTrack]) -> [MusicTrack] {
        switch sort {
        case .title:
            return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return tracks.sorted {
                if $0.displayArtist.localizedStandardCompare($1.displayArtist) != .orderedSame {
                    return $0.displayArtist.localizedStandardCompare($1.displayArtist) == .orderedAscending
                }
                if $0.album.localizedStandardCompare($1.album) != .orderedSame {
                    return $0.album.localizedStandardCompare($1.album) == .orderedAscending
                }
                return $0.trackNumber < $1.trackNumber
            }
        case .album:
            return tracks.sorted {
                if $0.album.localizedStandardCompare($1.album) != .orderedSame {
                    return $0.album.localizedStandardCompare($1.album) == .orderedAscending
                }
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                return $0.trackNumber < $1.trackNumber
            }
        case .recent:
            return tracks.sorted {
                ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
            }
        }
    }
}

private enum AlbumSort: String, CaseIterable, Identifiable {
    case title
    case artist
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .recent: return "Сначала новые"
        }
    }
}

struct MusicAlbumsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sort: AlbumSort = .title

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicPageHeader(
                "Альбомы",
                subtitle: model.library.map { RU.albums($0.albums.count) } ?? "Медиатека не подключена"
            ) {
                sortMenu
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            if let library = model.library, !library.albums.isEmpty {
                ScrollView {
                    AlbumGrid(albums: sorted(library.albums))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
            } else {
                EmptyStateView(
                    systemImage: "square.stack",
                    title: "Альбомов пока нет",
                    message: "Подключите Music или добавьте альбомы в медиатеку.",
                    actionTitle: "Подключить Music"
                ) {
                    Task { await model.refreshLibrary() }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AlbumSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if sort == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Сортировка")
    }

    private func sorted(_ albums: [MusicAlbum]) -> [MusicAlbum] {
        switch sort {
        case .title:
            return albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return albums.sorted {
                if $0.artist.localizedStandardCompare($1.artist) != .orderedSame {
                    return $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .recent:
            return albums.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        }
    }
}

struct MusicArtistsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicPageHeader(
                "Исполнители",
                subtitle: model.library.map { RU.artists($0.artists.count) } ?? "Медиатека не подключена"
            )
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            if let library = model.library, !library.artists.isEmpty {
                ScrollView {
                    ArtistGrid(artists: library.artists)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
            } else {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "Исполнителей пока нет",
                    message: "Подключите Music, чтобы увидеть исполнителей из вашей медиатеки."
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MusicPlaylistsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicPageHeader(
                "Плейлисты",
                subtitle: model.library.map { RU.playlists($0.userPlaylists.count) } ?? "Медиатека не подключена"
            ) {
                PillButton(title: "Открыть Music", systemImage: "arrow.up.forward.app", filled: false) {
                    model.openMusicApp()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            if let library = model.library, !library.userPlaylists.isEmpty {
                ScrollView {
                    PlaylistGrid(playlists: library.userPlaylists)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
            } else {
                EmptyStateView(
                    systemImage: "music.note.list",
                    title: "Плейлистов пока нет",
                    message: "Создайте плейлист в Music — он появится здесь.",
                    actionTitle: "Открыть Music"
                ) {
                    model.openMusicApp()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
