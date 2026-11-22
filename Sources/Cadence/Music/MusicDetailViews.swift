import AppKit
import CadenceCore
import SwiftUI

private struct DetailBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AlbumDetailView: View {
    let album: MusicAlbum
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var image: NSImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailBackButton(title: "Альбомы") {
                    model.selectMusic(.albums)
                }

                header
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

                TrackList(tracks: album.tracks, showAlbum: false, showHeader: true)
                    .cardSurface()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: "\(album.id)-\(artwork.revision)") {
            image = await artwork.image(for: album)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ArtworkImage(image: image, seed: album.id, size: 178, cornerRadius: 14)
                .shadow(color: .black.opacity(0.24), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 7) {
                Text("АЛЬБОМ")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.musicAccent)
                Text(album.title)
                    .font(.system(size: 29, weight: .bold))
                    .lineLimit(2)
                Button {
                    if !album.artist.isEmpty {
                        model.selectMusic(.artist(album.artist))
                    }
                } label: {
                    Text(album.artist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                    Button("Показать в Music") {
                        if let first = album.tracks.first {
                            model.reveal(track: first)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
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

struct ArtistDetailView: View {
    let artist: MusicArtist
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailBackButton(title: "Исполнители") {
                    model.selectMusic(.artists)
                }

                header
                    .padding(20)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.regularMaterial)
                            LinearGradient(
                                colors: [Theme.podcastAccent.opacity(0.14), Color.clear],
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

                if !artist.albums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Альбомы")
                            .font(.system(size: 16, weight: .semibold))
                        AlbumGrid(albums: artist.albums)
                    }
                }

                if !artist.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Песни")
                            .font(.system(size: 16, weight: .semibold))
                        TrackList(tracks: Array(artist.tracks.prefix(12)), showAlbum: true, showHeader: false)
                            .cardSurface()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ArtistAvatar(artist: artist)
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 7) {
                Text("ИСПОЛНИТЕЛЬ")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.podcastAccent)
                Text(artist.name)
                    .font(.system(size: 29, weight: .bold))
                    .lineLimit(2)
                Text("\(RU.albums(artist.albumCount)) · \(RU.tracks(artist.trackCount))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    PillButton(title: "Играть", systemImage: "play.fill") {
                        model.play(tracks: artist.tracks)
                    }
                    PillButton(title: "Перемешать", systemImage: "shuffle", filled: false) {
                        model.play(tracks: artist.tracks, shuffle: true)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ArtistAvatar: View {
    let artist: MusicArtist
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var image: NSImage?

    private var initial: String {
        String(artist.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle().fill(Theme.artworkGradient(for: artist.id))
                Text(initial.isEmpty ? "♪" : initial)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .task(id: "\(artist.id)-\(artwork.revision)") {
            if let album = artist.albums.first {
                image = await artwork.image(for: album)
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: MusicPlaylist
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var image: NSImage?

    private var tracks: [MusicTrack] {
        model.library?.tracks(in: playlist) ?? []
    }

    private var firstTrack: MusicTrack? {
        tracks.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailBackButton(title: "Плейлисты") {
                    model.selectMusic(.playlists)
                }

                header
                    .padding(20)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.regularMaterial)
                            LinearGradient(
                                colors: [Theme.podcastAccent.opacity(0.14), Color.clear],
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

                if tracks.isEmpty {
                    EmptyStateView(
                        systemImage: "music.note.list",
                        title: "Плейлист пуст",
                        message: "Добавьте треки в плейлист в Music."
                    )
                    .frame(height: 220)
                } else {
                    TrackList(tracks: tracks, showAlbum: true, showHeader: true)
                        .cardSurface()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: "\(playlist.id)-\(artwork.revision)") {
            if let firstTrack {
                image = await artwork.image(forAlbumKey: firstTrack.artworkKey, trackID: firstTrack.id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ArtworkImage(
                image: image,
                seed: playlist.name,
                size: 178,
                cornerRadius: 14,
                systemImage: "music.note.list"
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 7) {
                Text("ПЛЕЙЛИСТ")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.podcastAccent)
                Text(playlist.name)
                    .font(.system(size: 29, weight: .bold))
                    .lineLimit(2)
                Text("\(RU.tracks(tracks.count)) · \(totalDuration.musicDurationText)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    PillButton(title: "Играть", systemImage: "play.fill") {
                        model.play(playlist: playlist)
                    }
                    PillButton(title: "Перемешать", systemImage: "shuffle", filled: false) {
                        model.play(tracks: tracks, shuffle: true)
                    }
                    Button("Открыть Music") {
                        model.openMusicApp()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
}
