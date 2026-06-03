import Foundation
import AVFoundation
import Combine

class AutoplayManager: ObservableObject {
    static let shared = AutoplayManager()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "autoplay") }
    }

    @Published var shuffle: Bool {
        didSet { UserDefaults.standard.set(shuffle, forKey: "shuffle") }
    }

    var playlist: [MuxAsset] = []
    var currentIndex: Int = 0

    /// Pre-buffered player item for the next video
    private(set) var preloadedItem: AVPlayerItem?
    private(set) var preloadedURL: URL?

    /// Custom handler for series/podcast video autoplay — takes priority over playlist
    var customNextHandler: (() -> Void)?

    private init() {
        self.enabled = UserDefaults.standard.bool(forKey: "autoplay")
        self.shuffle = UserDefaults.standard.bool(forKey: "shuffle")
    }

    func setContext(asset: MuxAsset, playlist: [MuxAsset]) {
        self.playlist = playlist
        self.currentIndex = playlist.firstIndex(where: { $0.id == asset.id }) ?? 0
        preloadNext()
    }

    /// Start buffering the next video in the background
    func preloadNext() {
        let next = currentIndex + 1
        guard next < playlist.count,
              let url = playlist[next].streamURL else {
            preloadedItem = nil
            preloadedURL = nil
            return
        }
        // Don't re-preload the same URL
        guard url != preloadedURL else { return }
        preloadedURL = url
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 30 // buffer 30s ahead
        preloadedItem = item
    }

    /// Called when the current video finishes playing.
    func handleVideoEnd() {
        if let handler = customNextHandler {
            customNextHandler = nil
            handler()
            return
        }
        if enabled {
            playNext()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismissTopPlayer()
            }
        }
    }

    func playNext() {
        let next: Int
        if shuffle {
            // Pick a random video that isn't the current one
            let candidates = Array(playlist.indices).filter { $0 != currentIndex }
            guard let pick = candidates.randomElement() else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismissTopPlayer() }
                return
            }
            next = pick
        } else {
            next = currentIndex + 1
        }
        guard next < playlist.count else {
            preloadedItem = nil
            preloadedURL = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismissTopPlayer()
            }
            return
        }
        currentIndex = next
        guard let url = playlist[next].streamURL else { return }

        // Use preloaded item if available for instant playback
        let item = preloadedItem
        preloadedItem = nil
        preloadedURL = nil

        let nextAsset = playlist[next]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            playNextInExistingPlayer(url: url, preloadedItem: item, asset: nextAsset)
            // Start preloading the one after that
            preloadNext()
        }
    }
}
