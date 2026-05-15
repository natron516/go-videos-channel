import Foundation

/// Posts a notification to navigate the app to a named section.
/// ContentView (iOS) and TVContentView (tvOS) observe this and switch accordingly.
enum AppNavigator {
    static let navigateToSermonsNotification = Notification.Name("app.navigateToSermons")

    static func goToSermons() {
        NotificationCenter.default.post(name: navigateToSermonsNotification, object: nil)
    }
}
