import SwiftUI

struct CategoryLibraryView: View {
    let title: String
    let category: String
    let icon: String
    var includePrivate: Bool = false

    @EnvironmentObject var api: MuxAPI
    @State private var assets: [MuxAsset] = []
    @State private var isLoading = true
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false
    #if !os(tvOS)
    @ObservedObject private var videoDownloader = VideoDownloadManager.shared
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
        Group {
            if isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Color.clear.appBackground()
                    ProgressView("Loading \(title)…")
                }
            } else if assets.isEmpty {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Color.clear.appBackground()
                    VStack(spacing: 16) {
                        Image(systemName: icon).font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No \(title) Yet").font(.title)
                        Text("Tag videos with: \(category)").font(.caption).foregroundColor(.secondary)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        #if os(tvOS)
                        Label(title, systemImage: icon)
                            .font(.title2.bold())
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                        #else
                        Label(title, systemImage: icon)
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
                                    if asset.streamURL != nil {
                                        if videoDownloader.isDownloaded(asset.id) {
                                            Label("Downloaded ✓", systemImage: "checkmark.circle.fill")
                                        } else if videoDownloader.isDownloading(asset.id) {
                                            Label("Downloading...", systemImage: "arrow.down.circle")
                                        } else {
                                            Button {
                                                VideoDownloadManager.shared.startDownload(asset: asset)
                                            } label: {
                                                Label("Download Video", systemImage: "arrow.down.circle")
                                            }
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
    }

    func load() async {
        if assets.isEmpty { isLoading = true }
        do {
            async let allAssets = includePrivate ? api.fetchAllAssets() : api.fetchAssets()
            async let liveStream = api.activeLiveStream()
            let all = try await allAssets
            assets = all.filter { $0.category == category || (includePrivate && $0.category == nil) }
            // Keep LiveStreamManager current so card borders reflect live state
            LiveStreamManager.shared.update(stream: try? await liveStream, allAssets: all)
            prefetchThumbnails(assets.map(\.thumbnailURL))
        } catch { print("Error: \(error)") }
        isLoading = false
    }
}
