import Foundation
import FirebaseFirestore

/// Reads the curated featured-video list from Firestore (config/featured).
/// The admin dashboard writes this; the app reads it on every home-screen load.
@MainActor
class FeaturedManager: ObservableObject {
    static let shared = FeaturedManager()

    /// Ordered list of Mux asset IDs to show on the home screen.
    /// Empty = fall back to recent videos.
    @Published private(set) var featuredIds: [String] = []
    @Published private(set) var isLoaded = false

    private let db = Firestore.firestore()

    func fetch() async {
        do {
            let doc = try await db.collection("config").document("featured").getDocument()
            featuredIds = doc.data()?["ids"] as? [String] ?? []
        } catch {
            featuredIds = []
        }
        isLoaded = true
    }
}
