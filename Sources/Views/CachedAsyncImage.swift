import SwiftUI

/// In-memory + disk-cached image loader that replaces AsyncImage.
/// Images persist across navigation so thumbnails appear instantly on revisit.
/// Supports an optional `fallbackURL` — if the primary URL fails or returns
/// an error status, the fallback is tried automatically.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let fallbackURL: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(url: URL?, fallbackURL: URL? = nil, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
                    .task(id: url) { await load() }
            }
        }
    }

    private func load() async {
        // Try primary URL first
        if let url, let img = await fetchImage(url) {
            self.image = img
            return
        }
        // Try fallback URL if primary failed
        if let fallbackURL, let img = await fetchImage(fallbackURL) {
            self.image = img
            return
        }
    }

    private func fetchImage(_ url: URL) async -> UIImage? {
        // Check memory cache
        if let cached = ImageCache.shared.get(url) {
            return cached
        }
        // Check disk cache via URLCache
        let request = URLRequest(url: url)
        if let data = URLCache.thumbnailCache.cachedResponse(for: request)?.data,
           let img = UIImage(data: data) {
            ImageCache.shared.set(img, for: url)
            return img
        }
        // Network fetch
        do {
            let (data, response) = try await URLSession.thumbnailSession.data(for: request)
            // Check for HTTP error status
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return nil
            }
            guard let img = UIImage(data: data) else { return nil }
            let cached = CachedURLResponse(response: response, data: data)
            URLCache.thumbnailCache.storeCachedResponse(cached, for: request)
            ImageCache.shared.set(img, for: url)
            return img
        } catch {
            return nil
        }
    }
}

// MARK: - Prefetch helper
/// Call with a list of thumbnail URLs to eagerly cache them all in the background.
func prefetchThumbnails(_ urls: [URL?]) {
    for case let url? in urls {
        guard ImageCache.shared.get(url) == nil else { continue }
        Task.detached(priority: .utility) {
            let request = URLRequest(url: url)
            // Disk hit?
            if let data = URLCache.thumbnailCache.cachedResponse(for: request)?.data,
               let img = UIImage(data: data) {
                ImageCache.shared.set(img, for: url)
                return
            }
            // Network
            guard let (data, response) = try? await URLSession.thumbnailSession.data(for: request),
                  let img = UIImage(data: data) else { return }
            let cached = CachedURLResponse(response: response, data: data)
            URLCache.thumbnailCache.storeCachedResponse(cached, for: request)
            ImageCache.shared.set(img, for: url)
        }
    }
}

// MARK: - Memory cache (NSCache)
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 80 * 1024 * 1024 // 80 MB
    }

    func get(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

// MARK: - Shared URLCache + URLSession for thumbnails
extension URLCache {
    static let thumbnailCache: URLCache = {
        // 20 MB memory, 100 MB disk
        let cache = URLCache(memoryCapacity: 20 * 1024 * 1024,
                             diskCapacity: 100 * 1024 * 1024,
                             directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Thumbnails"))
        return cache
    }()
}

extension URLSession {
    static let thumbnailSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.thumbnailCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
}
