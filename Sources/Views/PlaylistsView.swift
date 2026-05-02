import SwiftUI

struct PlaylistsView: View {
    @ObservedObject private var manager = PlaylistManager.shared
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        Group {
            if manager.playlists.isEmpty && !showNewPlaylist {
                VStack(spacing: 20) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Playlists Yet")
                        .font(.title)
                    Text("Create a playlist and add videos from any category")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Long Press on any Video Thumbnail to add to your Playlists")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                    Button("Create Playlist") { showNewPlaylist = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // New playlist input
                        if showNewPlaylist {
                            HStack(spacing: 16) {
                                TextField("Playlist name", text: $newPlaylistName)
                                    .font(.title3)
                                Button("Create") {
                                    if !newPlaylistName.isEmpty {
                                        _ = manager.create(name: newPlaylistName)
                                        newPlaylistName = ""
                                        showNewPlaylist = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Cancel") {
                                    newPlaylistName = ""
                                    showNewPlaylist = false
                                }
                            }
                            .padding(.horizontal, 40)
                        }

                        Text("Long Press on any Video Thumbnail to add to your Playlists")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 10)

                        // Playlist list
                        ForEach(manager.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlistId: playlist.id)
                            } label: {
                                PlaylistRowView(playlist: playlist)
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #endif
                        }
                        .padding(.horizontal, 40)
                    }
                    .padding(.vertical, 20)
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            showNewPlaylist = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .navigationTitle("Playlists")
    }
}

struct PlaylistRowView: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Text("\(playlist.assetIds.count) video\(playlist.assetIds.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
