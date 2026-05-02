import SwiftUI

struct AddToPlaylistView: View {
    let assetId: String
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = PlaylistManager.shared
    @State private var showNewPlaylist = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if showNewPlaylist {
                    HStack {
                        TextField("New playlist name", text: $newName)
                        Button("Create") {
                            if !newName.isEmpty {
                                let p = manager.create(name: newName)
                                manager.addAsset(assetId, to: p.id)
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
                            let added = playlist.assetIds.contains(assetId)
                            Button {
                                if added {
                                    manager.removeAsset(assetId, from: playlist.id)
                                } else {
                                    manager.addAsset(assetId, to: playlist.id)
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
                                    Text("\(playlist.assetIds.count)")
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
