import SwiftUI
import MusicKit

#if os(tvOS)
// White-outline focus style for album cards — no oversized highlight
struct TVPlainAlbumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif

extension MusicAuthorization.Status {
    var description: String {
        switch self {
        case .authorized:      return "Authorized ✓"
        case .denied:          return "Denied — check Settings"
        case .notDetermined:   return "Not yet requested"
        case .restricted:      return "Restricted"
        @unknown default:      return "Unknown"
        }
    }
}

// Add album IDs here to curate the music section
// Find IDs: search Apple Music in browser, the ID is the number in the URL
// e.g. https://music.apple.com/us/album/amazing-grace/123456789 → "123456789"
struct CuratedMusic {
    // Add Apple Music album IDs here
    // Find IDs: search Apple Music in browser, the ID is the number in the URL
    // e.g. https://music.apple.com/us/album/amazing-grace/123456789 → "123456789"
    static let albumIDs: [String] = [
        "1887383546", // Your Word Is a Lamp
        "1841667676", // Gospel Outreach Scripture Songs
        "1831598367", // On the Carousel
        "1811597280", // Sing Choirs of Angels
        "1750051715", // Lullabies
        "1811680979", // I Am Always with You
        "1750085812", // New Mercies
        "6766344106", // I Am Pressing On (Single)
        "1889967963", // My Father's World (Single)
        "1882054119", // Great Is the Lord (Single)
        "724376682",  // Far Away Places
        "724482211",  // Hymns II
        "724693225",  // Hymns Instrumental
        "724606076",  // Night Light
        "715990922",  // The Roar of Love
        "723893734",  // Singer Sower
        "1167738867", // Encores
        "724642282",  // Rejoice
        "724076458",  // Mansion Builder
        "715917383",  // How the West Was One
        "1167728908", // To the Bride
        "1841979336", // In the Volume of the Book
        "1841979100", // With Footnotes
    ]

    static let playlistIDs: [String] = [
        // Managed via admin portal (Firebase config/music.playlists)
    ]
}

struct AppleMusicView: View {
    @StateObject private var music = AppleMusicService.shared
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var showAsList = false
    @State private var songs: [(album: Album, track: MusicKit.Track)] = []

    enum MusicSegment: String, CaseIterable {
        case albums = "Albums"
        case songs = "Songs"
        case artists = "Artists"
        case playlists = "Playlists"
    }
    @State private var segment: MusicSegment = .albums
    @State private var musicSearchText = ""
    @State private var activeLoadTask: Task<Void, Never>? = nil
    @State private var curatedPlaylists: [MusicKit.Playlist] = []
    @State private var playlistsLoading = false
    @State private var musicConfig: MusicConfig? = nil
    @State private var artists: [ArtistGroup] = []
    @State private var addToPlaylistItem: PlaylistItem? = nil
    @State private var showAddToPlaylist = false
    @State private var showAddCustomPlaylist = false
    @State private var customPlaylistLink = ""
    @State private var customPlaylistError: String?
    @State private var userPlaylists: [MusicKit.Playlist] = []

    var body: some View {
        ZStack {
            Color.clear
            if !music.isAuthorized {
                authPromptView
            } else if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading music...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Cancel") {
                        activeLoadTask?.cancel()
                        activeLoadTask = nil
                        isLoading = false
                        loadError = "Cancelled — tap Retry to try again."
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(err)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadError = nil
                        activeLoadTask = Task { await loadCurated() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if albums.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .navigationTitle("Listen")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if music.authStatus == .notDetermined {
                await music.requestAuthorization()
            }
            if music.isAuthorized {
                activeLoadTask = Task { await loadCurated() }
                await activeLoadTask?.value
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let item = addToPlaylistItem {
                AddToPlaylistView(mediaType: item.type, mediaId: item.itemId)
            }
        }
    }

    // MARK: - Auth Prompt

    var authPromptView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.pink)
            }

            Text("Apple Music")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Connect your Apple Music account\nto listen to worship music.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            // Status label
            Text("Status: \(music.authStatus.description)")
                .font(.caption)
                .foregroundColor(.secondary)

