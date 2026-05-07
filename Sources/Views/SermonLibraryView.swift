import SwiftUI

struct SermonLibraryView: View {
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
                        HStack(spacing: 24) {
                            Label("Sermon Library", systemImage: "film.stack")
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
                            Label("Sermons", systemImage: "film.stack")
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
            assets = all.filter { $0.category == "sermon" || $0.category == nil }
        } catch { print("Error: \(error)") }
        isLoading = false
    }
}

// MARK: - Sermon Card

struct SermonCardView: View {
    let asset: MuxAsset
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // Fixed 16:9 container — thumbnail always same size
            Color.clear
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    AsyncImage(url: asset.thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "play.circle").font(.largeTitle).foregroundColor(.white))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if asset.status == "preparing" {
                        Text("● LIVE")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }

            Text(asset.title)
                .font(.subheadline.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .frame(minHeight: 40, alignment: .top)

            if let speaker = asset.speaker {
                Text(speaker).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                if let date = asset.formattedDate {
                    Text(date).font(.caption).foregroundColor(.secondary)
                }
                if asset.formattedDate != nil, asset.duration != nil {
                    Text("·").font(.caption).foregroundColor(.secondary)
                }
                if let duration = asset.duration {
                    Text(formatDuration(duration)).font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
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
