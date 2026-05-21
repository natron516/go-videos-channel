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
    private var isWatching = false
    private var endTimer: Timer?
    private var resignedAt: Date?
    private let gracePeriod: TimeInterval = 120 // 2 minutes before ending session

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
        // If we have an active session and came back within the grace period, just resume
        if sessionDocRef != nil, let resigned = resignedAt,
           Date().timeIntervalSince(resigned) < gracePeriod {
            endTimer?.invalidate()
            endTimer = nil
            resignedAt = nil
            return
        }
        // Otherwise start a fresh session
        endTimer?.invalidate()
        endTimer = nil
        resignedAt = nil
        beginSession()
    }

    @objc private func appWillResignActive() {
        // Start grace period timer — don't end session immediately
        resignedAt = Date()
        endTimer?.invalidate()
        endTimer = Timer.scheduledTimer(withTimeInterval: gracePeriod, repeats: false) { [weak self] _ in
            self?.endSession()
        }
    }

    @objc private func appWillTerminate() {
        endTimer?.invalidate()
        endTimer = nil
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

        let deviceName: String
        #if os(tvOS)
        deviceName = "Apple TV"
        #else
        deviceName = UIDevice.current.name
        #endif

        let displayName = Auth.auth().currentUser?.displayName ?? ""

        let data: [String: Any] = [
            "uid": uid,
            "platform": platform,
            "startedAt": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "deviceName": deviceName,
            "displayName": displayName
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
        // Clear watching fields before ending
        if isWatching {
            stopWatching()
        }
        ref.updateData([
            "endedAt": FieldValue.serverTimestamp(),
            "durationSeconds": Int(duration)
        ])
        sessionDocRef = nil
        sessionStart = nil
    }

    // MARK: - Currently Watching

    /// Call when the user starts watching a video or livestream.
    func startWatching(title: String, assetId: String) {
        guard let ref = sessionDocRef else { return }
        isWatching = true
        ref.updateData([
            "watching": title,
            "watchingAssetId": assetId,
            "watchingSince": FieldValue.serverTimestamp()
        ])
    }

    /// Call when the user stops watching (player dismissed).
    func stopWatching() {
        guard let ref = sessionDocRef, isWatching else { return }
        isWatching = false
        ref.updateData([
            "watching": FieldValue.delete(),
            "watchingAssetId": FieldValue.delete(),
            "watchingSince": FieldValue.delete()
        ])
    }
}
