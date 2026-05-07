import Foundation
import AVFoundation

// MARK: - PlaybackProgress
// Saves and restores video playback positions using UserDefaults.
// Keyed by Mux asset ID (from the stream URL or asset.id).
// Live streams are never tracked.

final class PlaybackProgress {

    static let shared = PlaybackProgress()
    private init() {}

    private let defaultsKey = "go_playback_progress"
    private let maxEntries  = 50
    private let minSaveTime: Double = 10      // don't save < 10s in
    private let endThreshold: Double = 30     // within 30s of end → clear (treat as done)

    // MARK: - Save

    func save(assetId: String, position: Double, duration: Double?) {
        guard !assetId.isEmpty, position >= minSaveTime else { return }

        if let dur = duration, dur > 0, (dur - position) < endThreshold {
            // Near the end — treat as finished, clear entry
            clear(assetId: assetId)
            return
        }

        var store = loadStore()
        store[assetId] = [
            "pos": position,
            "ts": Date().timeIntervalSince1970
        ]

        // Prune oldest entries over limit
        if store.count > maxEntries {
            let sorted = store.sorted { ($0.value["ts"] ?? 0) < ($1.value["ts"] ?? 0) }
            for (key, _) in sorted.prefix(store.count - maxEntries) {
                store.removeValue(forKey: key)
            }
        }

        saveStore(store)
    }

    // MARK: - Load

    func position(for assetId: String) -> Double {
        guard !assetId.isEmpty else { return 0 }
        return loadStore()[assetId]?["pos"] ?? 0
    }

    func hasProgress(for assetId: String) -> Bool {
        position(for: assetId) > minSaveTime
    }

    // MARK: - Clear

    func clear(assetId: String) {
        var store = loadStore()
        store.removeValue(forKey: assetId)
        saveStore(store)
    }

    // MARK: - Private

    private func loadStore() -> [String: [String: Double]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveStore(_ store: [String: [String: Double]]) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - AVPlayer extension for easy position tracking

extension AVPlayer {

    /// Seek to a saved position for the given asset, if one exists (> 10s).
    func resumeIfNeeded(assetId: String) {
        let pos = PlaybackProgress.shared.position(for: assetId)
        guard pos > 0 else { return }
        let time = CMTime(seconds: pos, preferredTimescale: 600)
        seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
