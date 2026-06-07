import Foundation

class MuxAPI: ObservableObject {
    static let shared = MuxAPI()

    // MARK: - Credentials
    private let tokenID = "25cd1f0d-e6d4-445b-a106-e9ccc7a9f103"
    private let secretKey = "AcQYv3xI4uyhDIOmgAfaP+rAX9ei6bXzpT95dcAc74ALgOAl04BLg6o9PYwGh/iljlF4FTYz2VM"

    private let baseURL = "https://api.mux.com"

    // MARK: - In-memory response cache
    private(set) var cachedAssets: [MuxAsset]?
    private var cachedAssetsDate: Date?
    private var cachedLiveStreams: [MuxLiveStream]?
    private var cachedLiveDate: Date?
    /// How long cached data is served before a background refresh (seconds)
    private let cacheMaxAge: TimeInterval = 120

    private var authHeader: String {
        let credentials = "\(tokenID):\(secretKey)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func request(path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    // MARK: - Assets (VOD)

    /// Returns all non-hidden assets including private ones (for authorized users).
    func fetchAllAssets() async throws -> [MuxAsset] {
        if let cached = cachedAssets, let date = cachedAssetsDate {
            if Date().timeIntervalSince(date) < cacheMaxAge { return cached }
            Task.detached(priority: .utility) { [weak self] in try? await self?.refreshAssets() }
            return cached
        }
        return try await refreshAssets()
    }

    /// Returns cached assets instantly if available, refreshing in the background if stale.
    /// Private-category assets are excluded — use fetchAllAssets() for authorized access.
    func fetchAssets() async throws -> [MuxAsset] {
        // Return cache immediately if fresh enough
        let all = try await fetchAllAssets()
        return all.filter { $0.category != nil && $0.category != "hidden" }
    }

    @discardableResult
    private func refreshAssets() async throws -> [MuxAsset] {
        var allAssets: [MuxAsset] = []
        var cursor: String? = nil
        // Paginate through all Mux assets
        repeat {
            var path = "/video/v1/assets?limit=100&order_direction=desc"
            if let c = cursor {
                path += "&cursor=\(c)"
            }
            let req = request(path: path)
            let (data, _) = try await URLSession.shared.data(for: req)
            let response = try JSONDecoder().decode(MuxAssetsResponse.self, from: data)
            allAssets.append(contentsOf: response.data)
            cursor = response.next_cursor
        } while cursor != nil
        // Cache all ready assets including hidden; fetchAssets() strips hidden for regular users
        let assets = allAssets.filter { $0.status == "ready" || $0.status == "preparing" }
        await MainActor.run {
            cachedAssets = assets
            cachedAssetsDate = Date()
        }
        return assets
    }

    /// Force-refresh assets (e.g. pull-to-refresh)
    func reloadAssets() async throws -> [MuxAsset] {
        return try await refreshAssets()
    }

    // MARK: - Live Streams

    func fetchLiveStreams() async throws -> [MuxLiveStream] {
        if let cached = cachedLiveStreams, let date = cachedLiveDate,
           Date().timeIntervalSince(date) < 30 {
            return cached
        }
        let req = request(path: "/video/v1/live-streams")
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(MuxLiveStreamsResponse.self, from: data)
        cachedLiveStreams = response.data
        cachedLiveDate = Date()
        return response.data
    }

    func activeLiveStream() async throws -> MuxLiveStream? {
        let streams = try await fetchLiveStreams()
        return streams.first { $0.isLive }
    }
}
