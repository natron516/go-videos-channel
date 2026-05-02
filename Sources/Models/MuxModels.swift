import Foundation

// MARK: - Asset (VOD)

struct MuxAsset: Identifiable, Decodable {
    let id: String
    let status: String
    let duration: Double?
    let playbackIds: [MuxPlaybackId]?
    let passthrough: String? // category tag ("sermon", "children", "music", "performance")
    let meta: MuxAssetMeta?

    enum CodingKeys: String, CodingKey {
        case id, status, duration, passthrough, meta
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

    // Supports plain text passthrough ("sermon", "sermon", "children", etc.) OR JSON
    private var passthroughJSON: [String: String]? {
        guard let data = passthrough?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }

    var title: String {
        // Priority: Mux meta.title → passthrough JSON title → asset ID
        meta?.title ?? passthroughJSON?["title"] ?? "Untitled"
    }

    var speaker: String? {
        passthroughJSON?["speaker"]
    }

    var category: String? {
        // If JSON has category field, use it
        if let cat = passthroughJSON?["category"] { return cat.lowercased() }
        // Otherwise treat the whole passthrough string as the category
        guard let raw = passthrough?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty, !raw.hasPrefix("{") else { return nil }
        return raw
    }
}

struct MuxAssetMeta: Decodable {
    let title: String?
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
