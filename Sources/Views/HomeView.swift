import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var autoplay = AutoplayManager.shared
    @ObservedObject private var featured = FeaturedManager.shared
    @ObservedObject private var liveManager = LiveStreamManager.shared
    @State private var recentAssets: [MuxAsset] = []
    @State private var allAssets: [MuxAsset] = []
    @State private var liveStream: MuxLiveStream?
    @State private var isLoading = true
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false
    @State private var showLinkTV = false
    @State private var showAbout = false
    @State private var showWatchTimer = false
    @State private var showSearch = false
    @State private var showLivePinLock = false

    /// Assets to display — featured order when a curation list is set, otherwise recent.
    private var displayAssets: [MuxAsset] {
        let ids = featured.featuredIds
        guard !ids.isEmpty else { return recentAssets }
        let lookup = Dictionary(uniqueKeysWithValues: recentAssets.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    private var sectionTitle: String {
        featured.featuredIds.isEmpty ? "Recent Videos" : "Featured"
    }

    private var sectionIcon: String {
        featured.featuredIds.isEmpty ? "play.rectangle.fill" : "star.fill"
    }



    private var tvOSSpacing: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    // Home screen uses larger cards than the library views:
    // iPhone → 1 column (full-width), iPad → 3, tvOS → 3
    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 48), count: 3)
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
            ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
            : [GridItem(.flexible(), spacing: 0)]
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Logo header
                #if os(tvOS)
                if let uiImage = UIImage(named: "NavLogo") {
                    HStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(height: 120)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, -150)
                }
                #else
                // Logo lives in the nav bar on iOS — nothing here
                #endif


                #if os(tvOS)
                Label(sectionTitle, systemImage: sectionIcon)
                    .font(.title2.bold())
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 20)
                #else
                Label(sectionTitle, systemImage: sectionIcon)
                    .font(.title3.bold())
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                #endif

                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading videos…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: tvOSSpacing ? 48 : 12) {
                        // Note: iPhone gets extra horizontal padding below to shrink cards ~25%
                        ForEach(displayAssets) { asset in
                            Button {
                                if let url = asset.streamURL {
                                    AutoplayManager.shared.setContext(asset: asset, playlist: displayAssets)
                                    presentPlayer(url: url)
                                }
                            } label: {
                                SermonCardView(asset: asset, featured: true)
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
                    .padding(tvOSSpacing ? 20 : 8)
                    #if !os(tvOS)
                    // Slightly inset on iPhone
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .phone ? 16 : 0)
                    #endif
                }
            }
            .padding(.vertical, 20)
        }
        #if !os(tvOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        #endif
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .appBackground()
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, assetId: addToPlaylistAssetId)
        #if os(tvOS)
        // fullScreenCover gives the PIN proper focus ownership on tvOS
        .fullScreenCover(isPresented: $showLivePinLock) {
            PinLockView {
                showLivePinLock = false
                playLiveAsset()
            }
        }
        #else
        .overlay {
            if showLivePinLock {
                PinLockView {
                    showLivePinLock = false
                    playLiveAsset()
                }
                .ignoresSafeArea()
            }
        }
        #endif
    }

    @ViewBuilder
    func liveNowBanner(stream: MuxLiveStream) -> some View {
        Button {
            if PinUnlockManager.shared.isUnlocked {
                playLiveAsset()
            } else {
                showLivePinLock = true
            }
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.red, .red.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(maxWidth: .infinity, minHeight: 56)
                HStack(spacing: 12) {
                    Circle().fill(Color.white)
                        .frame(width: 12, height: 12)
                    Text("LIVE NOW  —  \(stream.title)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
        }
        .mediaCardStyle()
    }

    func playLiveAsset() {
        // Use the preparing asset URL (same as clicking it in SermonLibraryView)
        if let asset = liveManager.liveAsset, let url = asset.streamURL {
            AutoplayManager.shared.setContext(asset: asset, playlist: [asset])
            presentPlayer(url: url, asset: asset)
        } else if let url = liveStream?.streamURL {
            // Fallback: use live stream URL directly
            presentPlayer(url: url)
        } else {
            AppNavigator.goToSermons()
        }
    }

    func load() async {
        if recentAssets.isEmpty { isLoading = true }
        async let assets = api.fetchAssets()
        async let live = api.activeLiveStream()
        async let _ = FeaturedManager.shared.fetch()
        let fetched = (try? await assets) ?? []
        allAssets = fetched
        recentAssets = fetched.filter { $0.category != "sermon" }
        liveStream = try? await live
        LiveStreamManager.shared.update(stream: liveStream, allAssets: fetched)
        prefetchThumbnails(displayAssets.map(\.thumbnailURL))
        isLoading = false
    }
}


