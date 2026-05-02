import SwiftUI
import AVKit

struct KidsLibraryView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var assets: [MuxAsset] = []
    @State private var isLoading = true
    @State private var selectedAsset: MuxAsset?
    @State private var showPlayer = false

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible()), count: 4)
        #else
        return [GridItem(.adaptive(minimum: 280))]
        #endif
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Kids Videos…")
            } else if assets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)
                    Text("No Kids Videos Yet")
                        .font(.title)
                    Text("Upload videos tagged with category: kids in Mux")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(assets) { asset in
                            Button {
                                selectedAsset = asset
                                showPlayer = true
                            } label: {
                                SermonCardView(asset: asset)
                            }
                            .mediaCardStyle()
                        }
                    }
                    .padding(40)
                }
            }
        }
        .navigationTitle("Children's Videos")
        .task { await load() }
        .fullScreenCover(isPresented: $showPlayer) {
            if let asset = selectedAsset, let url = asset.streamURL {
                VideoPlayerView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    func load() async {
        isLoading = true
        do {
            let all = try await api.fetchAssets()
            assets = all.filter { $0.category == "children" }
        } catch {
            print("Error: \(error)")
        }
        isLoading = false
    }
}
