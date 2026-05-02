import SwiftUI

struct SermonLibraryView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var assets: [MuxAsset] = []
    @State private var isLoading = true
    @State private var selectedAsset: MuxAsset?

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Sermons…")
            } else if assets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 80))
                        .foregroundColor(.secondary)
                    Text("No Sermons Yet")
                        .font(.title)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(assets) { asset in
                            SermonCardView(asset: asset)
                                .onPlayModeChange { } // tvOS focus handled automatically
                                .focusable()
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                        }
                    }
                    .padding(40)
                }
            }
        }
        .navigationTitle("Sermon Library")
        .task { await load() }
        .fullScreenCover(item: $selectedAsset) { asset in
            if let url = asset.streamURL {
                VideoPlayerView(url: url, autoPlay: true)
                    .ignoresSafeArea()
            }
        }
    }

    func load() async {
        isLoading = true
        do {
            assets = try await api.fetchAssets()
        } catch {
            print("Error loading assets: \(error)")
        }
        isLoading = false
    }
}

struct SermonCardView: View {
    let asset: MuxAsset
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: asset.thumbnailURL) { image in
                image.resizable().aspectRatio(16/9, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fill)
                    .overlay(Image(systemName: "play.circle").font(.largeTitle))
            }
            .cornerRadius(12)
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            Text(asset.title)
                .font(.callout.bold())
                .lineLimit(2)

            if let speaker = asset.speaker {
                Text(speaker)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let duration = asset.duration {
                Text(formatDuration(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .focused($isFocused)
    }

    func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
