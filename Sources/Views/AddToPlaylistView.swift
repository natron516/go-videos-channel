import SwiftUI

struct AddToPlaylistView: View {
    /// For video assets (existing callers)
    var assetId: String?
    /// For audio assets (new callers)
    var audioId: String?
    /// Generic: any media type + id
    var mediaType: String?
    var mediaId: String?

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = PlaylistManager.shared
    @State private var showNewPlaylist = false
    @State private var newName = ""

    private var playlistItem: PlaylistItem? {
        if let type = mediaType, let id = mediaId { return PlaylistItem(type: type, itemId: id) }
        if let id = assetId { return PlaylistItem(type: "video", itemId: id) }
        if let id = audioId { return PlaylistItem(type: "audio", itemId: id) }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                if showNewPlaylist {
                    HStack {
                        TextField("New playlist name", text: $newName)
                        Button("Create") {
                            if !newName.isEmpty, let item = playlistItem {
                                let p = manager.create(name: newName)
                                manager.addItem(item, to: p.id)
                                newName = ""
                                showNewPlaylist = false
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button {
                        showNewPlaylist = true
                    } label: {
                        Label("New Playlist", systemImage: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }

                Section("Your Playlists") {
                    if manager.playlists.isEmpty {
                        Text("No playlists yet — create one above")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(manager.playlists) { playlist in
                            let added: Bool = {
                                guard let item = playlistItem else { return false }
                                return playlist.items.contains { $0.type == item.type && $0.itemId == item.itemId }
                            }()

                            Button {
                                guard let item = playlistItem else { return }
                                if added {
                                    manager.removeItem(item, from: playlist.id)
                                } else {
                                    manager.addItem(item, to: playlist.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: added ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(added ? .blue : .gray)
                                        .font(.title3)
                                    Text(playlist.name)
                                        .foregroundColor(.primary)
                                        .font(.body)
                                    Spacer()
                                    Text("\(playlist.totalCount)")
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if !os(tvOS)
            .scrollContentBackground(.visible)
            #endif
        }
        #if os(tvOS)
        .background(Color.black)
        #else
        .background(Color(.systemBackground))
        #endif
    }
}
