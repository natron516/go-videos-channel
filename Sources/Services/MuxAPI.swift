import Foundation

class MuxAPI: ObservableObject {
    static let shared = MuxAPI()

    // MARK: - Credentials
    // Replace MUX_SECRET_KEY with your actual secret key (never commit to git)
    private let tokenID = "25cd1f0d-e6d4-445b-a106-e9ccc7a9f103"
    private let secretKey = "AcQYv3xI4uyhDIOmgAfaP+rAX9ei6bXzpT95dcAc74ALgOAl04BLg6o9PYwGh/iljlF4FTYz2VM"

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
