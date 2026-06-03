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
        "pl.u-V9xKJUEWMY9J", // Edifying Songs Playlist 1
        "pl.u-d2ye0TD9Jr8E", // Playlist of Good Music
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
    }
    @State private var segment: MusicSegment = .albums
    @State private var musicSearchText = ""
    @State private var activeLoadTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.clear.appBackground()

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

                // Segment: Albums / Songs
                HStack {
                    Picker("", selection: $segment) {
                        ForEach(MusicSegment.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

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
                } else {
                    songsSection
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
                    }
                }
                .padding(.horizontal, 16)
            } else {
                #if os(tvOS)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)
                #else
                let columns = UIDevice.current.userInterfaceIdiom == .pad
                    ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
                    : Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                #endif

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filtered) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumCardView(album: album)
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

        // 20-second timeout — if catalog requests hang, bail out gracefully
        let loadTask = Task {
            await withTaskGroup(of: Album?.self) { group in
                for id in CuratedMusic.albumIDs {
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


