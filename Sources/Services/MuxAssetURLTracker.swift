import Foundation
import AVKit
import AVFoundation

// MARK: - ActivePlayerSession
// Holds a reference to the current player + its periodic observer so
// we can save position and clean up regardless of how the player is dismissed.

final class ActivePlayerSession {
    static let shared = ActivePlayerSession()
    private init() {}

    private weak var player: AVPlayer?
    private var observer: Any?

    func set(player: AVPlayer, observer: Any) {
        self.player   = player
        self.observer = observer
    }

    /// Save current position and remove the periodic observer.
    func saveAndClear() {
        defer { player = nil; observer = nil }
        guard let player = player, let item = player.currentItem else { return }
        if let obs = observer { player.removeTimeObserver(obs) }
        guard let url  = (item.asset as? AVURLAsset)?.url,
              let assetId = MuxAssetURLTracker.assetId(for: url) else { return }
        let pos = player.currentTime().seconds
        let dur = item.duration.seconds.isNaN || item.duration.seconds.isInfinite
            ? nil : item.duration.seconds
        PlaybackProgress.shared.save(assetId: assetId, position: pos, duration: dur)
    }
}

// MARK: - MuxAssetURLTracker
// Maps stream URLs → Mux asset IDs so the periodic time observer
// can look up which asset is playing without needing a closure capture.

final class MuxAssetURLTracker {
    static let shared = MuxAssetURLTracker()
    private init() {}

    private var map: [URL: String] = [:]
    private let lock = NSLock()

    static func track(url: URL, assetId: String) {
        shared.lock.lock()
        shared.map[url] = assetId
        shared.lock.unlock()
    }

    static func assetId(for url: URL) -> String? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        if let id = shared.map[url] { return id }
        // Fallback: derive from Mux stream URL pattern
        // https://stream.mux.com/{playbackId}.m3u8
        if url.host == "stream.mux.com" {
            return url.lastPathComponent.replacingOccurrences(of: ".m3u8", with: "")
        }
        return nil
    }
}


