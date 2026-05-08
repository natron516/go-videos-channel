import SwiftUI

struct SermonLibraryView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var assets: [MuxAsset] = []
    @State private var isLoading = true
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
            let all = try await api.fetchAssets()
            assets = all.filter { $0.category == "sermon" || $0.category == nil }
            prefetchThumbnails(assets.map(\.thumbnailURL))
        } catch { print("Error: \(error)") }
        isLoading = false
    }
}

// MARK: - Sermon Card

struct SermonCardView: View {
    let asset: MuxAsset
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail
            Color.clear
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: asset.thumbnailURL) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "play.circle").font(.largeTitle).foregroundColor(.white))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if asset.status == "preparing" {
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
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)

            HStack(spacing: 4) {
                if let date = asset.formattedDate {
                    Text(date).font(.caption2).foregroundColor(.secondary)
                }
                if let duration = asset.duration {
                    Text("· \(formatDuration(duration))").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        #if os(tvOS)
        .padding(10)
        #else
        .padding(6)
        #endif
        #if os(tvOS)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white, lineWidth: isFocused ? 4 : 0)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        #else
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        #endif
    }

    func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60; let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
