import Foundation

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var assetIds: [String]  // Mux asset IDs
    var createdAt: Date

    init(name: String, assetIds: [String] = []) {
        self.id = UUID()
        self.name = name
        self.assetIds = assetIds
        self.createdAt = Date()
    }
}

class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var playlists: [Playlist] = []

    private let storageKey = "user_playlists"
    private let icloud = NSUbiquitousKeyValueStore.default

    private init() {
        load()
        // Listen for iCloud changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: icloud
        )
        icloud.synchronize()
    }

    @objc private func icloudDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.load()
        }
    }

    // MARK: - CRUD

    func create(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        save()
        return playlist
    }

    func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = name
        save()
    }

    func addAsset(_ assetId: String, to playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !playlists[idx].assetIds.contains(assetId) {
            playlists[idx].assetIds.append(assetId)
            save()
        }
    }

    func removeAsset(_ assetId: String, from playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].assetIds.removeAll { $0 == assetId }
        save()
    }

    func moveAsset(in playlistId: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].assetIds.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence (iCloud + local fallback)

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        // Save to iCloud
        icloud.set(data, forKey: storageKey)
        icloud.synchronize()
        // Local backup
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        // Prefer iCloud, fall back to local
        let data = icloud.data(forKey: storageKey)
            ?? UserDefaults.standard.data(forKey: storageKey)
        guard let data = data,
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = decoded
    }
}
