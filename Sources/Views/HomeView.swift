import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var autoplay = AutoplayManager.shared
    @State private var recentAssets: [MuxAsset] = []
    @State private var liveStream: MuxLiveStream?
    @State private var isLoading = true
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false
    @State private var showLinkTV = false
    @State private var showAbout = false
    @State private var showWatchTimer = false
    @State private var showSearch = false



    private var tvOSSpacing: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 4) : Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
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


                // LIVE NOW banner
                if let stream = liveStream, stream.isLive {
                    Button {
                        if let url = stream.streamURL { presentPlayer(url: url) }
                    } label: {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(colors: [.red, .red.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                #if os(tvOS)
                                .frame(maxWidth: .infinity, minHeight: 140)
                                #else
                                .frame(maxWidth: .infinity, minHeight: UIDevice.current.userInterfaceIdiom == .pad ? 100 : 64)
                                #endif
                            HStack(spacing: 12) {
                                Circle().fill(Color.white)
                                    #if os(tvOS)
                                    .frame(width: 18, height: 18)
                                    #else
                                    .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 10,
                                           height: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 10)
                                    #endif
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("LIVE NOW")
                                        #if os(tvOS)
                                        .font(.headline.bold())
                                        #else
                                        .font(UIDevice.current.userInterfaceIdiom == .pad ? .headline.bold() : .caption.bold())
                                        #endif
                                        .foregroundColor(.white)
                                    Text(stream.title)
                                        #if os(tvOS)
                                        .font(.title2)
                                        #else
                                        .font(UIDevice.current.userInterfaceIdiom == .pad ? .subheadline : .footnote)
                                        #endif
                                        .foregroundColor(.white)
                                }
                            }
                            #if os(tvOS)
                            .padding(.horizontal, 20)
                            #else
                            .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 16)
                            #endif
                        }
                    }
                    .mediaCardStyle()
                    #if os(tvOS)
                    .padding(.horizontal, 20)
                    #else
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 16)
                    #endif
                }

                #if os(tvOS)
                Label("Recent Videos", systemImage: "play.rectangle.fill")
                    .font(.title2.bold())
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 20)
                #else
                Label("Recent Videos", systemImage: "play.rectangle.fill")
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
                    LazyVGrid(columns: columns, spacing: tvOSSpacing ? 24 : 16) {
                        ForEach(recentAssets) { asset in
                            Button {
                                if let url = asset.streamURL {
                                    AutoplayManager.shared.setContext(asset: asset, playlist: recentAssets)
                                    presentPlayer(url: url)
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
                            }
                        }
                    }
                    .padding(tvOSSpacing ? 20 : 8)
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
    }

    func load() async {
        if recentAssets.isEmpty { isLoading = true }
        async let assets = api.fetchAssets()
        async let live = api.activeLiveStream()
        recentAssets = ((try? await assets) ?? []).filter { $0.category != "sermon" }
        liveStream = try? await live
        prefetchThumbnails(recentAssets.map(\.thumbnailURL))
        isLoading = false
    }
}


