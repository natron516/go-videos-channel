import SwiftUI
import AVKit
import MUXSDKStats
import FirebaseAuth


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
        playerData?.viewerUserId = Auth.auth().currentUser?.uid

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
    // Detect live asset: check manager first, fall back to preparing status
    let isLiveAsset: Bool
    if let asset = asset {
        isLiveAsset = LiveStreamManager.shared.isAssetLive(asset) || asset.status == "preparing"
    } else {
        isLiveAsset = false
    }
    // Use HLS proxy for live assets - strips EXT-X-PROGRAM-DATE-TIME so AVKit
    // shows elapsed time with seconds instead of wall-clock time
    let item = isLiveAsset ? LiveHLSProxy.makePlayerItem(url: url) : AVPlayerItem(url: url)
    if !isLiveAsset { item.automaticallyPreservesTimeOffsetFromLive = true }
    let player = AVPlayer(playerItem: item)
    // AirPlay: use native full-screen external playback instead of mirroring
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    let vc = AVPlayerViewController()
    vc.player = player

    // Track URL → assetId mapping and resume from saved position
    let assetId = asset?.id ?? MuxAnalytics.playbackId(from: url)
    MuxAssetURLTracker.track(url: url, assetId: assetId)
    // Also track the proxy URL so the periodic observer can find the assetId
    if isLiveAsset, let proxyURL = URL(string: url.absoluteString.replacingOccurrences(of: "https://", with: "\(LiveHLSProxy.scheme)://")) {
        MuxAssetURLTracker.track(url: proxyURL, assetId: assetId)
    }
    if isLiveAsset {
        // Read saved position BEFORE clearing - saveAndClear() writes to PlaybackProgress on dismiss
        let resumePos: Double? = PlaybackProgress.shared.hasProgress(for: assetId)
            ? PlaybackProgress.shared.position(for: assetId) : nil
        PlaybackProgress.shared.clear(assetId: assetId)
        var liveObs: NSKeyValueObservation?
        liveObs = player.currentItem?.observe(\.status, options: [.new]) { [weak player] item, _ in
            guard item.status == .readyToPlay else { return }
            if let pos = resumePos {
                // Resume from where user left off
                let time = CMTime(seconds: pos, preferredTimescale: 600)
                player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
            } else {
                // First open - jump to live edge
                player?.seek(to: .positiveInfinity, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
            }
            liveObs?.invalidate(); liveObs = nil
        }
    } else if let deepSeek = DeepLinkSeekManager.shared.pendingSeek {
        // Shared link with timecode - seek to the requested position
        DeepLinkSeekManager.shared.pendingSeek = nil
        var obs: NSKeyValueObservation?
        obs = player.currentItem?.observe(\.status, options: [.new]) { [weak player] item, _ in
            if item.status == .readyToPlay {
                let time = CMTime(seconds: deepSeek, preferredTimescale: 600)
                player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
                obs?.invalidate(); obs = nil
            }
        }
    } else if PlaybackProgress.shared.hasProgress(for: assetId) {
        var obs: NSKeyValueObservation?
        obs = player.currentItem?.observe(\.status, options: [.new]) { [weak player] item, _ in
            if item.status == .readyToPlay {
                // Skip resume for short videos (< 5 min) - always start from beginning
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

    // Track what user is currently watching
    let watchTitle: String
    if isLiveAsset {
        watchTitle = "Live: \(asset?.title ?? "Livestream")"
    } else {
        watchTitle = asset?.title ?? "Unknown"
    }
    SessionTracker.shared.startWatching(title: watchTitle, assetId: asset?.id ?? "")

    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows.first?.rootViewController else { return }

    var top = root
    while let presented = top.presentedViewController { top = presented }

    sessionURL   = url
    sessionTitle = asset?.title

    if autoplay, top is AVPlayerViewController {
        top.dismiss(animated: false) {
            MuxAnalytics.destroy(playerName: "main")
            SessionTracker.shared.stopWatching()
            presentPlayerFresh(vc: vc, player: player, from: root, isLive: isLiveAsset, liveStreamId: asset?.live_stream_id, assetId: asset?.id)
        }
    } else {
        presentPlayerFresh(vc: vc, player: player, from: top, isLive: isLiveAsset, liveStreamId: asset?.live_stream_id, assetId: asset?.id)
    }
}

private var sessionURL: URL?
private var sessionTitle: String?

private func presentPlayerFresh(vc: AVPlayerViewController, player: AVPlayer, from presenter: UIViewController, isLive: Bool = false, liveStreamId: String? = nil, assetId: String? = nil) {
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
        let rawDur = item.duration.seconds
        let dur = (rawDur.isNaN || rawDur.isInfinite) ? nil : rawDur
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
    // Add overlays after presentation (deferred to avoid layout stall)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if WatchTimerManager.shared.isRunning {
            addTimerOverlay(to: vc)
        }
        #if !os(tvOS)
        addPlayerButtons(to: vc)
        #endif
    }

    // Store observer reference so dismissTopPlayer() can clean up
    ActivePlayerSession.shared.set(player: player, observer: progressObserver, url: sessionURL, title: sessionTitle)
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
        SessionTracker.shared.stopWatching()
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
    // AirPlay: use native full-screen external playback instead of mirroring
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true

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
    let player: AVPlayer = {
        let p = AVPlayer()
        // AirPlay: use native full-screen external playback instead of mirroring
        p.allowsExternalPlayback = true
        p.usesExternalPlaybackWhileExternalScreenIsActive = true
        return p
    }()
    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        item.automaticallyPreservesTimeOffsetFromLive = true
        player.replaceCurrentItem(with: item)
    }
}

