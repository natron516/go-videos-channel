import SwiftUI
import FirebaseCore
import AVFoundation

@main
struct GospelOutreachTVApp: App {
    @StateObject private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()
        SessionTracker.shared.start()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        CastManager.shared.setup()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(MuxAPI.shared)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    DeepLinkHandler.shared.handle(url)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    @StateObject private var forceUpdate = ForceUpdateService.shared

    var body: some View {
        if forceUpdate.updateRequired {
            ForceUpdateView()
        } else {
            ZStack {
                if auth.isLoading {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ProgressView().tint(.white).scaleEffect(1.5)
                    }
                } else if auth.isLoggedIn {
                    ZStack {
                        IntroSplashView()
                            .disabled(watchTimer.isLocked)
                            .allowsHitTesting(!watchTimer.isLocked)
                        if watchTimer.isLocked {
                            WatchTimerLockView()
                                .transition(.opacity)
                                .zIndex(10)
                        }
                    }
                } else {
                    #if os(tvOS)
                    TVLoginView()
                    #else
                    LoginView()
                    #endif
                }

                // Soft update banner overlay
                if forceUpdate.updateRecommended {
                    VStack {
                        UpdateRecommendedBanner()
                        Spacer()
                    }
                    .zIndex(20)
                }
            }
        }
    }
}
