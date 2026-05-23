#if os(iOS)
import UIKit
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = PushNotificationManager.shared

        // If the app was launched by tapping a notification (cold start),
        // store the payload so the notification delegate can handle it
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            print("[Push] App launched from notification: \(remoteNotification)")
            PushNotificationManager.shared.pendingNotificationPayload = remoteNotification
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Push] APNs token received: \(tokenStr.prefix(20))...")
        Messaging.messaging().apnsToken = deviceToken
        // Report success to server
        reportToServer(token: "APNS_OK:\(tokenStr.prefix(40))", device: UIDevice.current.name)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] APNs registration FAILED: \(error.localizedDescription)")
        // Report failure to server
        reportToServer(token: "APNS_FAIL:\(error.localizedDescription)", device: UIDevice.current.name)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }

    private func reportToServer(token: String, device: String) {
        guard let url = URL(string: "https://go-admin-production-6be4.up.railway.app/api/fcm-token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "device": device])
        URLSession.shared.dataTask(with: req).resume()
    }
}
#endif
