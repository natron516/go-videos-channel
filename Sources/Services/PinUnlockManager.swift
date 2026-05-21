import Foundation
import FirebaseFirestore

/// Persists the sermon PIN unlock state across sessions.
/// Once unlocked, stays unlocked for 4 hours.
/// If the admin changes the PIN (pin_changed_at in Firestore), all devices re-lock immediately.
class PinUnlockManager {
    static let shared = PinUnlockManager()
    private init() {}

    private let key = "sermon_pin_unlocked_at"
    private let duration: TimeInterval = 60 * 60 * 4 // 4 hours

    /// Whether the PIN has been entered within the window AND
    /// the admin hasn't changed the PIN since the unlock.
    var isUnlocked: Bool {
        guard let unlockDate = UserDefaults.standard.object(forKey: key) as? Date else { return false }
        return Date().timeIntervalSince(unlockDate) < duration
    }

    /// Check Firestore for a pin_changed_at timestamp that invalidates the local unlock.
    /// Calls completion(true) if still unlocked, completion(false) if re-lock needed.
    func validateUnlock(completion: @escaping (Bool) -> Void) {
        guard let unlockDate = UserDefaults.standard.object(forKey: key) as? Date,
              Date().timeIntervalSince(unlockDate) < duration else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        db.collection("config").document("app").getDocument { snap, error in
            guard error == nil,
                  let ts = snap?.data()?["pin_changed_at"] as? Timestamp else {
                // No timestamp or fetch failed — trust local unlock
                completion(true)
                return
            }
            let changedDate = ts.dateValue()
            if changedDate > unlockDate {
                // Admin changed PIN after this device unlocked — force re-lock
                self.lock()
                completion(false)
            } else {
                completion(true)
            }
        }
    }

    /// Call this when the user successfully enters the PIN.
    func unlock() {
        UserDefaults.standard.set(Date(), forKey: key)
    }

    /// Force-lock (e.g. for testing or future admin use).
    func lock() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
