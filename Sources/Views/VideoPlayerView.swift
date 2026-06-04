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
    // Stop any audio playback before starting video
    Task { @MainActor in AudioPlayerManager.shared.stop() }

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

private final class PlayerButtonsManager: NSObject {
    static var managerKey = "playerButtonsManager"

    private weak var vc: UIViewController?
    private weak var shareBtn: UIView?
    private weak var bookmarkView: ShareBookmarkView?
    private var bookmarkCenterX: NSLayoutConstraint?
    private var timeObserver: Any?
    private var hideTimer: Timer?
    private var dismissTimer: Timer?
    private var buttonWindow: UIWindow?

    private var visibilityPoller: Timer?
    // Dynamic insets computed from video duration (longer labels = wider insets)
    private var trackInsetLeft: CGFloat = 90
    private var trackInsetRight: CGFloat = 100

    init(vc: UIViewController) {
        self.vc = vc
        super.init()
    }

    func addButtons() {
        guard let vc = vc, let scene = vc.view.window?.windowScene else { return }

        // Floating UIWindow above AVPlayerViewController
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

        // --- Bookmark share indicator that follows the playhead ---
        let bookmark = ShareBookmarkView()
        bookmark.translatesAutoresizingMaskIntoConstraints = false
        bookmark.addTarget(self, action: #selector(handleShare), for: .touchUpInside)
        container.addSubview(bookmark)
        self.bookmarkView = bookmark
        self.shareBtn = bookmark

        let centerX = bookmark.centerXAnchor.constraint(equalTo: container.leadingAnchor, constant: trackInsetLeft)
        self.bookmarkCenterX = centerX

        // Bottom tip sits just above the top edge of the timebar capsule
        let aboveTimebar: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 62 : 82
        NSLayoutConstraint.activate([
            bookmark.widthAnchor.constraint(equalToConstant: 26),
            bookmark.heightAnchor.constraint(equalToConstant: 32),
            bookmark.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -aboveTimebar),
            centerX,
        ])

        // Start hidden — visibility poller will show it when controls appear
        bookmark.alpha = 0

        // Periodic observer to move bookmark with playhead
        if let playerVC = vc as? AVPlayerViewController, let player = playerVC.player {
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.updateBookmarkPosition(player: player)
            }
        }

        // Poll native control visibility every 0.2s — perfectly tracks show/hide
        visibilityPoller = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.syncVisibilityWithNativeControls()
        }

        // Tear down window when player is dismissed
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak vc] t in
            guard let self else { t.invalidate(); return }
            if vc?.view.window == nil { self.tearDown(); t.invalidate() }
        }
    }

    private var insetsComputed = false

    /// Compute track insets based on video duration.
    /// Longer videos show h:mm:ss labels which are wider than m:ss.
    private func computeInsets(duration: Double) {
        guard !insetsComputed else { return }
        insetsComputed = true

        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        if duration >= 3600 {
            // h:mm:ss labels (e.g. "2:07:49" / "-2:08:58") — widest
            trackInsetLeft  = isPad ? 110 : 105
            trackInsetRight = isPad ? 120 : 115
        } else if duration >= 600 {
            // mm:ss with double-digit minutes (e.g. "12:34" / "-45:12")
            trackInsetLeft  = isPad ? 90 : 85
            trackInsetRight = isPad ? 100 : 95
        } else {
            // m:ss short labels (e.g. "1:23" / "-4:56")
            trackInsetLeft  = isPad ? 80 : 76
            trackInsetRight = isPad ? 90 : 86
        }
    }

    private func updateBookmarkPosition(player: AVPlayer) {
        guard let item = player.currentItem,
              let container = bookmarkView?.superview else { return }
        let dur = item.duration.seconds
        guard dur.isFinite && dur > 0 else { return }

        computeInsets(duration: dur)

        let cur = player.currentTime().seconds
        let progress = min(max(cur / dur, 0), 1)

        let screenW = container.bounds.width
        let leftEdge = trackInsetLeft
        let rightEdge = screenW - trackInsetRight
        let trackWidth = rightEdge - leftEdge
        let x = leftEdge + trackWidth * progress

        bookmarkCenterX?.constant = x
    }

    // MARK: Visibility — directly observes native controls, never drifts

    /// Walk the view tree and find the effective alpha of the native transport controls.
    /// We look for UIButton instances (close, play/pause, skip) and check their
    /// effective visibility. This cannot get out of sync because we read the
    /// actual state every 0.2s.
    private func syncVisibilityWithNativeControls() {
        guard let vc = vc else { return }
        let nativeAlpha = effectiveControlAlpha(in: vc.view)
        let shouldShow = nativeAlpha > 0.5
        let current = (bookmarkView?.alpha ?? 0) > 0.5
        if shouldShow != current {
            UIView.animate(withDuration: 0.2) {
                self.bookmarkView?.alpha = shouldShow ? 1 : 0
            }
        }
    }

    /// Compute the true visible alpha of the native controls by finding
    /// a UIButton (close/play/skip) and walking its entire ancestor chain.
    /// When AVKit hides controls, a parent container's alpha goes to 0.
    private func effectiveControlAlpha(in rootView: UIView) -> CGFloat {
        guard let btn = findFirstButton(in: rootView) else { return 0 }
        // Walk from the button up through all ancestors to the rootView,
        // multiplying alpha at each level. If ANY ancestor has alpha~0,
        // the result will be ~0.
        var alpha: CGFloat = 1.0
        var current: UIView? = btn
        while let v = current, v !== rootView {
            alpha *= v.alpha
            current = v.superview
        }
        return alpha
    }

    private func findFirstButton(in view: UIView) -> UIButton? {
        // Breadth-first: find the topmost UIButton (likely the X close button)
        var queue: [UIView] = [view]
        while !queue.isEmpty {
            let v = queue.removeFirst()
            if let btn = v as? UIButton { return btn }
            queue.append(contentsOf: v.subviews)
        }
        return nil
    }

    private func showAndKeep() {
        // No-op — visibility is entirely driven by the poller now
    }

    private func tearDown() {
        hideTimer?.invalidate()
        visibilityPoller?.invalidate()
        dismissTimer?.invalidate()
        if let obs = timeObserver, let playerVC = vc as? AVPlayerViewController {
            playerVC.player?.removeTimeObserver(obs)
        }
        timeObserver = nil
        buttonWindow?.isHidden = true
        buttonWindow = nil
    }

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
}