// MARK: - Custom Player Buttons (Share + Cast)

#if !os(tvOS)

func addPlayerButtons(to vc: UIViewController) {
    guard vc is AVPlayerViewController else { return }
    let manager = PlayerButtonsManager(vc: vc)
    manager.addButtons()
    // Keep manager alive for the lifetime of vc's view
    objc_setAssociatedObject(vc.view, &PlayerButtonsManager.managerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

private final class PlayerButtonsManager: NSObject, UIGestureRecognizerDelegate {
    static var managerKey = "playerButtonsManager"

    private weak var vc: UIViewController?
    private weak var shareBtn: UIButton?

    private weak var shareFab: UIButton?
    private weak var shareFabBg: UIVisualEffectView?
    private var hideTimer: Timer?
    private var dismissTimer: Timer?
    private var buttonWindow: UIWindow?

    init(vc: UIViewController) {
        self.vc = vc
        super.init()
    }

    func addButtons() {
        guard let vc = vc, let scene = vc.view.window?.windowScene else { return }

        // Floating UIWindow - always above AVPlayerViewController's entire layer stack
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = .clear
        let rootVC = UIViewController()
        rootVC.view = PassthroughView()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        window.isHidden = false
        buttonWindow = window
        let container = rootVC.view!

        // Bookmark-style share button that sits near the timebar
        let btnHeight: CGFloat = 36
        let btnWidth: CGFloat = 44
        let fabBg = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        fabBg.clipsToBounds = true
        fabBg.layer.cornerRadius = 8
        fabBg.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fabBg)
        self.shareFabBg = fabBg

        let fab = UIButton(type: .system)
        fab.setImage(UIImage(systemName: "bookmark.circle.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        ), for: .normal)
        fab.tintColor = .white
        fab.translatesAutoresizingMaskIntoConstraints = false
        fab.addTarget(self, action: #selector(handleShare), for: .touchUpInside)
        fabBg.contentView.addSubview(fab)
        self.shareFab = fab
        self.shareBtn = fab

        // Position: right side, just above the transport bar / timebar area
        // iPhone timebar is ~52pt from bottom safe area; iPad ~44pt
        let bottomPad: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 8 : 52
        NSLayoutConstraint.activate([
            fabBg.widthAnchor.constraint(equalToConstant: btnWidth),
            fabBg.heightAnchor.constraint(equalToConstant: btnHeight),
            fabBg.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            fabBg.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomPad),
            fab.centerXAnchor.constraint(equalTo: fabBg.contentView.centerXAnchor),
            fab.centerYAnchor.constraint(equalTo: fabBg.contentView.centerYAnchor),
            fab.widthAnchor.constraint(equalToConstant: btnWidth),
            fab.heightAnchor.constraint(equalToConstant: btnHeight),
        ])

        // Show/hide in sync with player controls
        vc.view.gestureRecognizers?.forEach { $0.cancelsTouchesInView = false }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePlayerTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        vc.view.addGestureRecognizer(tap)

        // Tear down window when player is dismissed
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak vc] t in
            guard let self else { t.invalidate(); return }
            if vc?.view.window == nil { self.tearDown(); t.invalidate() }
        }

        scheduleHide()
    }

    private func findView(named fragment: String, in view: UIView) -> UIView? {
        if NSStringFromClass(type(of: view)).contains(fragment) { return view }
        for sub in view.subviews { if let f = findView(named: fragment, in: sub) { return f } }
        return nil
    }

    // MARK: Visibility

    private func showButtons() {
        shareFabBg?.alpha = 1
        shareFab?.alpha = 1
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) {
                self?.shareFabBg?.alpha = 0
                self?.shareFab?.alpha = 0
            }
        }
    }

    private func showAndKeep() {
        showButtons()
        scheduleHide()
    }

    private func tearDown() {
        hideTimer?.invalidate()
        dismissTimer?.invalidate()
        buttonWindow?.isHidden = true
        buttonWindow = nil
    }

    @objc private func handlePlayerTap() { showAndKeep() }

    // MARK: Share action

    @objc func handleShare() {
        showAndKeep()
        guard let vc = vc else { return }
        let session = ActivePlayerSession.shared
        guard let url = session.currentURL else { return }

        let seconds = Int(session.currentTime ?? 0)
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        let timeStr = h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
        let title = session.currentTitle ?? "this video"

        var comps = URLComponents()
        comps.scheme = "govideos"
        comps.host   = "play"
        comps.queryItems = [
            URLQueryItem(name: "url",   value: url.absoluteString),
            URLQueryItem(name: "t",     value: "\(seconds)"),
            URLQueryItem(name: "title", value: title),
        ]
        let shareURL = comps.url ?? url
        let message  = "Watch \"\(title)\" from \(timeStr) on GO Videos"

        let activityVC = UIActivityViewController(activityItems: [message, shareURL], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = shareBtn
        vc.present(activityVC, animated: true)
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }
}

// Touch-transparent window + view: only capture hits on UIControl subviews
// (buttons), pass everything else through to the player underneath.
private class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // Only capture taps on actual interactive controls
        if hit is UIControl { return hit }
        return nil
    }
}

private class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit is UIControl { return hit }
        return nil
    }
}

#endif

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

