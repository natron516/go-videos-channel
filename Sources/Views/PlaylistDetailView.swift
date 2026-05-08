import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: UUID

    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var manager = PlaylistManager.shared
    @ObservedObject private var autoplay = AutoplayManager.shared
    @State private var allAssets: [MuxAsset] = []
    @State private var showDeleteConfirm = false

    var playlist: Playlist? {
        manager.playlists.first { $0.id == playlistId }
    }

    var playlistAssets: [MuxAsset] {
        guard let playlist = playlist else { return [] }
        return playlist.assetIds.compactMap { id in
            allAssets.first { $0.id == id }
        }
    }

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return [GridItem(.adaptive(minimum: 280))]
        #endif
    }

    var body: some View {
        Group {
            if playlist != nil {
                if playlistAssets.isEmpty && allAssets.isEmpty {
                    ProgressView("Loading…")
                } else if playlistAssets.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Empty Playlist")
                            .font(.title)
                        Text("Add videos from any category using the + button")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Play All button
                            HStack(spacing: 16) {
                                Button {
                                    playAll()
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Play All")
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                            }
                            .padding(.horizontal, 40)

                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(playlistAssets) { asset in
                                    Button {
                                        playFrom(asset: asset)
                                    } label: {
                                        SermonCardView(asset: asset)
                                    }
                                    .mediaCardStyle()
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            manager.removeAsset(asset.id, from: playlistId)
                                        } label: {
                                            Label("Remove from Playlist", systemImage: "minus.circle")
                                        }
                                    }
                                }
                            }
                            .padding(40)
                        }
                    }
                }
            } else {
                Text("Playlist not found")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Playlist?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                manager.delete(id: playlistId)
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { allAssets = (try? await api.fetchAssets()) ?? [] }
    }

    func playAll() {
        guard let first = playlistAssets.first, let url = first.streamURL else { return }
        autoplay.setContext(asset: first, playlist: playlistAssets)
        presentPlayer(url: url)
    }

    func playFrom(asset: MuxAsset) {
        guard let url = asset.streamURL else { return }
        autoplay.setContext(asset: asset, playlist: playlistAssets)
        presentPlayer(url: url)
    }
}
