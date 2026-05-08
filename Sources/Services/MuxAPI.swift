import Foundation

class MuxAPI: ObservableObject {
    static let shared = MuxAPI()

    // MARK: - Credentials
    private let tokenID = "25cd1f0d-e6d4-445b-a106-e9ccc7a9f103"
    private let secretKey = "AcQYv3xI4uyhDIOmgAfaP+rAX9ei6bXzpT95dcAc74ALgOAl04BLg6o9PYwGh/iljlF4FTYz2VM"

    private let baseURL = "https://api.mux.com"

    // MARK: - In-memory response cache
    private var cachedAssets: [MuxAsset]?
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

    /// Returns cached assets instantly if available, refreshing in the background if stale.
    func fetchAssets() async throws -> [MuxAsset] {
        // Return cache immediately if fresh enough
        if let cached = cachedAssets, let date = cachedAssetsDate {
            if Date().timeIntervalSince(date) < cacheMaxAge {
                return cached
            }
            // Stale — return cache now, refresh in background
            Task.detached(priority: .utility) { [weak self] in
                try? await self?.refreshAssets()
            }
            return cached
        }
        // No cache — must fetch
        return try await refreshAssets()
    }

    @discardableResult
    private func refreshAssets() async throws -> [MuxAsset] {
        let req = request(path: "/video/v1/assets?limit=100&order_direction=desc")
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(MuxAssetsResponse.self, from: data)
        let assets = response.data.filter { $0.status == "ready" || $0.status == "preparing" }
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
