import SwiftUI
import AVKit

// MARK: - Present AVPlayerViewController via UIKit root VC

func presentPlayer(url: URL, autoplay: Bool = false) {
    let player = AVPlayer(url: url)
    let vc = AVPlayerViewController()
    vc.player = player

    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }

    var top = root
    while let presented = top.presentedViewController { top = presented }

    if autoplay, top is AVPlayerViewController {
        top.dismiss(animated: false) {
            presentPlayerFresh(vc: vc, player: player, from: root)
        }
    } else {
        presentPlayerFresh(vc: vc, player: player, from: top)
    }
}

private func presentPlayerFresh(vc: AVPlayerViewController, player: AVPlayer, from presenter: UIViewController) {
    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: nil,
        queue: .main
    ) { [weak player] notification in
        guard let endedItem = notification.object as? AVPlayerItem,
              endedItem === player?.currentItem else { return }
        AutoplayManager.shared.handleVideoEnd()
    }

    presenter.present(vc, animated: true) {
        player.play()
        // Start preloading the next video in the playlist
        AutoplayManager.shared.preloadNext()
    }
}

/// Dismiss the topmost AVPlayerViewController
func dismissTopPlayer() {
    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    if top is AVPlayerViewController {
        top.dismiss(animated: true)
    }
}

/// Swap video in existing player, or present fresh if none is open
func playNextInExistingPlayer(url: URL, preloadedItem: AVPlayerItem? = nil) {
    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }

    // Use preloaded item for instant playback, or create new
    let item = preloadedItem ?? AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)

    if let playerVC = top as? AVPlayerViewController {
        playerVC.player = player
    } else {
        let vc = AVPlayerViewController()
        vc.player = player
        top.present(vc, animated: true)
    }

    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: nil,
        queue: .main
    ) { [weak player] notification in
        guard let endedItem = notification.object as? AVPlayerItem,
              endedItem === player?.currentItem else { return }
        AutoplayManager.shared.handleVideoEnd()
    }

    player.play()
}

// MARK: - Inline player (Live tab)

struct VideoPlayerView: View {
    let url: URL
    @StateObject private var holder = PlayerHolder()

    var body: some View {
        AVKitVideoPlayer(player: holder.player)
            .ignoresSafeArea()
            .onAppear {
                holder.load(url: url)
                holder.player.play()
            }
            .onDisappear {
                holder.player.pause()
            }
    }
}

struct AVKitVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

class PlayerHolder: ObservableObject {
    let player = AVPlayer()
    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
}