            if music.authStatus == .denied {
                #if os(tvOS)
                Text("Access was denied. Go to\nSettings → Apps → GO Media → Apple Music")
                    .font(.callout)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                #else
                Text("Go to Settings → GO Media → Allow Apple Music")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                #endif
            }

            // Always show connect button so user can retry
            Button {
                Task {
                    await music.requestAuthorization()
                    if music.isAuthorized {
                        await loadCurated()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "music.note")
                    Text(music.authStatus == .denied ? "Try Again" : "Connect Apple Music")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Empty State

    var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 50))
                .foregroundColor(.pink.opacity(0.6))

            Text("Coming Soon")
                .font(.title3.bold())
                .foregroundColor(.white)

            Text("Worship music will be added here soon.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Content

    private var filteredAlbums: [Album] {
        guard !musicSearchText.isEmpty else { return albums }
        let q = musicSearchText.lowercased()
        return albums.filter {
            $0.title.lowercased().contains(q) ||
            $0.artistName.lowercased().contains(q)
        }
    }

    private var filteredSongs: [(album: Album, track: MusicKit.Track)] {
        guard !musicSearchText.isEmpty else { return songs }
        let q = musicSearchText.lowercased()
        return songs.filter {
            $0.track.title.lowercased().contains(q) ||
            $0.track.artistName.lowercased().contains(q) ||
            $0.album.title.lowercased().contains(q)
        }
    }

    var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Now Playing bar
                if music.isPlaying, let title = music.nowPlayingTitle {
                    NowPlayingBar(title: title)
                        .padding(.horizontal, 16)
                }

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search music...", text: $musicSearchText)
                        .foregroundColor(.white)
                    if !musicSearchText.isEmpty {
                        Button { musicSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 16)

                // Segment: Albums / Songs / Artists / Playlists
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(MusicSegment.allCases, id: \.self) { s in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) { segment = s }
                                } label: {
                                    Text(s.rawValue)
                                        .font(.subheadline.weight(segment == s ? .bold : .medium))
                                        .foregroundColor(segment == s ? .white : .secondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(segment == s ? Color.pink.opacity(0.3) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()

                    if segment == .albums {
                        Button {
                            showAsList.toggle()
                        } label: {
                            Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if segment == .albums {
                    albumsSection
                } else if segment == .songs {
                    songsSection
                } else if segment == .artists {
                    artistsSection
                } else {
                    playlistsSection
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var albumsSection: some View {
        Group {
            let filtered = filteredAlbums
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(musicSearchText.isEmpty ? "No albums" : "No matching albums")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else if showAsList {
                VStack(spacing: 8) {
                    ForEach(filtered) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumListRow(album: album)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task {
                                    try? await MusicLibrary.shared.add(album)
                                }
                            } label: {
                                Label("Add to Apple Music Library", systemImage: "plus.circle")
                            }
                            Button {
                                addToPlaylistItem = PlaylistItem(type: "music", itemId: album.id.rawValue)
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to My Playlists", systemImage: "text.badge.plus")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                #if os(tvOS)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)
                #else
                let columns = UIDevice.current.userInterfaceIdiom == .pad
                    ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
                    : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                #endif

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filtered) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumCardView(album: album)
                        }
                        .contextMenu {
                            Button {
                                Task {
                                    try? await MusicLibrary.shared.add(album)
                                }
                            } label: {
                                Label("Add to Apple Music Library", systemImage: "plus.circle")
                            }
                            Button {
                                addToPlaylistItem = PlaylistItem(type: "music", itemId: album.id.rawValue)
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to My Playlists", systemImage: "text.badge.plus")
                            }
                        }
                        #if os(tvOS)
                        .buttonStyle(TVPlainAlbumButtonStyle())
                        #endif
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Artists Section

    private var filteredArtists: [ArtistGroup] {
        guard !musicSearchText.isEmpty else { return artists }
        let q = musicSearchText.lowercased()
        return artists.filter { $0.name.lowercased().contains(q) }
    }

    private var artistsSection: some View {
        Group {
            if artists.isEmpty {
                VStack(spacing: 12) {
                    ProgressView("Grouping by artist...")
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .task { buildArtistGroups() }
            } else if filteredArtists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No matching artists")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredArtists) { artist in
                        NavigationLink(destination: ArtistAlbumsView(artist: artist, addToPlaylistItem: $addToPlaylistItem, showAddToPlaylist: $showAddToPlaylist)) {
                            ArtistRowView(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func buildArtistGroups() {
        var grouped: [String: [Album]] = [:]
        for album in albums {
            let name = album.artistName.isEmpty ? "Unknown Artist" : album.artistName
            grouped[name, default: []].append(album)
        }
        artists = grouped.map { ArtistGroup(name: $0.key, albums: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Playlists Section

    private var playlistsSection: some View {
        Group {
            if playlistsLoading {
                VStack(spacing: 12) {
                    ProgressView("Loading playlists...")
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                LazyVStack(spacing: 12) {
                    // Add custom playlist button
                    Button { showAddCustomPlaylist = true } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.pink)
                            Text("Add a Playlist")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white.opacity(0.3))
                                .font(.caption)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    // Add playlist sheet
                    .sheet(isPresented: $showAddCustomPlaylist) {
                        addCustomPlaylistSheet
                    }

                    // Church playlists
                    ForEach(curatedPlaylists) { playlist in
                        NavigationLink(destination: PlaylistMusicDetailView(playlist: playlist)) {
                            MusicPlaylistRowView(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task {
                                    try? await MusicLibrary.shared.add(playlist)
                                }
                            } label: {
                                Label("Add to Apple Music Library", systemImage: "plus.circle")
                            }
                            Button {
                                addToPlaylistItem = PlaylistItem(type: "music-playlist", itemId: playlist.id.rawValue)
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to My Playlists", systemImage: "text.badge.plus")
                            }
                        }
                    }

                    // User-added playlists
                    if !userPlaylists.isEmpty {
                        Text("My Playlists")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        ForEach(userPlaylists) { playlist in
                            NavigationLink(destination: PlaylistMusicDetailView(playlist: playlist)) {
                                MusicPlaylistRowView(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task {
                                        try? await MusicLibrary.shared.add(playlist)
                                    }
                                } label: {
                                    Label("Add to Apple Music Library", systemImage: "plus.circle")
                                }
                                Button(role: .destructive) {
                                    removeUserPlaylist(playlist.id.rawValue)
                                } label: {
                                    Label("Remove from App", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 0)
            }
        }
        .task {
            if curatedPlaylists.isEmpty {
                await loadCuratedPlaylists()
            }
            await loadUserPlaylists()
        }
    }

    // MARK: - Add Custom Playlist Sheet

    private var addCustomPlaylistSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundColor(.pink)
                    Text("Add an Apple Music Playlist")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Paste a link to any Apple Music playlist")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                TextField("https://music.apple.com/...", text: $customPlaylistLink)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 20)

                if let err = customPlaylistError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Button {
                    Task { await addCustomPlaylist() }
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Playlist")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .disabled(customPlaylistLink.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .background(Color.black)
            .navigationTitle("Add Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        customPlaylistLink = ""
                        customPlaylistError = nil
                        showAddCustomPlaylist = false
                    }
                }
            }
        }
    }

    // MARK: - Custom Playlist Helpers

    private func addCustomPlaylist() async {
        customPlaylistError = nil
        let link = customPlaylistLink.trimmingCharacters(in: .whitespaces)

        // Extract playlist ID from Apple Music URL
        // Format: https://music.apple.com/us/playlist/name/pl.xxxxx
        guard let playlistId = extractPlaylistId(from: link) else {
            customPlaylistError = "Invalid Apple Music playlist link. Copy the link from Apple Music and paste it here."
            return
        }

        // Check if already added
        let saved = savedUserPlaylistIds()
        if saved.contains(playlistId) {
            customPlaylistError = "This playlist is already added."
            return
        }

        // Try to load it from Apple Music catalog
        do {
            let request = MusicCatalogResourceRequest<MusicKit.Playlist>(matching: \.id, equalTo: MusicItemID(playlistId))
            let response = try await request.response()
            guard let playlist = response.items.first else {
                customPlaylistError = "Playlist not found. Make sure the link is correct and the playlist is public."
                return
            }

            // Save to UserDefaults
            var ids = saved
            ids.append(playlistId)
            UserDefaults.standard.set(ids, forKey: "userMusicPlaylistIds")

            userPlaylists.append(playlist)
            customPlaylistLink = ""
            showAddCustomPlaylist = false
        } catch {
            customPlaylistError = "Could not load playlist: \(error.localizedDescription)"
        }
    }

    private func extractPlaylistId(from urlString: String) -> String? {
        // Handle full URLs: https://music.apple.com/.../pl.xxxxx
        if let url = URL(string: urlString),
           let lastComponent = url.pathComponents.last,
           lastComponent.hasPrefix("pl.") {
            return lastComponent
        }
        // Handle raw playlist IDs
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("pl.") {
            return trimmed
        }
        return nil
    }

    private func savedUserPlaylistIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: "userMusicPlaylistIds") ?? []
    }

    private func removeUserPlaylist(_ id: String) {
        var ids = savedUserPlaylistIds()
        ids.removeAll { $0 == id }
        UserDefaults.standard.set(ids, forKey: "userMusicPlaylistIds")
        userPlaylists.removeAll { $0.id.rawValue == id }
    }

    private func loadUserPlaylists() async {
        let ids = savedUserPlaylistIds()
        guard !ids.isEmpty else { return }
        var loaded: [MusicKit.Playlist] = []
        for id in ids {
            do {
                let request = MusicCatalogResourceRequest<MusicKit.Playlist>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                if let playlist = response.items.first {
                    loaded.append(playlist)
                }
            } catch { /* skip */ }
        }
        userPlaylists = loaded
    }

    private var songsSection: some View {
        Group {
            let filtered = filteredSongs
            if songs.isEmpty {
                VStack(spacing: 12) {
                    ProgressView("Loading songs...")
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .task { await loadSongs() }
            } else if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No matching songs")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { idx, item in
                        SongRow(track: item.track, albumTitle: item.album.title)
                            .contextMenu {
                                Button {
                                    addToPlaylistItem = PlaylistItem(type: "music-track", itemId: item.track.id.rawValue)
                                    showAddToPlaylist = true
                                } label: {
                                    Label("Add Song to My Playlists", systemImage: "text.badge.plus")
                                }
                                Button {
                                    addToPlaylistItem = PlaylistItem(type: "music", itemId: item.album.id.rawValue)
                                    showAddToPlaylist = true
                                } label: {
                                    Label("Add Album to My Playlists", systemImage: "rectangle.stack.badge.plus")
                                }
                            }
                        if idx < filtered.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 72)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func loadSongs() async {
        guard songs.isEmpty else { return }
        var allSongs: [(album: Album, track: MusicKit.Track)] = []
        for album in albums {
            do {
                let detail = try await album.with([.tracks])
                if let tracks = detail.tracks {
                    for track in tracks {
                        allSongs.append((album: album, track: track))
                    }
                }
            } catch { /* skip */ }
        }
        songs = allSongs.sorted { $0.track.title.localizedCaseInsensitiveCompare($1.track.title) == .orderedAscending }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 16)
    }

    // MARK: - Load

    func loadCurated() async {
        isLoading = true
        loadError = nil
        albums = []
        defer { isLoading = false }

        // Use preloaded music config, fallback to fetch, then hardcoded
        var albumIDs = CuratedMusic.albumIDs
        if let preloaded = ContentPreloader.shared.musicConfig {
            musicConfig = preloaded
            if let configAlbums = preloaded.albums, !configAlbums.isEmpty {
                albumIDs = configAlbums.map { $0.albumId }
            }
        } else {
            do {
                let config = try await ContentAPI.shared.fetchMusicConfig()
                musicConfig = config
                if let configAlbums = config.albums, !configAlbums.isEmpty {
                    albumIDs = configAlbums.map { $0.albumId }
                }
            } catch {
                // Fallback to hardcoded IDs
            }
        }

        // 20-second timeout — if catalog requests hang, bail out gracefully
        let loadTask = Task {
            await withTaskGroup(of: Album?.self) { group in
                for id in albumIDs {
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        do {
                            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
                            let response = try await request.response()
                            return response.items.first
                        } catch {
                            return nil
                        }
                    }
                }
                var result: [Album] = []
                for await album in group {
                    if let album { result.append(album) }
                }
                return result
            }
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            loadTask.cancel()
        }

        let loaded = await loadTask.value
        timeoutTask.cancel()

        if loadTask.isCancelled {
            loadError = "Timed out loading music. Check your Apple Music subscription and internet connection."
            return
        }

        albums = loaded.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        music.curatedAlbums = albums
    }

    // MARK: - Load Curated Playlists

    func loadCuratedPlaylists() async {
        playlistsLoading = true
        defer { playlistsLoading = false }

        // Get playlist IDs from config (already fetched) or Firestore
        var playlistIDs = CuratedMusic.playlistIDs
        if let config = musicConfig, let configPlaylists = config.playlists, !configPlaylists.isEmpty {
            playlistIDs = configPlaylists.map { $0.playlistId }
        } else {
            // Try fetching if not loaded yet
            do {
                let config = try await ContentAPI.shared.fetchMusicConfig()
                musicConfig = config
                if let configPlaylists = config.playlists, !configPlaylists.isEmpty {
                    playlistIDs = configPlaylists.map { $0.playlistId }
                }
            } catch { /* use hardcoded */ }
        }

        var loaded: [MusicKit.Playlist] = []
        await withTaskGroup(of: MusicKit.Playlist?.self) { group in
            for id in playlistIDs {
                group.addTask {
                    do {
                        let request = MusicCatalogResourceRequest<MusicKit.Playlist>(matching: \.id, equalTo: MusicItemID(id))
                        let response = try await request.response()
                        return response.items.first
                    } catch {
                        return nil
                    }
                }
            }
            for await playlist in group {
                if let playlist { loaded.append(playlist) }
            }
        }
        curatedPlaylists = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Album Card

struct AlbumCardView: View {
    let album: Album
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            GeometryReader { geo in
                    if let artwork = album.artwork {
                        ArtworkImage(artwork, width: geo.size.width)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.largeTitle)
                                    .foregroundColor(.white.opacity(0.4))
                            )
                    }
                }
                .aspectRatio(1, contentMode: .fit)

            Text(album.title)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .frame(minHeight: 34, alignment: .top)

            if !album.artistName.isEmpty {
                Text(album.artistName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.white : Color.white.opacity(0.1),
                        lineWidth: isFocused ? 3 : 1)
        )
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}

// MARK: - Album List Row (for list view)

struct AlbumListRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.4))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.body.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !album.artistName.isEmpty {
                    Text(album.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
}



// MARK: - Song Row

struct SongRow: View {
    let track: MusicKit.Track
    let albumTitle: String
    @StateObject private var music = AppleMusicService.shared

    var body: some View {
        Button {
            Task {
                do {
                    try await music.play(track: track)
                } catch {
                    print("Failed to play track: \(error)")
                }
            }
        } label: {
            HStack(spacing: 14) {
                // Track artwork
                if let artwork = track.artwork {
                    ArtworkImage(artwork, width: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(track.artistName) · \(albumTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let dur = track.duration {
                    let mins = Int(dur) / 60
                    let secs = Int(dur) % 60
                    Text(String(format: "%d:%02d", mins, secs))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "play.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Now Playing Bar

struct NowPlayingBar: View {
    let title: String
    @StateObject private var music = AppleMusicService.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundColor(.pink)

            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Button { music.skipPrevious() } label: {
                Image(systemName: "backward.fill")
                    .foregroundColor(.white)
            }

            Button { music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.white)
                    .font(.title3)
            }

            Button { music.skipNext() } label: {
                Image(systemName: "forward.fill")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Playlist Row View (for curated playlists list)

struct MusicPlaylistRowView: View {
    let playlist: MusicKit.Playlist

    var body: some View {
        HStack(spacing: 14) {
            if let artwork = playlist.artwork {
                ArtworkImage(artwork, width: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.title3)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let curator = playlist.curatorName, !curator.isEmpty {
                    Text(curator)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let desc = playlist.standardDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Playlist Detail View (shows tracks in a curated Apple Music playlist)

struct PlaylistMusicDetailView: View {
    let playlist: MusicKit.Playlist
    @StateObject private var music = AppleMusicService.shared
    @State private var tracks: [MusicKit.Track] = []
    @State private var isLoading = true
    @State private var addToPlaylistItem: PlaylistItem? = nil
    @State private var showAddToPlaylist = false

    var body: some View {
        ZStack {
            Color.clear.appBackground()

            if isLoading {
                ProgressView("Loading tracks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No tracks found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Playlist header
                        VStack(spacing: 12) {
                            if let artwork = playlist.artwork {
                                ArtworkImage(artwork, width: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Text(playlist.name)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            if let curator = playlist.curatorName, !curator.isEmpty {
                                Text("by \(curator)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            // Play All button
                            Button {
                                Task {
                                    do {
                                        try await music.playPlaylist(playlist)
                                    } catch {
                                        print("Failed to play playlist: \(error)")
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play All")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(Capsule())
                            }

                            Button {
                                Task {
                                    try? await MusicLibrary.shared.add(playlist)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Add to My Library")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 20)

                        // Tracks
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.offset) { idx, track in
                                SongRow(track: track, albumTitle: playlist.name)
                                    .contextMenu {
                                        Button {
                                            addToPlaylistItem = PlaylistItem(type: "music-track", itemId: track.id.rawValue)
                                            showAddToPlaylist = true
                                        } label: {
                                            Label("Add to My Playlists", systemImage: "text.badge.plus")
                                        }
                                    }
                                if idx < tracks.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.08))
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadTracks() }
        .sheet(isPresented: $showAddToPlaylist) {
            if let item = addToPlaylistItem {
                AddToPlaylistView(mediaType: item.type, mediaId: item.itemId)
            }
        }
    }

    private func loadTracks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detailed = try await playlist.with([.tracks])
            if let playlistTracks = detailed.tracks {
                tracks = Array(playlistTracks)
            }
        } catch {
            print("Failed to load playlist tracks: \(error)")
        }
    }
}

// MARK: - Artist Group Model

struct ArtistGroup: Identifiable {
    var id: String { name }
    let name: String
    let albums: [Album]

    var albumCount: Int { albums.count }
    var firstArtwork: Artwork? { albums.first?.artwork }
}

// MARK: - Artist Row View

struct ArtistRowView: View {
    let artist: ArtistGroup

    var body: some View {
        HStack(spacing: 14) {
            if let artwork = artist.firstArtwork {
                ArtworkImage(artwork, width: 56)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.4))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.body.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Artist Albums View (drill-in from artists list)

struct ArtistAlbumsView: View {
    let artist: ArtistGroup
    @Binding var addToPlaylistItem: PlaylistItem?
    @Binding var showAddToPlaylist: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Artist header
                VStack(spacing: 12) {
                    if let artwork = artist.firstArtwork {
                        ArtworkImage(artwork, width: 120)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white.opacity(0.4))
                            )
                    }
                    Text(artist.name)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                // Albums grid
                #if os(tvOS)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)
                #else
                let columns = UIDevice.current.userInterfaceIdiom == .pad
                    ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
                    : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                #endif

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(artist.albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumCardView(album: album)
                        }
                        .contextMenu {
                            Button {
                                Task {
                                    try? await MusicLibrary.shared.add(album)
                                }
                            } label: {
                                Label("Add to Apple Music Library", systemImage: "plus.circle")
                            }
                            Button {
                                addToPlaylistItem = PlaylistItem(type: "music", itemId: album.id.rawValue)
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to My Playlists", systemImage: "text.badge.plus")
                            }
                        }
                        #if os(tvOS)
                        .buttonStyle(TVPlainAlbumButtonStyle())
                        #endif
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color.clear.appBackground())
        .navigationTitle(artist.name)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddToPlaylist) {
            if let item = addToPlaylistItem {
                AddToPlaylistView(mediaType: item.type, mediaId: item.itemId)
            }
        }
    }
}

