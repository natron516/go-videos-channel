import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore

/// Logs app open/close sessions to Firestore so the admin dashboard
/// can show per-user app usage time.
///
/// Document: sessions/{auto-id}
///   uid, platform, startedAt, endedAt, durationSeconds
///
/// Call `SessionTracker.shared.start()` once at app launch.
class SessionTracker {
    static let shared = SessionTracker()
    private init() {}

    private var sessionDocRef: DocumentReference?
    private var sessionStart: Date?
    private let db = Firestore.firestore()

    func start() {
        // Observe app lifecycle
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate),
                                               name: UIApplication.willTerminateNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        beginSession()
    }

    @objc private func appWillResignActive() {
        endSession()
    }

    @objc private func appWillTerminate() {
        endSession()
    }

    private func beginSession() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        sessionStart = Date()

        let platform: String
        #if os(tvOS)
        platform = "tvOS"
        #else
        platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif

        let data: [String: Any] = [
            "uid": uid,
            "platform": platform,
            "startedAt": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]

        let ref = db.collection("sessions").document()
        ref.setData(data)
        sessionDocRef = ref
    }

    private func endSession() {
        guard let ref = sessionDocRef, let start = sessionStart else { return }
        let duration = Date().timeIntervalSince(start)
        // Only log sessions longer than 3 seconds (ignore accidental opens)
        guard duration > 3 else {
            ref.delete()
            sessionDocRef = nil
            sessionStart = nil
            return
        }
        ref.updateData([
            "endedAt": FieldValue.serverTimestamp(),
            "durationSeconds": Int(duration)
        ])
        sessionDocRef = nil
        sessionStart = nil
    }
}
