import Foundation
import FirebaseAuth
import FirebaseFirestore

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var assetIds: [String]
    var createdAt: Date

    init(name: String, assetIds: [String] = []) {
        self.id = UUID()
        self.name = name
        self.assetIds = assetIds
        self.createdAt = Date()
    }
}

@MainActor
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var playlists: [Playlist] = []

    private var uid: String? { Auth.auth().currentUser?.uid }
    private var db = Firestore.firestore()

    private init() {
        // Reload playlists whenever auth state changes
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

    func addAsset(_ assetId: String, to playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !playlists[idx].assetIds.contains(assetId) {
            playlists[idx].assetIds.append(assetId)
            Task { await save(playlists[idx]) }
        }
    }

    func removeAsset(_ assetId: String, from playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].assetIds.removeAll { $0 == assetId }
        Task { await save(playlists[idx]) }
    }

    func moveAsset(in playlistId: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].assetIds.move(fromOffsets: source, toOffset: destination)
        Task { await save(playlists[idx]) }
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
                      let assetIds = d["assetIds"] as? [String],
                      let ts = d["createdAt"] as? Timestamp else { continue }
                loaded.append(Playlist(id: id, name: name, assetIds: assetIds, createdAt: ts.dateValue()))
            }
            playlists = loaded.sorted { $0.createdAt < $1.createdAt }
        } catch {
            print("PlaylistManager load error: \(error)")
        }
    }

    private func save(_ playlist: Playlist) async {
        guard let col = collection else { return }
        let data: [String: Any] = [
            "id": playlist.id.uuidString,
            "name": playlist.name,
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

// Extra init for decoding from Firestore fields
extension Playlist {
    init(id: UUID, name: String, assetIds: [String], createdAt: Date) {
        self.id = id
        self.name = name
        self.assetIds = assetIds
        self.createdAt = createdAt
    }
}
