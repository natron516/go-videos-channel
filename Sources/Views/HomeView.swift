import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var autoplay = AutoplayManager.shared
    @State private var recentAssets: [MuxAsset] = []
    @State private var liveStream: MuxLiveStream?
    @State private var isLoading = true
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false


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
            VStack(alignment: .leading, spacing: 48) {

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
                                    Text("Gospel Outreach of Olympia").font(.title2).foregroundColor(.white)
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
                }
                .padding(.horizontal, 40)
                .focusSection()
                #else
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recent Videos", systemImage: "play.rectangle.fill")
                        .font(.title3.bold())
                        .labelStyle(.titleAndIcon)
                    HStack(spacing: 12) {
                        AutoplayToggleButton(enabled: $autoplay.enabled)
                        ShuffleToggleButton(enabled: $autoplay.shuffle)
                    }
                }
                .padding(.horizontal, 20)
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
        .navigationTitle("Gospel Outreach")
        .navigationBarTitleDisplayMode(.inline)
        .searchToolbar()
        #endif
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
