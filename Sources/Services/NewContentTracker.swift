import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// Tracks which categories have "new" videos (posted within the last 3 days).
/// On iOS, directly applies blue badge dots to UITabBar items.
class NewContentTracker: ObservableObject {
    static let shared = NewContentTracker()

    /// Categories that currently have new content (video posted < 3 days ago)
    @Published private(set) var newCategories: Set<String> = []

    private let newContentWindow: TimeInterval = 3 * 24 * 60 * 60  // 3 days in seconds

    /// (Legacy — tab badges now cleared, indicators are emoji in title)

    /// Call this whenever assets are fetched/refreshed.
    func update(assets: [MuxAsset]) {
        let now = Date()
        var categories = Set<String>()

        for asset in assets {
            guard let cat = asset.category,
                  let tsString = asset.createdAt,
                  let ts = Double(tsString) else { continue }
            let created = Date(timeIntervalSince1970: ts)
            if now.timeIntervalSince(created) < newContentWindow {
                categories.insert(cat)
            }
        }

        DispatchQueue.main.async {
            // Only update if changed — avoids triggering unnecessary SwiftUI redraws
            if self.newCategories != categories {
                self.newCategories = categories
            }
            #if os(iOS)
            self.clearAllBadges()
            #endif
        }
    }

    /// Check if a specific category has new content.
    func hasNew(_ category: String) -> Bool {
        newCategories.contains(category)
    }

    #if os(iOS)
    /// Aggressively clear ALL UIKit tab bar badges and app icon badge.
    /// Indicators are emoji-only in tab titles — nothing should set UIKit badges.
    func clearAllBadges() {
        // Clear app icon badge
        UIApplication.shared.applicationIconBadgeNumber = 0

        func clearTabBadges() -> Bool {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
                  let window = scene.windows.first
            else { return false }

            let items: [UITabBarItem]?
            if let tbc = window.rootViewController?.findTabBarController() {
                items = tbc.tabBar.items
            } else if let tabBar = window.findTabBar() {
                items = tabBar.items
            } else {
                return false
            }

            guard let items = items, !items.isEmpty else { return false }
            for item in items {
                item.badgeValue = nil
            }
            return true
        }

        if !clearTabBadges() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { _ = clearTabBadges() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { _ = clearTabBadges() }
        }
    }
    #endif
}

#if os(iOS)
extension UIViewController {
    func findTabBarController() -> UITabBarController? {
        if let tbc = self as? UITabBarController { return tbc }
        for child in children {
            if let found = child.findTabBarController() { return found }
        }
        if let presented = presentedViewController {
            return presented.findTabBarController()
        }
        return nil
    }
}

extension UIView {
    /// Find any UITabBar in the view hierarchy (works when UITabBarController lookup fails on iPad)
    func findTabBar() -> UITabBar? {
        if let tb = self as? UITabBar { return tb }
        for sub in subviews {
            if let found = sub.findTabBar() { return found }
        }
        return nil
    }
}
#endif
