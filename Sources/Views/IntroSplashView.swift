import SwiftUI
import AVKit

struct IntroSplashView: View {
    private static var hasPlayedSplash = false

    @State private var showContent = IntroSplashView.hasPlayedSplash
    @State private var videoOpacity: Double = IntroSplashView.hasPlayedSplash ? 0.0 : 1.0
    @State private var player: AVPlayer?
    @ObservedObject private var watchTimer = WatchTimerManager.shared

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
        avPlayer.isMuted = false
        self.player = avPlayer

        // Listen for video end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            // Dissolve out
            IntroSplashView.hasPlayedSplash = true
            withAnimation(.easeInOut(duration: 0.8)) {
                showContent = true
                videoOpacity = 0
            }
            // Clean up player after fade
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.player = nil
            }
        }

        avPlayer.play()
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
