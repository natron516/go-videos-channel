import SwiftUI
import FirebaseCore
import AVFoundation
#if os(iOS)
import UIKit
#endif

@main
struct GospelOutreachTVApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()
        SessionTracker.shared.start()
        // Audio session is configured lazily when the user actually plays something
        // so we don't interrupt Apple Music / other audio on app launch.
    }

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    #if os(iOS)
                    PushNotificationManager.shared.requestPermission()
                    // Handle notification that launched the app from killed state
                    PushNotificationManager.shared.processPendingNotification()
                    clearBadge()
                    #endif
                }
                #if os(iOS)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        clearBadge()
                    }
                }
                #endif
                .environmentObject(MuxAPI.shared)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    DeepLinkHandler.shared.handle(url)
                }
        }
    }

    #if os(iOS)
    private func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
        // Tell the server to reset our badge counter
        let device = UIDevice.current.name
        guard let url = URL(string: "https://go-admin-production-6be4.up.railway.app/api/badge-reset") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["device": device])
        URLSession.shared.dataTask(with: req).resume()
    }
    #endif
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
