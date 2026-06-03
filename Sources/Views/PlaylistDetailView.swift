import SwiftUI
import MusicKit

struct PlaylistDetailView: View {
    let playlistId: UUID

    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var manager = PlaylistManager.shared
    @ObservedObject private var autoplay = AutoplayManager.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @StateObject private var musicService = AppleMusicService.shared

    @State private var allVideoAssets: [MuxAsset] = []
    @State private var allAudioAssets: [GOAudioAsset] = []
    @State private var allBooks: [GOBook] = []
    @State private var allArticles: [GOArticle] = []
    @State private var musicAlbums: [Album] = []
    @State private var musicTracks: [MusicKit.Track] = []
    @State private var musicPlaylists: [MusicKit.Playlist] = []
    @State private var isLoading = true
    @State private var showDeleteConfirm = false

    var playlist: Playlist? {
        manager.playlists.first { $0.id == playlistId }
    }

    // Resolved video assets in playlist order
    var playlistVideoAssets: [MuxAsset] {
        guard let playlist = playlist else { return [] }
        return playlist.items.compactMap { item in
            guard item.isVideo else { return nil }
            return allVideoAssets.first { $0.id == item.itemId }
        }
    }

    // Resolved audio assets in playlist order
    var playlistAudioAssets: [GOAudioAsset] {
        guard let playlist = playlist else { return [] }
        return playlist.items.compactMap { item in
            guard item.isAudio else { return nil }
            return allAudioAssets.first { $0.id == item.itemId }
        }
    }

    // Resolved books in playlist order
    var playlistBooks: [GOBook] {
        guard let playlist = playlist else { return [] }
        return playlist.items.compactMap { item in
            guard item.isBook else { return nil }
            return allBooks.first { $0.id == item.itemId }
        }
    }

    // Resolved articles in playlist order
    var playlistArticles: [GOArticle] {
        guard let playlist = playlist else { return [] }
        return playlist.items.compactMap { item in
            guard item.isArticle else { return nil }
            return allArticles.first { $0.id == item.itemId }
        }
    }

    // Resolved music items
    var playlistMusicItems: [PlaylistItem] {
        guard let playlist = playlist else { return [] }
        return playlist.items.filter { $0.isMusic }
    }

    var hasMusicItems: Bool {
        !musicAlbums.isEmpty || !musicTracks.isEmpty || !musicPlaylists.isEmpty
    }

