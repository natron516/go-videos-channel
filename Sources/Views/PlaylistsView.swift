import SwiftUI

struct PlaylistsView: View {
    @ObservedObject private var manager = PlaylistManager.shared
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        Group {
            if manager.playlists.isEmpty && !showNewPlaylist {
                VStack(spacing: 20) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Playlists Yet")
                        .font(.title)
                    Text("Create a playlist and add videos, audio, books, or articles")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Long Press on any media card to add to a Playlist")
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
                                    #if !os(tvOS)
                                    .textFieldStyle(.roundedBorder)
                                    #endif
                                Button("Create") {
                                    let trimmed = newPlaylistName.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty {
                                        _ = manager.create(name: trimmed)
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

                        Text("Long Press on any media card to add to a Playlist")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 10)

                        // Playlist list
                        ForEach(manager.playlists) { playlist in
                            #if os(tvOS)
                            NavigationLink {
                                PlaylistDetailView(playlistId: playlist.id)
                            } label: {
                                PlaylistRowView(playlist: playlist)
                            }
                            .buttonStyle(.card)
                            #else
                            NavigationLink(value: playlist.id) {
                                PlaylistRowView(playlist: playlist)
                            }
                            .buttonStyle(.plain)
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
        .navigationTitle("")
        #if !os(tvOS)
        .navigationDestination(for: UUID.self) { id in
            PlaylistDetailView(playlistId: id)
        }
        #endif
        .task {
            await manager.reload()
        }
    }
}

struct PlaylistRowView: View {
    let playlist: Playlist

    private var countLabel: String {
        let count = playlist.totalCount
        let videoCount = playlist.items.filter { $0.isVideo }.count
        let audioCount = playlist.items.filter { $0.isAudio }.count
        let bookCount = playlist.items.filter { $0.isBook }.count
        let articleCount = playlist.items.filter { $0.isArticle }.count

        if count == 0 { return "Empty" }
        var parts: [String] = []
        if videoCount > 0 { parts.append("\(videoCount) video\(videoCount == 1 ? "" : "s")") }
        if audioCount > 0 { parts.append("\(audioCount) audio") }
        if bookCount > 0 { parts.append("\(bookCount) book\(bookCount == 1 ? "" : "s")") }
        if articleCount > 0 { parts.append("\(articleCount) article\(articleCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "books.vertical.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Text(countLabel)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
