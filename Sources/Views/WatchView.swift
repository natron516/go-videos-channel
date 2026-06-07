import SwiftUI

#if !os(tvOS)

// MARK: - Category pill filter model
private struct WatchCategory: Identifiable, Equatable {
    let id: String
    let label: String
    let assetCategory: String?  // nil = "All"
    let requiresPin: Bool

    static let all: [WatchCategory] = [
        WatchCategory(id: "all",        label: "All",       assetCategory: nil,           requiresPin: false),
        WatchCategory(id: "sermon",     label: "Sermons",   assetCategory: "sermon",      requiresPin: true),
        WatchCategory(id: "children",   label: "Children's",assetCategory: "children",    requiresPin: false),
        WatchCategory(id: "music",      label: "Music",     assetCategory: "music",       requiresPin: false),
        WatchCategory(id: "performance",label: "Shows",     assetCategory: "performance", requiresPin: false),
        WatchCategory(id: "funzone",    label: "FunZone",   assetCategory: "funzone",     requiresPin: false),
        WatchCategory(id: "hidden",     label: "Private",   assetCategory: "hidden",      requiresPin: false),
    ]
}

struct WatchView: View {
    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var liveManager = LiveStreamManager.shared
    @ObservedObject private var autoplay = AutoplayManager.shared

    @State private var allAssets: [MuxAsset] = []
    @State private var isLoading = true
    @State private var selectedCategory: WatchCategory = WatchCategory.all[0]
    @State private var showPinLock = false
    @State private var pinUnlocked = false
    @State private var pendingLivePlay = false
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false

    private var visibleCategories: [WatchCategory] {
        WatchCategory.all.filter { cat in
            if cat.id == "hidden" { return auth.hasPrivateAccess }
            return true
        }
    }

    private var filteredAssets: [MuxAsset] {
        if let catKey = selectedCategory.assetCategory {
            return allAssets.filter { $0.category == catKey }
        }
        // "All" — exclude hidden AND sermons (sermons are behind PIN lock)
        return allAssets.filter { asset in
            asset.category != nil && asset.category != "hidden" && asset.category != "sermon"
        }
    }

    var columns: [GridItem] {
        UIDevice.current.userInterfaceIdiom == .pad
            ? Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)
            : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            if showPinLock {
                PinLockView {
                    PinUnlockManager.shared.unlock()
                    pinUnlocked = true
                    showPinLock = false
                    // If PIN was triggered from live sermon banner, auto-play after unlock
                    if pendingLivePlay, let liveAsset = liveManager.liveAsset,
                       let url = liveAsset.streamURL {
                        pendingLivePlay = false
                        presentPlayer(url: url)
                    }
                }
                .background(Color.black)
                .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    // Live stream banner
                    if liveManager.isLive, let liveAsset = liveManager.liveAsset {
                        if selectedCategory.assetCategory == nil ||
                           selectedCategory.assetCategory == liveAsset.category {
                            LiveStreamBanner(asset: liveAsset) {
                                if liveAsset.category == "sermon" && !pinUnlocked {
                                    pendingLivePlay = true
                                    showPinLock = true
                                } else if let url = liveAsset.streamURL {
                                    presentPlayer(url: url)
                                }
                            }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                    }

                    // Category pill bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(visibleCategories) { cat in
                                WatchPillButton(
                                    label: cat.label,
                                    isSelected: selectedCategory == cat
                                ) {
                                    if cat.requiresPin && !pinUnlocked {
                                        selectedCategory = cat
                                        showPinLock = true
                                    } else {
                                        selectedCategory = cat
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    Divider().background(Color.white.opacity(0.1))

                    if isLoading {
                        Spacer()
                        ProgressView("Loading…")
                        Spacer()
                    } else if filteredAssets.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No videos in \(selectedCategory.label)")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredAssets) { asset in
                                    Button {
                                        playAsset(asset)
                                    } label: {
                                        SermonCardView(asset: asset)
                                    }
                                    .mediaCardStyle()
                                    .contextMenu {
                                        if let url = asset.shareURL ?? asset.streamURL {
                                            ShareLink(
                                                item: url,
                                                subject: Text(asset.title),
                                                message: Text("Watch \(asset.title) on GO Videos")
                                            ) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                        Button {
                                            addToPlaylistAssetId = asset.id
                                            showAddToPlaylist = true
                                        } label: {
                                            Label("Add to Playlist", systemImage: "plus.circle")
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
        .navigationTitle("Watch")
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .sheet(isPresented: $showAddToPlaylist) {
            if let id = addToPlaylistAssetId {
                AddToPlaylistView(assetId: id)
            }
        }
        .task {
            await loadAssets()
        }
        .onAppear {
            pinUnlocked = PinUnlockManager.shared.isUnlocked
        }
        .onChange(of: selectedCategory) { newCat in
            if newCat.requiresPin && !pinUnlocked {
                showPinLock = true
            } else if !newCat.requiresPin {
                showPinLock = false
            }
        }
    }

    private func loadAssets() async {
        isLoading = true
        defer { isLoading = false }
        allAssets = (try? await api.fetchAllAssets()) ?? []
    }

    private func playAsset(_ asset: MuxAsset) {
        guard let url = asset.streamURL else { return }
        autoplay.setContext(asset: asset, playlist: filteredAssets)
        presentPlayer(url: url)
    }
}

// MARK: - Category pill button
struct WatchPillButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.15))
                )
        }
    }
}

// MARK: - Live Stream Banner
struct LiveStreamBanner: View {
    let asset: MuxAsset
    var onWatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 4)
                )
            Text("LIVE")
                .font(.caption.bold())
                .foregroundColor(.red)
            Text(asset.title)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Button {
                onWatch()
            } label: {
                Text("Watch")
                    .font(.caption.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

#endif
