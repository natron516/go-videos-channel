import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Tracks per-user playback state in Firestore:
/// - Which episodes/tracks have been played (for blue dot indicator)
/// - Last playback position (for resume)
/// Structure: users/{uid}/playback/{trackId} → { played: true, position: Double, updatedAt: Timestamp }
@MainActor
class PlaybackTracker: ObservableObject {
    static let shared = PlaybackTracker()

    /// Set of track IDs the current user has played
    @Published var playedTracks: Set<String> = []

    /// Cached positions: trackId → seconds
    private var positions: [String: Double] = [:]
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    private init() {
        // Listen for auth changes to reload data
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if user != nil {
                    self?.startListening()
                } else {
                    self?.playedTracks.removeAll()
                    self?.positions.removeAll()
                    self?.listener?.remove()
                    self?.listener = nil
                }
            }
        }
    }

    // MARK: - Firestore path

    private var uid: String? { Auth.auth().currentUser?.uid }

    private func collectionRef() -> CollectionReference? {
        guard let uid else { return nil }
        return db.collection("users").document(uid).collection("playback")
    }

    // MARK: - Listen for real-time updates

    func startListening() {
        listener?.remove()
        guard let ref = collectionRef() else { return }
        listener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self, let docs = snap?.documents else { return }
            Task { @MainActor in
                var played = Set<String>()
                var pos: [String: Double] = [:]
                for doc in docs {
                    let data = doc.data()
                    if data["played"] as? Bool == true {
                        played.insert(doc.documentID)
                    }
                    if let p = data["position"] as? Double, p > 0 {
                        pos[doc.documentID] = p
                    }
                }
                self.playedTracks = played
                self.positions = pos
            }
        }
    }

    // MARK: - Public API

    /// Check if a track has been played by the current user
    func hasPlayed(_ trackId: String) -> Bool {
        playedTracks.contains(trackId)
    }

    /// Mark a track as played
    func markPlayed(_ trackId: String) {
        guard let ref = collectionRef() else { return }
        playedTracks.insert(trackId)
        ref.document(trackId).setData([
            "played": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    /// Save playback position for resume
    func savePosition(_ trackId: String, seconds: Double) {
        guard let ref = collectionRef() else { return }
        positions[trackId] = seconds
        ref.document(trackId).setData([
            "played": true,
            "position": seconds,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    /// Get saved position for a track (0 if none)
    func getPosition(_ trackId: String) -> Double {
        positions[trackId] ?? 0
    }

    /// Clear position when playback completes naturally
    func clearPosition(_ trackId: String) {
        guard let ref = collectionRef() else { return }
        positions.removeValue(forKey: trackId)
        ref.document(trackId).setData([
            "played": true,
            "position": 0,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
