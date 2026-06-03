import Foundation
import SwiftUI

/// Preloads all content during the splash screen so tabs load instantly.
/// Each view can check `ContentPreloader.shared` for cached data before fetching.
@MainActor
class ContentPreloader: ObservableObject {
    static let shared = ContentPreloader()

    // MARK: - Cached data

    @Published var books: [GOBook]?
    @Published var articles: [GOArticle]?
    @Published var podcasts: [GOPodcast]?
    @Published var audioAssets: [GOAudioAsset]?
    @Published var series: [GOSeries]?
    @Published var musicConfig: MusicConfig?

    @Published var isPreloading = false
    @Published var isComplete = false

    private var hasStarted = false

    // MARK: - Preload all content

    func preloadAll() async {
        guard !hasStarted else { return }
        hasStarted = true
        isPreloading = true

        let api = ContentAPI.shared

        // Fire all requests concurrently
        async let booksResult = safeLoad { try await api.fetchBooks() }
        async let articlesResult = safeLoad { try await api.fetchArticles() }
        async let podcastsResult = safeLoad { try await api.fetchPodcasts() }
        async let audioResult = safeLoad { try await api.fetchAudio() }
        async let seriesResult = safeLoad { try await api.fetchSeries() }
        async let musicResult = safeLoad { try await api.fetchMusicConfig() }

        // Also preload featured IDs (fire-and-forget, writes to FeaturedManager.shared)
        async let featuredDone: Void = FeaturedManager.shared.fetch()

        books = await booksResult
        articles = await articlesResult
        podcasts = await podcastsResult
        audioAssets = await audioResult
        series = await seriesResult
        musicConfig = await musicResult
        _ = await featuredDone

        isPreloading = false
        isComplete = true
    }

    // MARK: - Invalidation (force reload on pull-to-refresh)

    func invalidateBooks() { books = nil }
    func invalidateArticles() { articles = nil }
    func invalidatePodcasts() { podcasts = nil }
    func invalidateAudio() { audioAssets = nil }
    func invalidateSeries() { series = nil }
    func invalidateMusic() { musicConfig = nil }
    func invalidateAll() {
        books = nil
        articles = nil
        podcasts = nil
        audioAssets = nil
        series = nil
        musicConfig = nil
        hasStarted = false
        isComplete = false
    }

    // MARK: - Helper

    private func safeLoad<T>(_ block: @Sendable () async throws -> T) async -> T? {
        do {
            return try await block()
        } catch {
            print("[ContentPreloader] Error: \(error.localizedDescription)")
            return nil
        }
    }
}
