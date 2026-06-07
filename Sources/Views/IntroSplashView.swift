import SwiftUI

struct IntroSplashView: View {
    private static var hasPlayedSplash = false

    @State private var showContent = IntroSplashView.hasPlayedSplash
    @State private var splashOpacity: Double = 1.0
    @State private var dataReady = false
    @State private var minTimeReached = false
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

            // Static logo splash on top
            if !IntroSplashView.hasPlayedSplash || splashOpacity > 0 {
                ZStack {
                    // Dark gradient background
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.08, blue: 0.10),
                            Color(red: 0.15, green: 0.15, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    // Cross logo centered
                    Image("CrossLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                }
                .opacity(splashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            setupSplash()
            // Prefetch ALL assets + thumbnails + tab content during splash
            Task {
                async let assetsTask: Void = {
                    let all = (try? await api.fetchAllAssets()) ?? []
                    prefetchThumbnails(all.map(\.thumbnailURL))
                    prefetchThumbnails(all.map(\.fallbackThumbnailURL))
                }()
                async let preloadTask: Void = ContentPreloader.shared.preloadAll()
                _ = await (assetsTask, preloadTask)
                dataReady = true
                revealIfReady()
            }
        }
    }

    private func revealIfReady() {
        guard dataReady && minTimeReached else { return }
        guard !showContent else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            showContent = true
            splashOpacity = 0
        }
    }

    private func setupSplash() {
        guard !IntroSplashView.hasPlayedSplash else {
            showContent = true
            splashOpacity = 0
            dataReady = true
            minTimeReached = true
            return
        }

        IntroSplashView.hasPlayedSplash = true

        // Minimum splash time of 1.5s, but wait for data before revealing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            minTimeReached = true
            revealIfReady()
        }
        // Safety timeout — reveal after 6s even if data is still loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            if !showContent {
                withAnimation(.easeInOut(duration: 0.6)) {
                    showContent = true
                    splashOpacity = 0
                }
            }
        }
    }
}
