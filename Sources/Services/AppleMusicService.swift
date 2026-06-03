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
    @Published var playbackError: String?

    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }

    init() {
        authStatus = MusicAuthorization.currentStatus
        isAuthorized = authStatus == .authorized
        // Only start playback observation if already authorized
        if authStatus == .authorized {
            observePlayback()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authStatus = status
        isAuthorized = status == .authorized
        if status == .authorized {
            observePlayback()
        }
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
        playbackError = nil
        do {
            let detailed = try await album.with([.tracks])
            player.queue = [detailed]
            try await player.prepareToPlay()
            try await player.play()
        } catch {
            playbackError = error.localizedDescription
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
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let state = self.player.state
                    self.isPlaying = state.playbackStatus == .playing
                    self.nowPlayingTitle = self.player.queue.currentEntry?.title
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1s poll
                } catch {
                    break // Task cancelled
                }
            }
        }
    }

    func play(song: Song) async throws {
        let player = ApplicationMusicPlayer.shared
        player.queue = [song]
        try await player.play()
    }

    func play(track: MusicKit.Track) async throws {
        let player = ApplicationMusicPlayer.shared
        player.queue = [track]
        try await player.play()
    }

    func playPlaylist(_ playlist: MusicKit.Playlist) async throws {
        let player = ApplicationMusicPlayer.shared
        player.queue = [playlist]
        try await player.play()
    }
}