import SwiftUI

struct SermonLibraryView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var assets: [MuxAsset] = []
    @State private var isLoading = true
    #if !os(tvOS)
    @State private var isUnlocked = PinUnlockManager.shared.isUnlocked
    #endif
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false
    #if !os(tvOS)
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false
    #endif

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? Array(repeating: GridItem(.flexible(), spacing: 20), count: 3) : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        #endif
    }

    var body: some View {
        ZStack {
          Group {
            if isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Color.clear.appBackground()
                    ProgressView("Loading Sermons…")
                }
            } else if assets.isEmpty {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Color.clear.appBackground()
                    VStack(spacing: 16) {
                        Image(systemName: "film.stack").font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No Sermons Yet").font(.title)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        #if os(tvOS)
                        Label("Sermon Library", systemImage: "film.stack")
                            .font(.title2.bold())
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                        #else
                        Label("Sermons", systemImage: "film.stack")
                            .font(.title3.bold())
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        #endif

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(assets) { asset in
                                Button {
                                    if let url = asset.streamURL {
                                        AutoplayManager.shared.setContext(asset: asset, playlist: assets)
                                        presentPlayer(url: url, asset: asset)
                                    }
                                } label: {
                                    SermonCardView(asset: asset)
                                }
                                .mediaCardStyle()
                                .contextMenu {
                                    Button {
                                        addToPlaylistAssetId = asset.id
                                        showAddToPlaylist = true
                                    } label: {
                                        Label("Add to Playlist", systemImage: "plus.circle")
                                    }
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
                                    if CastManager.shared.isConnected, let url = asset.streamURL {
                                        Button {
                                            CastManager.shared.cast(url: url, title: asset.title)
                                        } label: {
                                            Label("Cast to TV", systemImage: "tv")
                                        }
                                    }
                                    #endif
                                }
                            }
                        }
                        #if os(tvOS)
                        .padding(20)
                        #else
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        #endif
                    }
                }
            }
        }
        .navigationTitle("")
        .appBackground()
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, assetId: addToPlaylistAssetId)
        #if !os(tvOS)
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        #endif

          // iOS PIN overlay only — tvOS PIN is handled in TVContentView
          #if !os(tvOS)
          if !isUnlocked {
            PinLockView {
                PinUnlockManager.shared.unlock()
                isUnlocked = true
            }
              .ignoresSafeArea()
              .zIndex(1)
          }
          #endif
        } // end ZStack
    }

    func load() async {
        if assets.isEmpty { isLoading = true }
        do {
            async let allAssets = api.fetchAssets()
            async let liveStream = api.activeLiveStream()
            let all = try await allAssets
            assets = all.filter { $0.category == "sermon" || $0.category == nil }
            // Keep LiveStreamManager current so card borders reflect live state
            LiveStreamManager.shared.update(stream: try? await liveStream, allAssets: all)
            prefetchThumbnails(assets.map(\.thumbnailURL))
        } catch { print("Error: \(error)") }
        isLoading = false
    }
}

// MARK: - Sermon Card

struct SermonCardView: View {
    let asset: MuxAsset
    var featured: Bool = false
    @Environment(\.isFocused) var isFocused
    @ObservedObject private var liveManager = LiveStreamManager.shared

    private var isLive: Bool { liveManager.isAssetLive(asset) }

    var body: some View {
        VStack(alignment: featured ? .center : .leading, spacing: featured ? 8 : 4) {
            // Thumbnail
            Color.clear
                .aspectRatio({
                    guard featured else { return 16.0/9.0 }
                    #if os(tvOS)
                    return 16.0/9.0
                    #else
                    return UIDevice.current.userInterfaceIdiom == .pad ? 16.0/9.0 : 21.0/9.0
                    #endif
                }(), contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: featured ? asset.featuredThumbnailURL : asset.thumbnailURL) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "play.circle").font(.largeTitle).foregroundColor(.white))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if isLive {
                        Text("● LIVE")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .padding(4)
                    }
                }

            Text(asset.title)
                .font(featured ? .title3.bold() : .caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(featured ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: featured ? .center : .leading)
                .foregroundColor(.primary)

            HStack(spacing: 4) {
                if let date = asset.formattedDate {
                    Text(date).font(featured ? .caption : .caption2).foregroundColor(.secondary)
                }
                if let duration = asset.duration {
                    Text("· \(formatDuration(duration))").font(featured ? .caption : .caption2).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: featured ? .center : .leading)

            Spacer(minLength: 0)
        }
        #if os(tvOS)
        .padding(10)
        #else
        .padding(6)
        #endif
        #if os(tvOS)
        .scaleEffect(featured ? 0.9 : 1.0) // 10% smaller for featured — more breathing room
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(featured
                    ? LinearGradient(
                        colors: [Color(red: 0.13, green: 0.12, blue: 0.22), Color(red: 0.07, green: 0.06, blue: 0.14)],
                        startPoint: .top, endPoint: .bottom)
                    : LinearGradient(
                        colors: [Color(red: 0.12, green: 0.11, blue: 0.18), Color(red: 0.08, green: 0.07, blue: 0.13)],
                        startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            Group {
                if featured {
                    // Gold bevel frame — stays gold on focus, gets brighter/thicker
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    isFocused ? Color.white : Color.white.opacity(0.75),
                                    Color(red: 1.0,  green: 0.84, blue: 0.0),
                                    Color(red: 0.83, green: 0.68, blue: 0.21),
                                    isFocused ? Color(red: 0.6, green: 0.45, blue: 0.05) : Color(red: 0.35, green: 0.25, blue: 0.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isFocused ? 7 : 2.5
                        )
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(isFocused ? 0.5 : 0.35), Color.clear, Color.black.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .padding(4)
                } else {
                    // Non-featured: gold bevel on focus, wraps whole card
                    if isFocused {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.85),
                                        Color(red: 1.0,  green: 0.84, blue: 0.0),
                                        Color(red: 0.83, green: 0.68, blue: 0.21),
                                        Color(red: 0.35, green: 0.25, blue: 0.0),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 5
                            )
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.clear, Color.black.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .padding(4)
                    }
                }
            }
        )
        .shadow(
            color: Color(red: 0.83, green: 0.68, blue: 0.21).opacity(
                featured ? (isFocused ? 0.8 : 0.5) : (isFocused ? 0.5 : 0)
            ),
            radius: isFocused ? 16 : 10, x: 0, y: isFocused ? 8 : 5
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        #else
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(featured
                    ? LinearGradient(
                        colors: [Color(red: 0.13, green: 0.12, blue: 0.22), Color(red: 0.07, green: 0.06, blue: 0.14)],
                        startPoint: .top, endPoint: .bottom)
                    : LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            Group {
                if featured {
                    // Outer bevel — gold gradient with highlight top-left, shadow bottom-right
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.75),
                                    Color(red: 1.0,  green: 0.84, blue: 0.0),
                                    Color(red: 0.83, green: 0.68, blue: 0.21),
                                    Color(red: 0.35, green: 0.25, blue: 0.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                    // Inner bevel — subtle inset shadow effect
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .padding(4)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
        )
        .shadow(
            color: featured ? Color(red: 0.83, green: 0.68, blue: 0.21).opacity(0.5) : .clear,
            radius: 10, x: 0, y: 5
        )
        #endif
        // Live red border around the whole card
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red, lineWidth: isLive ? 3 : 0)
        )
    }

    func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60; let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
