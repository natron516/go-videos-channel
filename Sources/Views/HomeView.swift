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
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? Array(repeating: GridItem(.flexible(), spacing: 16), count: 4) : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
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
                    .padding(.horizontal, 40)
                    .padding(.top, -150)
                }
                #else
                if let uiImage = UIImage(named: "NavLogo") {
                    HStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 64)
                        Spacer()
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            Button { showSearch = true } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 30))
                            }
                            Menu {
                                Button { showLinkTV = true } label: {
                                    Label("Link Apple TV", systemImage: "appletv")
                                }
                                Button { showWatchTimer = true } label: {
                                    WatchTimerMenuLabel()
                                }
                                Divider()
                                Button(role: .destructive) {
                                    AuthService.shared.signOut()
                                } label: {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            } label: {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 30))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? -67 : -80)
                }
                #endif


                // LIVE NOW banner
                if let stream = liveStream, stream.isLive {
                    Button {
                        if let url = stream.streamURL { presentPlayer(url: url) }
                    } label: {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [.red, .red.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                .frame(maxWidth: .infinity, minHeight: 140)
                            HStack(spacing: 20) {
                                Circle().fill(Color.white).frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("LIVE NOW").font(.headline.bold()).foregroundColor(.white)
                                    Text(stream.title).font(.title2).foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                    .mediaCardStyle()
                    .padding(.horizontal, 40)
                }

                // Section header with autoplay toggle
                #if os(tvOS)
                HStack(spacing: 24) {
                    Label("Recent Videos", systemImage: "play.rectangle.fill")
                        .font(.title2.bold())
                        .labelStyle(.titleAndIcon)
                    AutoplayToggleButton(enabled: $autoplay.enabled)
                    ShuffleToggleButton(enabled: $autoplay.shuffle)
                    Spacer()
                    WatchTimerButton { showWatchTimer = true }
                }
                .padding(.horizontal, 40)
                .focusSection()
                #else
                HStack(spacing: 12) {
                    Label("Recent Videos", systemImage: "play.rectangle.fill")
                        .font(.title3.bold())
                        .labelStyle(.titleAndIcon)
                    AutoplayToggleButton(enabled: $autoplay.enabled)
                    ShuffleToggleButton(enabled: $autoplay.shuffle)
                    Spacer()
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        WatchTimerButton { showWatchTimer = true }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                    LazyVGrid(columns: columns, spacing: tvOSSpacing ? 40 : 16) {
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
                    .padding(tvOSSpacing ? 40 : 12)
                }
            }
            .padding(.vertical, 20)
        }
        #if !os(tvOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        // Only show toolbar items on iPhone (iPad has them inline with logo)
        .modifier(iPhoneToolbarModifier(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer))
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        #endif
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .appBackground()
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, assetId: addToPlaylistAssetId)
    }

    func load() async {
        isLoading = true
        async let assets = api.fetchAssets()
        async let live = api.activeLiveStream()
        recentAssets = ((try? await assets) ?? []).filter { $0.category != "sermon" }
        liveStream = try? await live
        isLoading = false
    }
}

#if !os(tvOS)
struct iPhoneToolbarModifier: ViewModifier {
    @Binding var showLinkTV: Bool
    @Binding var showWatchTimer: Bool

    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content
        } else {
            content
                .searchToolbar()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { showLinkTV = true } label: {
                                Label("Link Apple TV", systemImage: "appletv")
                            }
                            Button { showWatchTimer = true } label: {
                                WatchTimerMenuLabel()
                            }
                            Divider()
                            Button(role: .destructive) {
                                AuthService.shared.signOut()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 22))
                        }
                    }
                }
        }
    }
}
#endif
