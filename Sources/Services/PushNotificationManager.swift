import Foundation

#if os(iOS)
import UserNotifications
import FirebaseMessaging
import UIKit

/// Manages push notification registration and FCM topic subscription.
/// All users subscribe to the "new_video" topic. The admin portal sends
/// notifications to this topic when the "Notify Users" button is clicked.
class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = PushNotificationManager()

    @Published var isRegistered = false
    /// Stores notification payload when app is launched from killed state
    var pendingNotificationPayload: [AnyHashable: Any]?

    override init() {
        super.init()
        // Set delegates BEFORE requesting permission
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// Request notification permission and register for remote notifications.
    func requestPermission() {
        // Always register for remote notifications so we get an APNs token for FCM
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("[Push] Auth error: \(error.localizedDescription)")
                return
            }
            print("[Push] Permission granted: \(granted)")
            DispatchQueue.main.async {
                self.isRegistered = granted
            }
        }

        // Try subscribing in case we already have a token from a previous session
        subscribeToNewVideos()

        // Directly fetch FCM token (doesn't rely on AppDelegate)
        Task {
            do {
                let token = try await Messaging.messaging().token()
                print("[Push] Direct FCM token: \(token.prefix(20))...")
                reportToken(token)
                subscribeToNewVideos()
            } catch {
                print("[Push] Direct token fetch failed: \(error.localizedDescription)")
                reportToken("TOKEN_FETCH_FAIL: \(error.localizedDescription)")
            }
        }
    }

    /// Subscribe to the new_video topic for broadcast notifications.
    func subscribeToNewVideos() {
        Messaging.messaging().subscribe(toTopic: "new_video") { error in
            if let error = error {
                print("[Push] Topic subscribe error: \(error.localizedDescription)")
            } else {
                print("[Push] Subscribed to new_video topic")
            }
        }
    }

    /// Process any pending notification from cold launch
    func processPendingNotification() {
        guard let userInfo = pendingNotificationPayload else { return }
        pendingNotificationPayload = nil
        print("[Push] Processing pending notification: \(userInfo)")

        let playbackId = userInfo["playbackId"] as? String
        let assetId = userInfo["assetId"] as? String

        if let pid = playbackId, !pid.isEmpty {
            let streamURL = URL(string: "https://stream.mux.com/\(pid).m3u8")!
            let asset = MuxAsset.stub(playbackId: pid, title: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                presentPlayer(url: streamURL, asset: asset)
            }
        } else if let aid = assetId, !aid.isEmpty {
            Task { @MainActor in
                let allAssets = (try? await MuxAPI.shared.fetchAllAssets()) ?? []
                if let asset = allAssets.first(where: { $0.id == aid }),
                   let url = asset.streamURL {
                    presentPlayer(url: url, asset: asset)
                }
            }
        }
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("[Push] FCM token received: \(token.prefix(20))...")
        // Subscribe to topic once we have a token
        subscribeToNewVideos()
        // Report token to server for debugging
        reportToken(token)
    }

    private func reportToken(_ token: String) {
        guard let url = URL(string: "https://go-admin-production-6be4.up.railway.app/api/fcm-token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["token": token, "device": UIDevice.current.name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, error in
            if let error = error {
                print("[Push] Token report failed: \(error.localizedDescription)")
            } else {
                print("[Push] Token reported to server")
            }
        }.resume()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("[Push] Received notification in foreground: \(notification.request.content.title)")
        completionHandler([.banner, .sound])  // no .badge — prevents UIKit tab bar badge dots
    }

    /// Handle notification tap — deep link to the notified video
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("[Push] Notification tapped: \(userInfo)")

        // Extract playback ID or asset ID from the notification data
        let playbackId = userInfo["playbackId"] as? String
        let assetId = userInfo["assetId"] as? String
        let title = response.notification.request.content.title

        if let pid = playbackId, !pid.isEmpty {
            // We have a playback ID — go straight to the video
            let streamURL = URL(string: "https://stream.mux.com/\(pid).m3u8")!
            let asset = MuxAsset.stub(playbackId: pid, title: title)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentPlayer(url: streamURL, asset: asset)
            }
        } else if let aid = assetId, !aid.isEmpty {
            // We have an asset ID — look it up from the API then play
            Task { @MainActor in
                let allAssets = (try? await MuxAPI.shared.fetchAllAssets()) ?? []
                if let asset = allAssets.first(where: { $0.id == aid }),
                   let url = asset.streamURL {
                    presentPlayer(url: url, asset: asset)
                }
            }
        }

        completionHandler()
    }
}

#else
// tvOS stub
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    @Published var isRegistered = false
    func requestPermission() {}
    func subscribeToNewVideos() {}
}
#endif
