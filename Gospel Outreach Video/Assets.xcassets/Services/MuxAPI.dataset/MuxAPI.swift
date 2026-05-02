import Foundation

class MuxAPI: ObservableObject {
    static let shared = MuxAPI()

    // MARK: - Credentials
    // Replace MUX_SECRET_KEY with your actual secret key (never commit to git)
    private let tokenID = "b6c48444-9330-4a8c-9ddd-fdb3f05f9d1f"
    private let secretKey = "MUX_SECRET_KEY" // ← paste your secret key here

    private let baseURL = "https://api.mux.com"

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

    func fetchAssets() async throws -> [MuxAsset] {
        let req = request(path: "/video/v1/assets?limit=100&order_direction=desc")
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(MuxAssetsResponse.self, from: data)
        return response.data.filter { $0.status == "ready" }
    }

    // MARK: - Live Streams

    func fetchLiveStreams() async throws -> [MuxLiveStream] {
        let req = request(path: "/video/v1/live-streams")
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(MuxLiveStreamsResponse.self, from: data)
        return response.data
    }

    func activeLiveStream() async throws -> MuxLiveStream? {
        let streams = try await fetchLiveStreams()
        return streams.first { $0.isLive }
    }
}
