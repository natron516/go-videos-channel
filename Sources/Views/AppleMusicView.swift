import SwiftUI
import MusicKit

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

    var body: some View {
        ZStack {
            Color.clear.appBackground()

            if !music.isAuthorized {
                authPromptView
            } else if isLoading {
                ProgressView()
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
                await loadCurated()
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

            if music.authStatus == .denied {
                Text("Apple Music access was denied.\nGo to Settings → GO Media → Allow Apple Music")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
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
                        Text("Connect Apple Music")
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

    var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Now Playing bar
                if music.isPlaying, let title = music.nowPlayingTitle {
                    NowPlayingBar(title: title)
                        .padding(.horizontal, 16)
                }

                // Albums section
                if !albums.isEmpty {
                    sectionHeader("Albums")

                    #if os(tvOS)
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
                    #else
                    let columns = UIDevice.current.userInterfaceIdiom == .pad
                        ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
                        : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
                    #endif

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(albums) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                AlbumCardView(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }


            }
            .padding(.vertical, 16)
        }
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
        defer { isLoading = false }

        // Load albums
        for id in CuratedMusic.albumIDs {
            do {
                let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                if let album = response.items.first {
                    albums.append(album)
                }
            } catch {
                print("Failed to load album \(id): \(error)")
            }
        }

        // Sort alphabetically
        albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Album Card

struct AlbumCardView: View {
    let album: Album

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 200)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.4))
                    )
            }

            Text(album.title)
                .font(.subheadline.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .frame(minHeight: 40, alignment: .top)

            if !album.artistName.isEmpty {
                Text(album.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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


