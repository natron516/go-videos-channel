import Foundation

// MARK: - Asset (VOD)

struct MuxAsset: Identifiable, Decodable {
    let id: String
    let status: String
    let duration: Double?
    let playbackIds: [MuxPlaybackId]?
    let passthrough: String? // Use this to store title/speaker JSON

    enum CodingKeys: String, CodingKey {
        case id, status, duration, passthrough
        case playbackIds = "playback_ids"
    }

    var playbackId: String? {
        playbackIds?.first?.id
    }

    var streamURL: URL? {
        guard let pid = playbackId else { return nil }
        return URL(string: "https://stream.mux.com/\(pid).m3u8")
    }

    var thumbnailURL: URL? {
        guard let pid = playbackId else { return nil }
        return URL(string: "https://image.mux.com/\(pid)/thumbnail.jpg?width=640&time=10")
    }

    // Parse title/speaker from passthrough JSON field
    var title: String {
        guard let data = passthrough?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let t = json["title"] else {
            return id
        }
        return t
    }

    var speaker: String? {
        guard let data = passthrough?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return json["speaker"]
    }
}

struct MuxPlaybackId: Decodable {
    let id: String
    let policy: String
}

struct MuxAssetsResponse: Decodable {
    let data: [MuxAsset]
}

// MARK: - Live Stream

struct MuxLiveStream: Identifiable, Decodable {
    let id: String
    let status: String // "active", "idle", "disabled"
    let playbackIds: [MuxPlaybackId]?
    let streamKey: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case playbackIds = "playback_ids"
        case streamKey = "stream_key"
    }

    var isLive: Bool { status == "active" }

    var playbackId: String? {
        playbackIds?.first?.id
    }

    var streamURL: URL? {
        guard let pid = playbackId else { return nil }
        return URL(string: "https://stream.mux.com/\(pid).m3u8")
    }
}

struct MuxLiveStreamsResponse: Decodable {
    let data: [MuxLiveStream]
}
