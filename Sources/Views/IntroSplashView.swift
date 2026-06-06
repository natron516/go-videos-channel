import SwiftUI

struct IntroSplashView: View {
    private static var hasPlayedSplash = false

    @State private var showContent = IntroSplashView.hasPlayedSplash
    @State private var splashOpacity: Double = 1.0
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

    private func setupSplash() {
        guard !IntroSplashView.hasPlayedSplash else {
            showContent = true
            splashOpacity = 0
            return
        }

        IntroSplashView.hasPlayedSplash = true

        // Show logo for ~1.5 seconds, then dissolve into content
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.6)) {
                showContent = true
                splashOpacity = 0
            }
        }
    }
}
