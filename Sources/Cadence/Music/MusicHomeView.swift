import AppKit
import CadenceCore
import SwiftUI

struct MusicHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var artwork: ArtworkStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let library = model.library {
                    let featured = library.recentlyAddedAlbums.first(where: { $0.trackCount >= 4 })
                        ?? library.albums.max(by: { $0.trackCount < $1.trackCount })
                        ?? library.recentlyAddedAlbums.first
                    if let featured {
                        HeroAlbumCard(album: featured)
                    }

                    let recent = Array(library.recentlyAddedAlbums.prefix(8))
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Недавно добавленные", actionTitle: "Все альбомы") {
                                model.selectMusic(.albums)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 18) {
                                    ForEach(recent) { album in
                                        AlbumCard(album: album)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    let frequent = Array(library.frequentlyPlayed.prefix(6))
                    if !frequent.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Часто играет", actionTitle: "Все песни") {
                                model.selectMusic(.songs)
                            }
                            TrackList(tracks: frequent, showAlbum: false, showHeader: false)
                                .cardSurface()
                        }
                    }

                    if !library.favoriteTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Любимые песни", actionTitle: "Все песни") {
                                model.selectMusic(.songs)
                            }
                            TrackList(tracks: Array(library.favoriteTracks.prefix(5)), showAlbum: false, showHeader: false)
                                .cardSurface()
                        }
                    }

                    if !library.userPlaylists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Плейлисты", actionTitle: "Все плейлисты") {
                                model.selectMusic(.playlists)
                            }
                            PlaylistGrid(playlists: Array(library.userPlaylists.prefix(5)))
                        }
                    }
                } else {
                    libraryPlaceholder
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        MusicPageHeader(
            "Медиатека",
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
                PillButton(title: "Music", systemImage: "arrow.up.forward.app", filled: false) {
                    model.openMusicApp()
                }
            }
        }
    }

    private var subtitle: String {
        guard let library = model.library else {
            if model.libraryStatus == .loading { return "Читаем медиатеку…" }
            return "Fast Apple Music и подкасты"
        }
        return "\(RU.tracks(library.snapshot.tracks.count)) · \(RU.albums(library.albums.count)) · \(library.totalDuration.musicDurationText)"
    }

    @ViewBuilder
    private var libraryPlaceholder: some View {
        if model.libraryStatus == .loading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Читаем медиатеку из Music…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            ConnectMusicCard()
        }
    }
}

private struct HeroAlbumCard: View {
    let album: MusicAlbum
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 22) {
            ArtworkImage(image: image, seed: album.id, size: 172, cornerRadius: 14)
                .shadow(color: .black.opacity(0.24), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("НЕДАВНО ДОБАВЛЕНО")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.musicAccent)
                Text(album.title)
                    .font(.system(size: 27, weight: .bold))
                    .lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    PillButton(title: "Играть", systemImage: "play.fill") {
                        model.play(album: album)
                    }
                    PillButton(title: "Перемешать", systemImage: "shuffle", filled: false) {
                        model.play(album: album, shuffle: true)
                    }
                    Button("Открыть альбом") {
                        model.selectMusic(.album(album.id))
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                LinearGradient(
                    colors: [Theme.musicAccent.opacity(0.15), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .task(id: "\(album.id)-\(artwork.revision)") {
            image = await artwork.image(for: album)
        }
    }

    private var metadata: String {
        var parts: [String] = []
        if album.year > 0 { parts.append(String(album.year)) }
        parts.append(RU.tracks(album.trackCount))
        parts.append(album.duration.musicDurationText)
        return parts.joined(separator: " · ")
    }
}

private struct ConnectMusicCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.musicAccent)
                    .frame(width: 58, height: 58)
                    .background(Theme.musicAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Подключите Music")
                        .font(.system(size: 20, weight: .bold))
                    Text("Cadence управляет Music.app — так Apple разрешает воспроизведение по подписке. Разрешение нужно один раз.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Нажмите «Подключить Music».")
                step(2, "Разрешите Cadence управлять Music в системном запросе.")
                step(3, "Медиатека и обложки появятся автоматически.")
            }

            HStack(spacing: 8) {
                PillButton(title: "Подключить Music", systemImage: "link") {
                    model.connectMusic()
                }
                PillButton(title: "Настройки автоматизации", systemImage: "gearshape", filled: false) {
                    model.openAutomationSettings()
                }
                PillButton(title: "Открыть Music", systemImage: "arrow.up.forward.app", filled: false) {
                    model.openMusicApp()
                }
            }

            if let error = model.libraryError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(22)
        .cardSurface(cornerRadius: 18)
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Theme.musicAccent, in: Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