// MARK: - Share Bookmark Button
/// A bookmark-shaped button with a small share arrow, drawn via Core Graphics.
private class ShareBookmarkView: UIControl {
    private let bookmarkColor = UIColor.white
    private let arrowColor = UIColor.black

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width, h = rect.height
        let inset: CGFloat = 2
        let bw = w - inset * 2  // bookmark width
        let bh = h - inset * 2  // bookmark height
        let bx = inset
        let by = inset
        let pointDepth: CGFloat = bh * 0.22

        // Bookmark shape: flat top with rounded corners, tapers to point at bottom
        let path = UIBezierPath()
        let cornerR: CGFloat = 3
        path.move(to: CGPoint(x: bx + cornerR, y: by))
        path.addLine(to: CGPoint(x: bx + bw - cornerR, y: by))
        path.addArc(withCenter: CGPoint(x: bx + bw - cornerR, y: by + cornerR), radius: cornerR, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: bx + bw, y: by + bh - pointDepth))
        path.addLine(to: CGPoint(x: bx + bw / 2, y: by + bh))  // point at bottom
        path.addLine(to: CGPoint(x: bx, y: by + bh - pointDepth))
        path.addLine(to: CGPoint(x: bx, y: by + cornerR))
        path.addArc(withCenter: CGPoint(x: bx + cornerR, y: by + cornerR), radius: cornerR, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.close()

        // White fill with drop shadow
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        bookmarkColor.withAlphaComponent(0.92).setFill()
        path.fill()
        ctx.setShadow(offset: .zero, blur: 0)

        // Share arrow in the body area (above the point)
        let bodyH = bh - pointDepth
        let arrowSize: CGFloat = min(bw, bodyH) * 0.38
        let arrowCX = bx + bw / 2
        let arrowCY = by + bodyH * 0.45

        let arrowPath = UIBezierPath()
        // Arrow stem
        arrowPath.move(to: CGPoint(x: arrowCX, y: arrowCY - arrowSize * 0.5))
        arrowPath.addLine(to: CGPoint(x: arrowCX, y: arrowCY + arrowSize * 0.5))
        // Arrow head
        arrowPath.move(to: CGPoint(x: arrowCX - arrowSize * 0.35, y: arrowCY - arrowSize * 0.15))
        arrowPath.addLine(to: CGPoint(x: arrowCX, y: arrowCY - arrowSize * 0.5))
        arrowPath.addLine(to: CGPoint(x: arrowCX + arrowSize * 0.35, y: arrowCY - arrowSize * 0.15))

        arrowPath.lineWidth = 2.0
        arrowPath.lineCapStyle = .round
        arrowPath.lineJoinStyle = .round
        arrowColor.setStroke()
        arrowPath.stroke()
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

