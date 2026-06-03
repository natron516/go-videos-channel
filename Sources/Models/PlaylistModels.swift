import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - PlaylistItem (mixed video + audio support)
struct PlaylistItem: Identifiable, Codable, Equatable {
    var id: String { type + ":" + itemId }
    let type: String   // "video" or "audio"
    let itemId: String

    init(type: String, itemId: String) {
        self.type = type
        self.itemId = itemId
    }

    var isVideo: Bool { type == "video" }
    var isAudio: Bool { type == "audio" }
    var isBook: Bool { type == "book" }
    var isArticle: Bool { type == "article" }
}

// MARK: - Playlist
struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [PlaylistItem]   // new mixed-content list
    var createdAt: Date

    /// Backward-compat: expose just video asset IDs (old callers)
    var assetIds: [String] {
        items.filter { $0.isVideo }.map { $0.itemId }
    }

    /// Total count including audio
    var totalCount: Int { items.count }

    init(name: String, items: [PlaylistItem] = []) {
        self.id = UUID()
        self.name = name
        self.items = items
        self.createdAt = Date()
    }

    // Convenience: create from legacy assetIds array (all treated as "video")
    init(id: UUID, name: String, assetIds: [String], createdAt: Date) {
        self.id = id
        self.name = name
        self.items = assetIds.map { PlaylistItem(type: "video", itemId: $0) }
        self.createdAt = createdAt
    }

    // Full init for decoded playlists with items
    init(id: UUID, name: String, items: [PlaylistItem], createdAt: Date) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
    }
}

// MARK: - PlaylistManager
@MainActor
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var playlists: [Playlist] = []

    private var uid: String? { Auth.auth().currentUser?.uid }
    private var db = Firestore.firestore()

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if user != nil {
                    await self?.load()
                } else {
                    self?.playlists = []
                }
            }
        }
    }

    private var collection: CollectionReference? {
        guard let uid else { return nil }
        return db.collection("users").document(uid).collection("playlists")
    }

    func reload() async {
        await load()
    }

    // MARK: - CRUD

    func create(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        Task { await save(playlist) }
        return playlist
    }

    func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
        Task { await remove(id: id) }
    }

    func rename(id: UUID, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = name
        Task { await save(playlists[idx]) }
    }

    // MARK: Video asset methods (backward compat)

    func addAsset(_ assetId: String, to playlistId: UUID) {
        addItem(PlaylistItem(type: "video", itemId: assetId), to: playlistId)
    }

    func removeAsset(_ assetId: String, from playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].items.removeAll { $0.isVideo && $0.itemId == assetId }
        Task { await save(playlists[idx]) }
    }

    func moveAsset(in playlistId: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].items.move(fromOffsets: source, toOffset: destination)
        Task { await save(playlists[idx]) }
    }

    // MARK: Mixed-item methods

    func addItem(_ item: PlaylistItem, to playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        let alreadyContains = playlists[idx].items.contains { $0.type == item.type && $0.itemId == item.itemId }
        if !alreadyContains {
            playlists[idx].items.append(item)
            Task { await save(playlists[idx]) }
        }
    }

    func removeItem(_ item: PlaylistItem, from playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].items.removeAll { $0.type == item.type && $0.itemId == item.itemId }
        Task { await save(playlists[idx]) }
    }

    func containsAsset(_ assetId: String, in playlistId: UUID) -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else { return false }
        return playlist.items.contains { $0.isVideo && $0.itemId == assetId }
    }

    func containsAudio(_ audioId: String, in playlistId: UUID) -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else { return false }
        return playlist.items.contains { $0.isAudio && $0.itemId == audioId }
    }

    func containsItem(type: String, id: String, in playlistId: UUID) -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else { return false }
        return playlist.items.contains { $0.type == type && $0.itemId == id }
    }

    // MARK: - Firestore

    private func load() async {
        guard let col = collection else { return }
        do {
            let snap = try await col.getDocuments()
            var loaded: [Playlist] = []
            for doc in snap.documents {
                let d = doc.data()
                guard let idStr = d["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = d["name"] as? String,
                      let ts = d["createdAt"] as? Timestamp else { continue }

                let createdAt = ts.dateValue()

                // Try loading new "items" field first
                if let rawItems = d["items"] as? [[String: String]] {
                    let items = rawItems.compactMap { dict -> PlaylistItem? in
                        guard let type = dict["type"], let itemId = dict["itemId"] else { return nil }
                        return PlaylistItem(type: type, itemId: itemId)
                    }
                    loaded.append(Playlist(id: id, name: name, items: items, createdAt: createdAt))
                } else if let assetIds = d["assetIds"] as? [String] {
                    // Backward compat: old format had assetIds as [String]
                    loaded.append(Playlist(id: id, name: name, assetIds: assetIds, createdAt: createdAt))
                } else {
                    loaded.append(Playlist(id: id, name: name, items: [], createdAt: createdAt))
                }
            }
            playlists = loaded.sorted { $0.createdAt < $1.createdAt }
        } catch {
            print("PlaylistManager load error: \(error)")
        }
    }

    private func save(_ playlist: Playlist) async {
        guard let col = collection else { return }
        let itemsData: [[String: String]] = playlist.items.map { ["type": $0.type, "itemId": $0.itemId] }
        let data: [String: Any] = [
            "id": playlist.id.uuidString,
            "name": playlist.name,
            "items": itemsData,
            // Keep assetIds for legacy compatibility (apps that haven't updated yet)
            "assetIds": playlist.assetIds,
            "createdAt": Timestamp(date: playlist.createdAt)
        ]
        do {
            try await col.document(playlist.id.uuidString).setData(data)
        } catch {
            print("PlaylistManager save error: \(error)")
        }
    }

    private func remove(id: UUID) async {
        guard let col = collection else { return }
        do {
            try await col.document(id.uuidString).delete()
        } catch {
            print("PlaylistManager delete error: \(error)")
        }
    }
}
