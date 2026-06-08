import Foundation

// Fetches books, articles, podcasts, audio, series from the GO Admin API
// Base URL: https://go-admin-production-6be4.up.railway.app
// All GET endpoints are behind basic auth (admin:gomedia)
//
// Endpoints:
// GET /api/books      → { books: [...] }
// GET /api/articles   → { articles: [...] }
// GET /api/podcasts   → { podcasts: [...] }
// GET /api/podcasts/:id/episodes → { episodes: [...] }
// GET /api/audio      → { audio: [...] }
// GET /api/series     → { series: [...] }
// GET /api/series/:id/episodes → { episodes: [...] }

@MainActor
class ContentAPI: ObservableObject {
    static let shared = ContentAPI()

    private let baseURL = "https://go-admin-production-6be4.up.railway.app"
    private let credentials = "admin:gomedia"

    private var authHeader: String {
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func request(path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        return req
    }

    // MARK: - Books

    func fetchBooks() async throws -> [GOBook] {
        let req = request(path: "/api/books")
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(BooksResponse.self, from: data)
        return wrapper.books
            .filter { $0.category != "hidden" && $0.category != "admin_only" }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Articles

    func fetchArticles() async throws -> [GOArticle] {
        let req = request(path: "/api/articles")
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(ArticlesResponse.self, from: data)
        return wrapper.articles
            .filter { $0.published && $0.category != "hidden" && $0.category != "admin_only" }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Podcasts

    func fetchPodcasts() async throws -> [GOPodcast] {
        let req = request(path: "/api/podcasts")
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(PodcastsResponse.self, from: data)
        return wrapper.podcasts
            .filter { $0.enabled && $0.category != "hidden" && $0.category != "admin_only" }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchEpisodes(podcastId: String) async throws -> [GOPodcastEpisode] {
        let path = "/api/podcasts/\(podcastId)/episodes"
        let req = request(path: path)
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(EpisodesResponse.self, from: data)
        return wrapper.episodes
    }

    // MARK: - Audio

    func fetchAudio() async throws -> [GOAudioAsset] {
        let req = request(path: "/api/audio")
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(AudioResponse.self, from: data)
        return wrapper.audio
            .filter { $0.category != "hidden" && $0.category != "admin_only" }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Series

    func fetchSeries() async throws -> [GOSeries] {
        let req = request(path: "/api/series")
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(SeriesResponse.self, from: data)
        return wrapper.series
            .filter { $0.enabled && $0.category != "hidden" && $0.category != "admin_only" }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchSeriesEpisodes(seriesId: String) async throws -> [GOAudioAsset] {
        let path = "/api/series/\(seriesId)/episodes"
        let req = request(path: path)
        let (data, _) = try await URLSession.shared.data(for: req)
        let wrapper = try JSONDecoder().decode(SeriesEpisodesResponse.self, from: data)
        return wrapper.episodes.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    // MARK: - Music Config

    func fetchMusicConfig() async throws -> MusicConfig {
        let req = request(path: "/api/music")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(MusicConfig.self, from: data)
    }
}

// MARK: - Response wrappers

private struct BooksResponse: Decodable {
    let books: [GOBook]
}

private struct ArticlesResponse: Decodable {
    let articles: [GOArticle]
}

private struct PodcastsResponse: Decodable {
    let podcasts: [GOPodcast]
}

private struct EpisodesResponse: Decodable {
    let episodes: [GOPodcastEpisode]
}

private struct AudioResponse: Decodable {
    let audio: [GOAudioAsset]
}

private struct SeriesResponse: Decodable {
    let series: [GOSeries]
}

private struct SeriesEpisodesResponse: Decodable {
    let episodes: [GOAudioAsset]
}

// MARK: - Music Config

struct MusicConfigAlbum: Decodable {
    let albumId: String
    let title: String?
    let artist: String?
    let type: String?
    let artworkUrl: String?
}

struct MusicConfigPlaylist: Decodable {
    let playlistId: String
    let title: String?
    let curatorName: String?
    let artworkUrl: String?
    let description: String?
}

struct MusicConfig: Decodable {
    let albums: [MusicConfigAlbum]?
    let playlists: [MusicConfigPlaylist]?
}
