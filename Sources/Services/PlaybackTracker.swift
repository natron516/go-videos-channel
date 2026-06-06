import Foundation
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

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

    /// Hash track ID to create a safe Firestore document ID
    private func safeId(_ trackId: String) -> String {
        let hash = SHA256.hash(data: Data(trackId.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
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
        playedTracks.contains(safeId(trackId))
    }

    /// Mark a track as played
    func markPlayed(_ trackId: String) {
        let id = safeId(trackId)
        guard let ref = collectionRef() else { return }
        playedTracks.insert(id)
        ref.document(id).setData([
            "played": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    /// Save playback position for resume
    func savePosition(_ trackId: String, seconds: Double) {
        let id = safeId(trackId)
        guard let ref = collectionRef() else { return }
        positions[id] = seconds
        ref.document(id).setData([
            "played": true,
            "position": seconds,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    /// Get saved position for a track (0 if none)
    func getPosition(_ trackId: String) -> Double {
        positions[safeId(trackId)] ?? 0
    }

    /// Clear position when playback completes naturally
    func clearPosition(_ trackId: String) {
        let id = safeId(trackId)
        guard let ref = collectionRef() else { return }
        positions.removeValue(forKey: id)
        ref.document(id).setData([
            "played": true,
            "position": 0,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
