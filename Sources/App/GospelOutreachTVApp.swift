import SwiftUI
import FirebaseCore
import AVFoundation

@main
struct GospelOutreachTVApp: App {
    @StateObject private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(MuxAPI.shared)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject private var watchTimer = WatchTimerManager.shared

    var body: some View {
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
    }
}
