import SwiftUI
import AVKit
import MUXSDKStats

// MARK: - Mux Data ENV Key
private let kMuxDataEnvKey = "kmoo2e3phld20msigd6flcreb"

// MARK: - Mux Analytics Helper

struct MuxAnalytics {

    /// Extract Mux playback ID from stream URL (https://stream.mux.com/{id}.m3u8)
    static func playbackId(from url: URL) -> String {
        url.lastPathComponent.replacingOccurrences(of: ".m3u8", with: "")
    }

    static func makeCustomerData(playerName: String, url: URL, asset: MuxAsset? = nil, isLive: Bool = false) -> MUXSDKCustomerData {
        let playerData = MUXSDKCustomerPlayerData(propertyKey: kMuxDataEnvKey)
        playerData?.playerName = "GO Media - \(playerName)"

        let videoData = MUXSDKCustomerVideoData()
        if let asset = asset {
            videoData.videoTitle = asset.title
            videoData.videoId = asset.id
            if let dur = asset.duration {
                videoData.videoDuration = NSNumber(value: dur * 1000)
            }
            videoData.videoSeries = asset.category
        } else {
            videoData.videoId = playbackId(from: url)
        }
        videoData.videoIsLive = NSNumber(value: isLive)

        let customerData = MUXSDKCustomerData()
        customerData.customerPlayerData = playerData
        customerData.customerVideoData = videoData
        return customerData
    }

    /// Start monitoring an AVPlayerViewController
    static func monitor(vc: AVPlayerViewController, name: String, url: URL, asset: MuxAsset? = nil, isLive: Bool = false) {
        let data = makeCustomerData(playerName: name, url: url, asset: asset, isLive: isLive)
        MUXSDKStats.monitorAVPlayerViewController(vc, withPlayerName: name, customerData: data)
    }

    /// Notify Mux when a new video starts in an existing player (autoplay/next)
    static func videoChanged(playerName: String, url: URL, asset: MuxAsset? = nil) {
        let videoData = MUXSDKCustomerVideoData()
        if let asset = asset {
            videoData.videoTitle = asset.title
            videoData.videoId = asset.id
            if let dur = asset.duration {
                videoData.videoDuration = NSNumber(value: dur * 1000)
            }
            videoData.videoSeries = asset.category
        } else {
            videoData.videoId = playbackId(from: url)
        }
        videoData.videoIsLive = false

        let customerData = MUXSDKCustomerData()
        customerData.customerVideoData = videoData
        MUXSDKStats.videoChange(forPlayer: playerName, with: customerData)
    }

    /// Destroy a tracked player session (call when player is dismissed)
    static func destroy(playerName: String) {
        MUXSDKStats.destroyPlayer(playerName)
    }
}

// MARK: - Present AVPlayerViewController via UIKit root VC

func presentPlayer(url: URL, autoplay: Bool = false, asset: MuxAsset? = nil) {
    let item = AVPlayerItem(url: url)
    item.automaticallyPreservesTimeOffsetFromLive = true
    let player = AVPlayer(playerItem: item)
    let vc = AVPlayerViewController()
    vc.player = player

    // Track URL → assetId mapping and resume from saved position
    let assetId = asset?.id ?? MuxAnalytics.playbackId(from: url)
    MuxAssetURLTracker.track(url: url, assetId: assetId)
    if PlaybackProgress.shared.hasProgress(for: assetId) {
        var obs: NSKeyValueObservation?
        obs = player.currentItem?.observe(\.status, options: [.new]) { [weak player] item, _ in
            if item.status == .readyToPlay {
                // Skip resume for short videos (< 5 min) — always start from beginning
                let duration = item.duration.seconds
                if !duration.isNaN && duration < 300 {
                    PlaybackProgress.shared.clear(assetId: assetId)
                } else {
                    player?.resumeIfNeeded(assetId: assetId)
                }
                obs?.invalidate(); obs = nil
            }
        }
    }

    MuxAnalytics.monitor(vc: vc, name: "main", url: url, asset: asset)

    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }

    var top = root
    while let presented = top.presentedViewController { top = presented }

    if autoplay, top is AVPlayerViewController {
        top.dismiss(animated: false) {
            MuxAnalytics.destroy(playerName: "main")
            presentPlayerFresh(vc: vc, player: player, from: root)
        }
    } else {
        presentPlayerFresh(vc: vc, player: player, from: top)
    }
}

