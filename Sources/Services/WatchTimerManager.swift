import SwiftUI
import Combine
import AVFoundation

@MainActor
class WatchTimerManager: ObservableObject {
    static let shared = WatchTimerManager()

    /// Whether the timer is actively counting down
    @Published var isRunning = false
    /// Whether the lock screen should show (time expired)
    @Published var isLocked = false
    /// Seconds remaining
    @Published var secondsRemaining: Int = 0
    /// Total seconds that were set
    @Published var totalSeconds: Int = 0

    /// PIN set by the parent for this timer session
    private(set) var currentPin: String = ""

    private var timer: AnyCancellable?

    /// Start a watch timer for the given number of minutes with a parent-set PIN
    func start(minutes: Int, pin: String) {
        stop()
        currentPin = pin
        totalSeconds = minutes * 60
        secondsRemaining = totalSeconds
        isRunning = true
        isLocked = false

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.secondsRemaining > 0 {
                    self.secondsRemaining -= 1
                } else {
                    self.lock()
                }
            }
    }

    /// Stop and reset the timer
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        secondsRemaining = 0
        totalSeconds = 0
        currentPin = ""
    }

    /// Check if the entered PIN matches
    func checkPin(_ entered: String) -> Bool {
        return entered == currentPin
    }

    /// Unlock after correct PIN entry
    func unlock() {
        isLocked = false
        stop()
    }

    /// Add more time (in minutes)
    func addTime(minutes: Int) {
        secondsRemaining += minutes * 60
        totalSeconds += minutes * 60
        if isLocked {
            isLocked = false
            isRunning = true
            timer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    if self.secondsRemaining > 0 {
                        self.secondsRemaining -= 1
                    } else {
                        self.lock()
                    }
                }
        }
    }

    private func lock() {
        timer?.cancel()
        timer = nil
        isRunning = false
        isLocked = true
        // Pause any active video/audio playback
        pauseAllPlayback()
    }

    private func pauseAllPlayback() {
        // Dismiss any active video player and pause playback
        dismissTopPlayer()
        // Also post notification in case anything else needs to respond
        NotificationCenter.default.post(name: .watchTimerExpired, object: nil)
    }

    var formattedTimeRemaining: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(secondsRemaining) / Double(totalSeconds)
    }
}

extension Notification.Name {
    static let watchTimerExpired = Notification.Name("watchTimerExpired")
}
