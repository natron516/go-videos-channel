import SwiftUI
import AVKit

struct IntroSplashView: View {
    private static var hasPlayedSplash = false

    @State private var showContent = IntroSplashView.hasPlayedSplash
    @State private var videoOpacity: Double = 0.0  // starts invisible, fades in
    @State private var player: AVPlayer?
    @ObservedObject private var watchTimer = WatchTimerManager.shared

    @EnvironmentObject var api: MuxAPI

    var body: some View {
        ZStack {
            // Main content underneath
            ContentView()
                .opacity(showContent ? 1.0 : 0.0)

            // Watch timer lock overlay
            if watchTimer.isLocked {
                WatchTimerLockView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Video splash on top
            if !showContent || videoOpacity > 0 {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let player = player {
                        IntroPlayerView(player: player)
                            .aspectRatio(1, contentMode: .fit)
                            .ignoresSafeArea()
                    }
                }
                .opacity(videoOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            setupPlayer()
            // Prefetch ALL thumbnails during splash so every category loads instantly
            Task {
                let all = (try? await api.fetchAllAssets()) ?? []
                prefetchThumbnails(all.map(\.thumbnailURL))
                prefetchThumbnails(all.map(\.fallbackThumbnailURL))
            }
            // Preload all tab content (books, articles, podcasts, audio, series, music)
            Task {
                await ContentPreloader.shared.preloadAll()
            }
        }
    }

    private func setupPlayer() {
        // Only play splash once per app launch
        guard !IntroSplashView.hasPlayedSplash else {
            showContent = true
            videoOpacity = 0
            return
        }

        guard let url = Bundle.main.url(forResource: "intro_splash", withExtension: "mp4") else {
            showContent = true
            videoOpacity = 0
            IntroSplashView.hasPlayedSplash = true
            return
        }

        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = true
        self.player = avPlayer

        let dismissSplash = {
            IntroSplashView.hasPlayedSplash = true
            // Dissolve splash out, content in simultaneously
            withAnimation(.easeInOut(duration: 0.8)) {
                showContent = true
                videoOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.player = nil
            }
        }

        // Fade video in on start
        let asset = AVAsset(url: url)
        Task {
            if let duration = try? await asset.load(.duration), duration.isNumeric {
                let halfTime = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
                await avPlayer.seek(to: .zero)
                avPlayer.play()
                // Fade in
                withAnimation(.easeIn(duration: 0.4)) {
                    videoOpacity = 1.0
                }
                // Dissolve out at halfway point
                DispatchQueue.main.asyncAfter(deadline: .now() + halfTime.seconds) {
                    dismissSplash()
                }
            } else {
                // Fallback: listen for video end
                avPlayer.play()
                withAnimation(.easeIn(duration: 0.4)) { videoOpacity = 1.0 }
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: avPlayer.currentItem,
                    queue: .main
                ) { _ in dismissSplash() }
            }
        }
    }
}

// Simple AVPlayer wrapper without controls
struct IntroPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView(player: player)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

class PlayerUIView: UIView {
    private var playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