private func presentPlayerFresh(vc: AVPlayerViewController, player: AVPlayer, from presenter: UIViewController) {
    // Save position periodically while playing
    let progressObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 5, preferredTimescale: 600),
        queue: .main
    ) { [weak player] _ in
        guard let player = player,
              let item = player.currentItem,
              let avUrl = (item.asset as? AVURLAsset)?.url,
              let assetId = MuxAssetURLTracker.assetId(for: avUrl)
        else { return }
        let pos = player.currentTime().seconds
        let dur = item.duration.seconds.isNaN ? nil : item.duration.seconds
        PlaybackProgress.shared.save(assetId: assetId, position: pos, duration: dur)
    }

    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: nil,
        queue: .main
    ) { [weak player] notification in
        guard let endedItem = notification.object as? AVPlayerItem,
              endedItem === player?.currentItem else { return }
        // Clear progress when video finishes naturally
        if let url = (endedItem.asset as? AVURLAsset)?.url,
           let assetId = MuxAssetURLTracker.assetId(for: url) {
            PlaybackProgress.shared.clear(assetId: assetId)
        }
        AutoplayManager.shared.handleVideoEnd()
    }

    presenter.present(vc, animated: true) {
        player.play()
        AutoplayManager.shared.preloadNext()
    }
    // Add watch timer overlay after presentation (deferred to avoid layout stall)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if WatchTimerManager.shared.isRunning {
            addTimerOverlay(to: vc)
        }
    }

    // Store observer reference so dismissTopPlayer() can clean up
    ActivePlayerSession.shared.set(player: player, observer: progressObserver)
}

/// Dismiss the topmost AVPlayerViewController
func dismissTopPlayer() {
    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    if top is AVPlayerViewController {
        // Save position before dismissing
        ActivePlayerSession.shared.saveAndClear()
        MuxAnalytics.destroy(playerName: "main")
        top.dismiss(animated: true)
    }
}

/// Swap video in existing player, or present fresh if none is open
func playNextInExistingPlayer(url: URL, preloadedItem: AVPlayerItem? = nil, asset: MuxAsset? = nil) {
    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }

    let item = preloadedItem ?? AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)

    // Resume from saved position
    let assetId = asset?.id ?? MuxAnalytics.playbackId(from: url)
    MuxAssetURLTracker.track(url: url, assetId: assetId)
    if PlaybackProgress.shared.hasProgress(for: assetId) {
        item.observe(\.status, options: [.new]) { item, _ in
            if item.status == .readyToPlay { player.resumeIfNeeded(assetId: assetId) }
        }
    }

    if let playerVC = top as? AVPlayerViewController {
        MuxAnalytics.videoChanged(playerName: "main", url: url, asset: asset)
        playerVC.player = player
    } else {
        let vc = AVPlayerViewController()
        vc.player = player
        MuxAnalytics.monitor(vc: vc, name: "main", url: url, asset: asset)
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
    var isLive: Bool = false
    @StateObject private var holder = PlayerHolder()

    var body: some View {
        AVKitVideoPlayer(player: holder.player, isLive: isLive, url: url)
            .ignoresSafeArea()
            .onAppear {
                holder.load(url: url)
                holder.player.play()
            }
            .onDisappear {
                holder.player.pause()
                MuxAnalytics.destroy(playerName: "live")
            }
    }
}

struct AVKitVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var isLive: Bool = false
    var url: URL? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        if let url = url {
            MuxAnalytics.monitor(vc: vc, name: "live", url: url, isLive: isLive)
        }
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

class PlayerHolder: ObservableObject {
    let player = AVPlayer()
    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        item.automaticallyPreservesTimeOffsetFromLive = true
        player.replaceCurrentItem(with: item)
    }
}

// MARK: - Watch Timer Overlay

private var timerOverlayTag = 9999

func addTimerOverlay(to vc: UIViewController) {
    let hostingController = WatchTimerOverlayController()
    hostingController.view.tag = timerOverlayTag
    hostingController.view.backgroundColor = .clear
    hostingController.view.isUserInteractionEnabled = false
    hostingController.view.layer.zPosition = 9999 // Stay above all controls
    
    vc.view.addSubview(hostingController.view)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    #if os(tvOS)
    let overlayLeading: CGFloat = 40
    let overlayBottom: CGFloat = -40
    let overlayWidth: CGFloat = 200
    let overlayHeight: CGFloat = 60
    #else
    let overlayLeading: CGFloat = 20
    let overlayBottom: CGFloat = -20
    let overlayWidth: CGFloat = 100
    let overlayHeight: CGFloat = 40
    #endif
    NSLayoutConstraint.activate([
        hostingController.view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: overlayLeading),
        hostingController.view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: overlayBottom),
        hostingController.view.widthAnchor.constraint(equalToConstant: overlayWidth),
        hostingController.view.heightAnchor.constraint(equalToConstant: overlayHeight)
    ])
    
    // Keep the hosting controller alive
    vc.addChild(hostingController)
    hostingController.didMove(toParent: vc)
}

class WatchTimerOverlayController: UIHostingController<WatchTimerOverlayView> {
    init() {
        super.init(rootView: WatchTimerOverlayView())
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct WatchTimerOverlayView: View {
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    
    private var fontSize: CGFloat {
        #if os(tvOS)
        return 32
        #else
        return 18
        #endif
    }
    
    var body: some View {
        if watchTimer.isRunning {
            Text(watchTimer.formattedTimeRemaining)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                )
        }
    }
}
