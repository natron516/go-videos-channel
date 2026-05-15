import Foundation

/// Persists the sermon PIN unlock state across sessions.
/// Once unlocked, stays unlocked for 24 hours.
class PinUnlockManager {
    static let shared = PinUnlockManager()
    private init() {}

    private let key = "sermon_pin_unlocked_at"
    private let duration: TimeInterval = 60 * 60 * 24 // 24 hours

    /// Whether the PIN has been entered within the last 24 hours.
    var isUnlocked: Bool {
        guard let date = UserDefaults.standard.object(forKey: key) as? Date else { return false }
        return Date().timeIntervalSince(date) < duration
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
