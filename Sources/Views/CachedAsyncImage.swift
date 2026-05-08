import SwiftUI

/// In-memory + disk-cached image loader that replaces AsyncImage.
/// Images persist across navigation so thumbnails appear instantly on revisit.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

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
        guard let url else { return }
        // Check memory cache
        if let cached = ImageCache.shared.get(url) {
            self.image = cached
            return
        }
        // Check disk cache via URLCache
        let request = URLRequest(url: url)
        if let data = URLCache.thumbnailCache.cachedResponse(for: request)?.data,
           let img = UIImage(data: data) {
            ImageCache.shared.set(img, for: url)
            self.image = img
            return
        }
        // Network fetch
        do {
            let (data, response) = try await URLSession.thumbnailSession.data(for: request)
            guard let img = UIImage(data: data) else { return }
            // Store in disk cache
            let cached = CachedURLResponse(response: response, data: data)
            URLCache.thumbnailCache.storeCachedResponse(cached, for: request)
            // Store in memory cache
            ImageCache.shared.set(img, for: url)
            self.image = img
        } catch {
            // Silently fail — placeholder stays visible
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
