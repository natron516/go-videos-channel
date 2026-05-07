import Foundation
import MusicKit
import Combine

@MainActor
class AppleMusicService: ObservableObject {
    static let shared = AppleMusicService()

    @Published var authStatus: MusicAuthorization.Status = .notDetermined
    @Published var isAuthorized: Bool = false
    @Published var searchResults: [Album] = []
    @Published var curatedAlbums: [Album] = []
    @Published var isLoading = false
    @Published var nowPlayingTitle: String?
    @Published var isPlaying = false

    private let player = ApplicationMusicPlayer.shared

    init() {
        authStatus = MusicAuthorization.currentStatus
        isAuthorized = authStatus == .authorized
        observePlayback()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authStatus = status
        isAuthorized = status == .authorized
    }

    // MARK: - Search

    func searchAlbums(query: String) async {
        guard isAuthorized, !query.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Album.self])
            request.limit = 25
            let response = try await request.response()
            searchResults = Array(response.albums)
        } catch {
            print("Apple Music search error: \(error)")
            searchResults = []
        }
    }

    // MARK: - Curated Albums (by ID)

    func loadCuratedAlbums(ids: [String]) async {
        guard isAuthorized else { return }
        isLoading = true
        defer { isLoading = false }

        var albums: [Album] = []
        for id in ids {
            do {
                let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                if let album = response.items.first {
                    albums.append(album)
                }
            } catch {
                print("Failed to load album \(id): \(error)")
            }
        }
        curatedAlbums = albums
    }

    // MARK: - Fetch Album Tracks

    func fetchTracks(for album: Album) async -> [Track] {
        do {
            let detailed = try await album.with([.tracks])
            return detailed.tracks.map { Array($0) } ?? []
        } catch {
            print("Failed to fetch tracks: \(error)")
            return []
        }
    }

    // MARK: - Playback

    func playAlbum(_ album: Album) async {
        do {
            let detailed = try await album.with([.tracks])
            player.queue = [detailed]
            try await player.play()
        } catch {
            print("Playback error: \(error)")
        }
    }

    func playTrack(_ track: Track, in album: Album) async {
        do {
            let detailed = try await album.with([.tracks])
            player.queue = [detailed]
            // Start from the specific track
            try await player.play()
            if let tracks = detailed.tracks {
                let trackArray = Array(tracks)
                if let index = trackArray.firstIndex(where: { $0.id == track.id }) {
                    // Skip to the right track
                    for _ in 0..<index {
                        try await player.skipToNextEntry()
                    }
                }
            }
        } catch {
            print("Track playback error: \(error)")
        }
    }

    func togglePlayPause() {
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            Task { try? await player.play() }
        }
    }

    func skipNext() {
        Task { try? await player.skipToNextEntry() }
    }

    func skipPrevious() {
        Task { try? await player.skipToPreviousEntry() }
    }

    func stop() {
        player.stop()
    }

    // MARK: - Observe Playback State

    private func observePlayback() {
        // Poll playback state
        Task {
            while true {
                let state = player.state
                isPlaying = state.playbackStatus == .playing
                if let entry = player.queue.currentEntry {
                    nowPlayingTitle = entry.title
                } else {
                    nowPlayingTitle = nil
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
