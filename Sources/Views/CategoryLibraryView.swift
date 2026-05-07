import SwiftUI

struct CategoryLibraryView: View {
    let title: String
    let category: String
    let icon: String

    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var autoplay = AutoplayManager.shared
    @State private var assets: [MuxAsset] = []
    @State private var isLoading = true
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
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
                        HStack(spacing: 24) {
                            Label(title, systemImage: icon)
                                .font(.title2.bold())
                                .labelStyle(.titleAndIcon)
                            AutoplayToggleButton(enabled: $autoplay.enabled)
                            ShuffleToggleButton(enabled: $autoplay.shuffle)
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                        .focusSection()
                        #else
                        HStack(spacing: 12) {
                            Label(title, systemImage: icon)
                                .font(.title3.bold())
                                .labelStyle(.titleAndIcon)
                            AutoplayToggleButton(enabled: $autoplay.enabled)
                            ShuffleToggleButton(enabled: $autoplay.shuffle)
                            Spacer()
                        }
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
                        .padding(40)
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
    }

    func load() async {
        isLoading = true
        do {
            let all = try await api.fetchAssets()
            assets = all.filter { $0.category == category }
        } catch { print("Error: \(error)") }
        isLoading = false
    }
}
