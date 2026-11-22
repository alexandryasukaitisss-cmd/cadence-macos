import AppKit
import CadenceCore
import SwiftUI

struct MusicSearchView: View {
    @EnvironmentObject private var model: AppModel

    private var query: String {
        model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [MusicSearchResult] {
        model.library?.search(query, limit: 40) ?? []
    }

    private var tracks: [MusicTrack] {
        results.compactMap {
            if case let .track(track) = $0 { return track }
            return nil
        }
    }

    private var albums: [MusicAlbum] {
        results.compactMap {
            if case let .album(album) = $0 { return album }
            return nil
        }
    }

    private var artists: [MusicArtist] {
        results.compactMap {
            if case let .artist(artist) = $0 { return artist }
            return nil
        }
    }

    private var playlists: [MusicPlaylist] {
        results.compactMap {
            if case let .playlist(playlist) = $0 { return playlist }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MusicPageHeader(
                    "Поиск",
                    subtitle: query.isEmpty ? "Введите запрос" : "Результаты для «\(query)»"
                )

                if !tracks.isEmpty {
                    section("Песни") {
                        TrackList(tracks: tracks, showAlbum: true, showHeader: false)
                            .cardSurface()
                    }
                }

                if !albums.isEmpty {
                    section("Альбомы") {
                        AlbumGrid(albums: albums)
                    }
                }

                if !artists.isEmpty {
                    section("Исполнители") {
                        ArtistGrid(artists: artists)
                    }
                }

                if !playlists.isEmpty {
                    section("Плейлисты") {
                        PlaylistGrid(playlists: playlists)
                    }
                }

                appleMusicSection

                if results.isEmpty && !model.isCatalogLoading && !catalogVisible {
                    VStack(spacing: 8) {
                        Text("В медиатеке ничего не найдено")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Попробуйте другой запрос или найдите трек в каталоге Apple Music.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
    }

    private var catalogVisible: Bool {
        model.showCatalog && model.catalogQuery == query
    }

    private var appleMusicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("В Apple Music")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !catalogVisible {
                    Button {
                        model.searchAppleMusic()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                            Text("Искать в каталоге")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(query.isEmpty || model.isCatalogLoading)
                }
            }

            if model.isCatalogLoading && model.catalogQuery == query {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Ищем в Apple Music…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let error = model.catalogError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else if catalogVisible {
                if model.catalogItems.isEmpty {
                    Text("В каталоге ничего не найдено.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.catalogItems) { item in
                            CatalogResultRow(item: item) {
                                model.openCatalogItem(item)
                            }
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                        }
                    }
                    .cardSurface()
                    Text("Воспроизведение откроется в Music. Cadence не может играть каталог Apple Music внутри окна — Apple ограничивает DRM сторонними оболочками.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Найдите трек или альбом в каталоге и откройте его в Music.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
