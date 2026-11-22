import AppKit
import CadenceCore
import SwiftUI

struct MusicPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let actions: Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    init(_ title: String, subtitle: String? = nil) where Actions == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.actions = EmptyView()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            actions
        }
    }
}

struct TrackList: View {
    let tracks: [MusicTrack]
    var showAlbum = true
    var showHeader = false
    var contextTitle: String = ""
    var onPlay: ((MusicTrack) -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @State private var selectedID: Int?

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                header
            }
            LazyVStack(spacing: 0) {
                ForEach(tracks) { track in
                    TrackRow(
                        track: track,
                        showAlbum: showAlbum,
                        isSelected: selectedID == track.id,
                        contextTitle: contextTitle,
                        onPlay: {
                            selectedID = track.id
                            if let onPlay {
                                onPlay(track)
                            } else {
                                model.play(track: track)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedID = track.id
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 36)
            Text("Название")
                .frame(maxWidth: .infinity, alignment: .leading)
            if showAlbum {
                Text("Альбом")
                    .frame(width: 180, alignment: .leading)
            }
            Color.clear.frame(width: 26)
            Text("Время")
                .frame(width: 44, alignment: .trailing)
            Color.clear.frame(width: 26)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }
}

struct TrackRow: View {
    let track: MusicTrack
    var showAlbum = true
    var isSelected = false
    var contextTitle: String = ""
    var onPlay: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var music: MusicController
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var hovering = false
    @State private var image: NSImage?

    private var isCurrent: Bool { music.state.databaseID == track.id }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ArtworkImage(
                    image: image,
                    seed: track.artworkKey,
                    size: 32,
                    cornerRadius: 5
                )
                if hovering || (isCurrent && music.state.isPlaying) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(hovering ? 0.38 : 0.24))
                        .frame(width: 32, height: 32)
                    Image(systemName: isCurrent && music.state.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 32)
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.musicAccent : .primary)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showAlbum {
                Text(track.displayAlbum)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)
            }

            Group {
                if track.favorited {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.musicAccent)
                        .help("В любимых")
                } else {
                    Color.clear
                }
            }
            .frame(width: 26, height: 26)

            Text(track.duration.musicDurationText)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)

            Menu {
                Button("Играть") { model.play(track: track) }
                Button("Показать в Music") { model.reveal(track: track) }
                Divider()
                Button("Скопировать название") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(track.title) — \(track.displayArtist)", forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Color.secondary : Color.clear)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.045)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .contextMenu {
            Button("Играть") { model.play(track: track) }
            Button("Показать в Music") { model.reveal(track: track) }
            Divider()
            Button("Скопировать название") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(track.title) — \(track.displayArtist)", forType: .string)
            }
        }
        .task(id: "\(track.artworkKey)-\(artwork.revision)") {
            image = await artwork.image(forAlbumKey: track.artworkKey, trackID: track.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.displayArtist), \(track.displayAlbum), \(track.duration.musicDurationText)")
        .accessibilityAction(named: "Играть", onPlay)
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.075) }
        if hovering { return Color.primary.opacity(0.045) }
        return .clear
    }
}

struct AlbumGrid: View {
    let albums: [MusicAlbum]
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 158, maximum: 182), spacing: 20)],
            alignment: .leading,
            spacing: 24
        ) {
            ForEach(albums) { album in
                AlbumCard(album: album)
            }
        }
    }
}

struct AlbumCard: View {
    let album: MusicAlbum
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var hovering = false
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkImage(image: image, seed: album.id, size: 166, cornerRadius: 10)
                .frame(width: 166, height: 166)
                .shadow(color: .black.opacity(hovering ? 0.24 : 0.14), radius: hovering ? 14 : 8, y: hovering ? 7 : 3)
                .scaleEffect(hovering ? 1.018 : 1)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        Button {
                            model.play(album: album)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.musicAccent, in: Circle())
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .help("Играть альбом")
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 166, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectMusic(.album(album.id))
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Играть") { model.play(album: album) }
            Button("Перемешать") { model.play(album: album, shuffle: true) }
            Divider()
            Button("Открыть альбом") { model.selectMusic(.album(album.id)) }
        }
        .task(id: "\(album.id)-\(artwork.revision)") {
            image = await artwork.image(for: album)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title), \(album.artist)")
        .accessibilityAction(named: Text("Играть")) { model.play(album: album) }
    }
}

struct PlaylistGrid: View {
    let playlists: [MusicPlaylist]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 158, maximum: 182), spacing: 20)],
            alignment: .leading,
            spacing: 24
        ) {
            ForEach(playlists) { playlist in
                PlaylistCard(playlist: playlist)
            }
        }
    }
}

struct PlaylistCard: View {
    let playlist: MusicPlaylist
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var hovering = false
    @State private var image: NSImage?

    private var firstTrack: MusicTrack? {
        guard let library = model.library else { return nil }
        return library.tracks(in: playlist).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkImage(
                image: image,
                seed: playlist.name,
                size: 166,
                cornerRadius: 10,
                systemImage: "music.note.list"
            )
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.12), radius: hovering ? 13 : 7, y: 3)
            .scaleEffect(hovering ? 1.018 : 1)
            .animation(.easeOut(duration: 0.14), value: hovering)
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(RU.tracks(playlist.trackCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 166, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectMusic(.playlist(playlist.id)) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Играть") { model.play(playlist: playlist) }
            Button("Открыть плейлист") { model.selectMusic(.playlist(playlist.id)) }
        }
        .task(id: "\(playlist.id)-\(artwork.revision)") {
            guard let firstTrack else { return }
            image = await artwork.image(forAlbumKey: firstTrack.artworkKey, trackID: firstTrack.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(RU.tracks(playlist.trackCount))")
    }
}

struct ArtistGrid: View {
    let artists: [MusicArtist]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 142, maximum: 168), spacing: 18)],
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(artists) { artist in
                ArtistCard(artist: artist)
            }
        }
    }
}

struct ArtistCard: View {
    let artist: MusicArtist
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    private var initial: String {
        String(artist.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Theme.artworkGradient(for: artist.id))
                Text(initial.isEmpty ? "♪" : initial)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 92, height: 92)
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.10), radius: hovering ? 12 : 6, y: 3)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.14), value: hovering)
            VStack(spacing: 1) {
                Text(artist.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(RU.albums(artist.albumCount))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.selectMusic(.artist(artist.name)) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Открыть исполнителя") { model.selectMusic(.artist(artist.name)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artist.name), \(RU.albums(artist.albumCount))")
    }
}

struct CatalogResultRow: View {
    let item: CatalogItem
    var open: () -> Void
    @EnvironmentObject private var artwork: ArtworkStore
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ArtworkImage(image: image, seed: item.id, size: 42, cornerRadius: 7, systemImage: "music.note")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(item.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let collection = item.collectionName, collection != item.title {
                Text(collection)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
            Button("Открыть в Music", action: open)
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .task(id: item.id) {
            image = await artwork.remoteImage(url: item.largeArtworkURL)
        }
    }
}
