import Foundation
import FirebaseFirestore
import Combine

final class ForceUpdateService: ObservableObject {
    static let shared = ForceUpdateService()

    @Published var updateRequired = false
    @Published var updateRecommended = false
    @Published var updateMessage = ""

    private var listener: ListenerRegistration?
    private let currentVersion: String

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        startListening()
    }

    deinit {
        listener?.remove()
    }

    private func startListening() {
        let db = Firestore.firestore()
        listener = db.collection("config").document("app")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let data = snapshot?.data() else { return }

                let enabled = data["forceUpdateEnabled"] as? Bool ?? true
                guard enabled else {
                    DispatchQueue.main.async {
                        self.updateRequired = false
                        self.updateRecommended = false
                        self.updateMessage = ""
                    }
                    return
                }

                let minimumVersion = data["minimumVersion"] as? String ?? "0.0.0"
                let recommendedVersion = data["recommendedVersion"] as? String ?? "0.0.0"
                let message = data["updateMessage"] as? String ?? ""

                let isBelow = Self.compareVersions(self.currentVersion, minimumVersion) == .orderedAscending
                let isBelowRecommended = Self.compareVersions(self.currentVersion, recommendedVersion) == .orderedAscending

                DispatchQueue.main.async {
                    self.updateRequired = isBelow
                    self.updateRecommended = isBelowRecommended && !isBelow
                    self.updateMessage = message
                }
            }
    }

    /// Semantic version comparison: "1.6.7" vs "1.6.8"
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(aParts.count, bParts.count)

        for i in 0..<maxLen {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal < bVal { return .orderedAscending }
            if aVal > bVal { return .orderedDescending }
        }
        return .orderedSame
    }
}