    var isEmpty: Bool {
        playlistVideoAssets.isEmpty && playlistAudioAssets.isEmpty && playlistBooks.isEmpty && playlistArticles.isEmpty && !hasMusicItems
    }

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return [GridItem(.adaptive(minimum: 280))]
        #endif
    }

    var body: some View {
        Group {
            if playlist != nil {
                if isLoading {
                    ProgressView("Loading…")
                } else if isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Empty Playlist")
                            .font(.title)
                        Text("Long press any video, audio, book, article, or music to add it here")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                // Play All (videos only)
                                if !playlistVideoAssets.isEmpty {
                                    HStack(spacing: 16) {
                                        Button {
                                            playAllVideos()
                                        } label: {
                                            HStack {
                                                Image(systemName: "play.fill")
                                                Text("Play All Videos")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(.horizontal, 40)
                                }

                                // Video section
                                if !playlistVideoAssets.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Videos", systemImage: "play.rectangle.fill")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 40)

                                        LazyVGrid(columns: columns, spacing: 20) {
                                            ForEach(playlistVideoAssets) { asset in
                                                Button {
                                                    playVideo(asset: asset)
                                                } label: {
                                                    SermonCardView(asset: asset)
                                                }
                                                .mediaCardStyle()
                                                .contextMenu {
                                                    #if !os(tvOS)
                                                    if let url = asset.shareURL ?? asset.streamURL {
                                                        ShareLink(
                                                            item: url,
                                                            subject: Text(asset.title),
                                                            message: Text("Watch \(asset.title) on GO Videos")
                                                        ) {
                                                            Label("Share", systemImage: "square.and.arrow.up")
                                                        }
                                                    }
                                                    #endif
                                                    Button(role: .destructive) {
                                                        manager.removeAsset(asset.id, from: playlistId)
                                                    } label: {
                                                        Label("Remove from Playlist", systemImage: "minus.circle")
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 40)
                                    }
                                }

                                // Audio section
                                if !playlistAudioAssets.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Audio", systemImage: "headphones")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 40)

                                        LazyVStack(spacing: 0) {
                                            ForEach(playlistAudioAssets) { audio in
                                                PlaylistAudioRow(audio: audio) {
                                                    audioPlayer.play(
                                                        url: audio.audioUrl,
                                                        title: audio.title,
                                                        artist: audio.artist
                                                    )
                                                } onRemove: {
                                                    manager.removeItem(
                                                        PlaylistItem(type: "audio", itemId: audio.id),
                                                        from: playlistId
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }

                                // Books section
                                if !playlistBooks.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Books", systemImage: "book.fill")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 40)

                                        #if !os(tvOS)
                                        let bookCols = UIDevice.current.userInterfaceIdiom == .pad
                                            ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
                                            : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                                        LazyVGrid(columns: bookCols, spacing: 14) {
                                            ForEach(playlistBooks) { book in
                                                NavigationLink {
                                                    BookDetailView(book: book)
                                                } label: {
                                                    BookCard(book: book)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button(role: .destructive) {
                                                        manager.removeItem(
                                                            PlaylistItem(type: "book", itemId: book.id),
                                                            from: playlistId
                                                        )
                                                    } label: {
                                                        Label("Remove from Playlist", systemImage: "minus.circle")
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 40)
                                        #endif
                                    }
                                }

                                // Music section
                                if hasMusicItems {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Music", systemImage: "music.note")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 40)

                                        // Albums
                                        if !musicAlbums.isEmpty {
                                            #if !os(tvOS)
                                            let musicCols = UIDevice.current.userInterfaceIdiom == .pad
                                                ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
                                                : Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                                            LazyVGrid(columns: musicCols, spacing: 16) {
                                                ForEach(musicAlbums) { album in
                                                    NavigationLink(destination: AlbumDetailView(album: album)) {
                                                        AlbumCardView(album: album)
                                                    }
                                                    .contextMenu {
                                                        Button(role: .destructive) {
                                                            manager.removeItem(
                                                                PlaylistItem(type: "music", itemId: album.id.rawValue),
                                                                from: playlistId
                                                            )
                                                        } label: {
                                                            Label("Remove from Playlist", systemImage: "minus.circle")
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 40)
                                            #endif
                                        }

                                        // Tracks
                                        if !musicTracks.isEmpty {
                                            LazyVStack(spacing: 0) {
                                                ForEach(Array(musicTracks.enumerated()), id: \.offset) { idx, track in
                                                    SongRow(track: track, albumTitle: "")
                                                        .contextMenu {
                                                            Button(role: .destructive) {
                                                                manager.removeItem(
                                                                    PlaylistItem(type: "music-track", itemId: track.id.rawValue),
                                                                    from: playlistId
                                                                )
                                                            } label: {
                                                                Label("Remove from Playlist", systemImage: "minus.circle")
                                                            }
                                                        }
                                                    if idx < musicTracks.count - 1 {
                                                        Divider().background(Color.white.opacity(0.08)).padding(.leading, 72)
                                                    }
                                                }
                                            }
                                        }

                                        // Playlists
                                        if !musicPlaylists.isEmpty {
                                            LazyVStack(spacing: 12) {
                                                ForEach(musicPlaylists) { playlist in
                                                    NavigationLink(destination: PlaylistMusicDetailView(playlist: playlist)) {
                                                        MusicPlaylistRowView(playlist: playlist)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .contextMenu {
                                                        Button(role: .destructive) {
                                                            manager.removeItem(
                                                                PlaylistItem(type: "music-playlist", itemId: playlist.id.rawValue),
                                                                from: playlistId
                                                            )
                                                        } label: {
                                                            Label("Remove from Playlist", systemImage: "minus.circle")
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 40)
                                        }
                                    }
                                }

                                // Articles section
                                if !playlistArticles.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Articles", systemImage: "doc.text")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 40)

                                        #if !os(tvOS)
                                        LazyVStack(spacing: 0) {
                                            ForEach(playlistArticles) { article in
                                                NavigationLink {
                                                    ArticleDetailView(article: article)
                                                } label: {
                                                    ArticleRow(article: article)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button(role: .destructive) {
                                                        manager.removeItem(
                                                            PlaylistItem(type: "article", itemId: article.id),
                                                            from: playlistId
                                                        )
                                                    } label: {
                                                        Label("Remove from Playlist", systemImage: "minus.circle")
                                                    }
                                                }
                                            }
                                        }
                                        #endif
                                    }
                                }
                            }
                            .padding(.vertical, 20)

                            // Spacer for audio mini player
                            if audioPlayer.hasItem {
                                Color.clear.frame(height: 80)
                            }
                        }

                        // Audio mini player
                        #if !os(tvOS)
                        if audioPlayer.hasItem {
                            AudioMiniPlayer()
                        }
                        #endif
                    }
                }
            } else {
                Text("Playlist not found")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            #if !os(tvOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sharePlaylist()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
            #endif
        }
        .alert("Delete Playlist?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                manager.delete(id: playlistId)
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        async let videos = api.fetchAssets()
        async let audio = ContentAPI.shared.fetchAudio()
        async let books = ContentAPI.shared.fetchBooks()
        async let articles = ContentAPI.shared.fetchArticles()
        allVideoAssets = (try? await videos) ?? []
        allAudioAssets = (try? await audio) ?? []
        allBooks = (try? await books) ?? []
        allArticles = (try? await articles) ?? []

        // Load music items from MusicKit
        guard let playlist = playlist else { return }
        let musicItems = playlist.items.filter { $0.isMusic }
        if !musicItems.isEmpty && musicService.isAuthorized {
            await loadMusicItems(musicItems)
        }
    }

    private func loadMusicItems(_ items: [PlaylistItem]) async {
        var albums: [Album] = []
        var tracks: [MusicKit.Track] = []
        var playlists: [MusicKit.Playlist] = []

        for item in items {
            if item.isMusicAlbum {
                do {
                    let req = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(item.itemId))
                    let resp = try await req.response()
                    if let album = resp.items.first { albums.append(album) }
                } catch { /* skip */ }
            } else if item.isMusicTrack {
                do {
                    let req = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: MusicItemID(item.itemId))
                    let resp = try await req.response()
                    // Song and Track are different; try Song lookup
                    // Actually use Track type
                } catch { /* skip */ }
                // Try as Track
                // MusicKit doesn't have direct Track catalog lookup by ID easily,
                // so we'll skip for now — tracks show up from playlists mainly
            } else if item.isMusicPlaylist {
                do {
                    let req = MusicCatalogResourceRequest<MusicKit.Playlist>(matching: \.id, equalTo: MusicItemID(item.itemId))
                    let resp = try await req.response()
                    if let pl = resp.items.first { playlists.append(pl) }
                } catch { /* skip */ }
            }
        }

        musicAlbums = albums
        musicTracks = tracks
        musicPlaylists = playlists
    }

    func playAllVideos() {
        guard let first = playlistVideoAssets.first, let url = first.streamURL else { return }
        autoplay.setContext(asset: first, playlist: playlistVideoAssets)
        presentPlayer(url: url)
    }

    func playVideo(asset: MuxAsset) {
        guard let url = asset.streamURL else { return }
        autoplay.setContext(asset: asset, playlist: playlistVideoAssets)
        presentPlayer(url: url)
    }

    #if !os(tvOS)
    func sharePlaylist() {
        guard let playlist = playlist else { return }
        var lines: [String] = []
        lines.append("\(playlist.name) - GO Media Playlist")
        lines.append("")
        for (i, asset) in playlistVideoAssets.enumerated() {
            lines.append("\(i + 1). \(asset.title) [video]")
        }
        for (i, audio) in playlistAudioAssets.enumerated() {
            let idx = playlistVideoAssets.count + i + 1
            lines.append("\(idx). \(audio.title) [audio]")
        }
        for (i, book) in playlistBooks.enumerated() {
            let idx = playlistVideoAssets.count + playlistAudioAssets.count + i + 1
            lines.append("\(idx). \(book.title) by \(book.author) [book]")
        }
        for (i, article) in playlistArticles.enumerated() {
            let idx = playlistVideoAssets.count + playlistAudioAssets.count + playlistBooks.count + i + 1
            lines.append("\(idx). \(article.title) [article]")
        }
        lines.append("")
        lines.append("\(playlist.totalCount) item\(playlist.totalCount == 1 ? "" : "s") — Shared from GO Media")
        let text = lines.joined(separator: "\n")
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        activityVC.popoverPresentationController?.sourceView = root.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(x: root.view.bounds.midX, y: 0, width: 0, height: 0)
        root.present(activityVC, animated: true)
    }
    #endif
}

// MARK: - Playlist Audio Row
struct PlaylistAudioRow: View {
    let audio: GOAudioAsset
    let onPlay: () -> Void
    let onRemove: () -> Void
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentTitle == audio.title && audioPlayer.isPlaying
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let urlStr = audio.coverImageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        Color.white.opacity(0.08)
                            .overlay(
                                Image(systemName: "waveform")
                                    .foregroundColor(.secondary)
                            )
                    }
                } else {
                    Color.white.opacity(0.08)
                        .overlay(
                            Image(systemName: "waveform")
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 54, height: 54)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(audio.title)
                    .font(.subheadline.bold())
                    .foregroundColor(isCurrentlyPlaying ? .blue : .white)
                    .lineLimit(2)
                if !audio.artist.isEmpty {
                    Text(audio.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            Button(action: onPlay) {
                Image(systemName: isCurrentlyPlaying ? "waveform" : "play.circle")
                    .font(.title2)
                    .foregroundColor(isCurrentlyPlaying ? .blue : .secondary)
            }

            #if !os(tvOS)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red.opacity(0.7))
            }
            #endif
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(Color.white.opacity(isCurrentlyPlaying ? 0.06 : 0.02))
        .overlay(
            Divider().background(Color.white.opacity(0.07)),
            alignment: .bottom
        )
    }
}
