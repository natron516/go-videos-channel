import SwiftUI

/// YouTube-style "Add videos to playlist" sheet.
/// Shows all videos grouped by category with checkboxes to toggle membership.
struct AddVideosToPlaylistView: View {
    let playlistId: UUID

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var manager = PlaylistManager.shared

    @State private var allAssets: [MuxAsset] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedCategory = "all"

    private let categories: [(key: String, label: String, icon: String)] = [
        ("all",         "All",        "square.grid.2x2"),
        ("children",    "Children's", "figure.and.child.holdinghands"),
        ("music",       "Music",      "music.note"),
        ("performance", "Shows",      "theatermasks"),
        ("funzone",     "FunZone",    "party.popper"),
        ("sermon",      "Sermons",    "book.fill"),
    ]

    private var playlist: Playlist? {
        manager.playlists.first { $0.id == playlistId }
    }

    /// Items already in the playlist (video type)
    private var playlistVideoIds: Set<String> {
        guard let p = playlist else { return [] }
        return Set(p.items.filter { $0.isVideo }.map { $0.itemId })
    }

    /// Filtered assets based on selected category + search
    private var filteredAssets: [MuxAsset] {
        var list = allAssets

        // Filter by category
        if selectedCategory != "all" {
            list = list.filter { ($0.category ?? "").lowercased() == selectedCategory }
        }

        // Filter by search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.title.lowercased().contains(q) }
        }

        return list
    }

    /// Count of items that will be in playlist after current changes
    private var addedCount: Int {
        playlistVideoIds.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category pills — horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.key) { cat in
                            let isSelected = selectedCategory == cat.key
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = cat.key
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: cat.icon)
                                        .font(.caption)
                                    Text(cat.label)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.blue : Color.white.opacity(0.1))
                                .foregroundColor(isSelected ? .white : .secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider().background(Color.white.opacity(0.1))

                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Loading videos…")
                    Spacer()
                } else if filteredAssets.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No videos found")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredAssets) { asset in
                            let isAdded = playlistVideoIds.contains(asset.id)

                            Button {
                                toggleAsset(asset, isAdded: isAdded)
                            } label: {
                                HStack(spacing: 14) {
                                    // Checkbox
                                    Image(systemName: isAdded ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundColor(isAdded ? .blue : .gray)

                                    // Thumbnail
                                    if let thumbURL = asset.muxThumbnailURL {
                                        CachedAsyncImage(url: thumbURL) {
                                            Color.white.opacity(0.08)
                                        }
                                        .frame(width: 100, height: 56)
                                        .cornerRadius(6)
                                        .clipped()
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 100, height: 56)
                                            .overlay(
                                                Image(systemName: "play.rectangle")
                                                    .foregroundColor(.secondary)
                                            )
                                    }

                                    // Title + meta
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(asset.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        HStack(spacing: 8) {
                                            if let cat = asset.category {
                                                Text(categoryLabel(for: cat))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            if let dur = asset.duration {
                                                Text(formatDuration(dur))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Videos")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search videos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(addedCount) in playlist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .task { await loadAssets() }
        }
    }

    // MARK: - Actions

    private func toggleAsset(_ asset: MuxAsset, isAdded: Bool) {
        if isAdded {
            manager.removeAsset(asset.id, from: playlistId)
        } else {
            manager.addAsset(asset.id, to: playlistId)
        }
    }

    // MARK: - Data

    private func loadAssets() async {
        isLoading = true
        defer { isLoading = false }
        allAssets = (try? await api.fetchAssets()) ?? []
        // Sort alphabetically
        allAssets.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Helpers

    private func categoryLabel(for key: String) -> String {
        switch key.lowercased() {
        case "children":    return "Children's"
        case "music":       return "Music"
        case "performance": return "Shows"
        case "funzone":     return "FunZone"
        case "sermon":      return "Sermons"
        default:            return key.capitalized
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins >= 60 {
            let hrs = mins / 60
            let rem = mins % 60
            return String(format: "%d:%02d:%02d", hrs, rem, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
