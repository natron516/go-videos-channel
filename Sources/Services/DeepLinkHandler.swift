import Foundation
import AVFoundation

// MARK: - DeepLinkHandler
// Handles govideos:// URLs, e.g.:
//   govideos://play?url=https://stream.mux.com/abc.m3u8&t=134&title=Sermon%20%E2%80%93%20May%2010%2C%202026

final class DeepLinkHandler {
    static let shared = DeepLinkHandler()
    private init() {}

    func handle(_ url: URL) {
        guard url.scheme == "govideos", url.host == "play" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let streamURLStr = components?.queryItems?.first(where: { $0.name == "url" })?.value,
              let streamURL = URL(string: streamURLStr) else { return }

        let startSeconds = components?.queryItems?.first(where: { $0.name == "t" })?.value
            .flatMap(Double.init) ?? 0
        let title = components?.queryItems?.first(where: { $0.name == "title" })?.value

        // Small delay so the app UI is ready if launching cold
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Find or build the matching MuxAsset so the player gets a title
            let playbackId = streamURL.lastPathComponent.replacingOccurrences(of: ".m3u8", with: "")
            let asset = MuxAsset.stub(playbackId: playbackId, title: title)

            // Present the player — it will seek to startSeconds once ready
            DeepLinkSeekManager.shared.pendingSeek = startSeconds > 0 ? startSeconds : nil
            presentPlayer(url: streamURL, asset: asset)
        }
    }
}

// MARK: - DeepLinkSeekManager
// Stores a one-shot seek target consumed by the player after it becomes ready.

final class DeepLinkSeekManager {
    static let shared = DeepLinkSeekManager()
    private init() {}
    var pendingSeek: Double?
}
