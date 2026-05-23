import Foundation
import UIKit

// MARK: - Asset (VOD)

struct MuxAsset: Identifiable, Decodable {
    let id: String
    let status: String
    let duration: Double?
    let playbackIds: [MuxPlaybackId]?
    let passthrough: String? // category tag ("sermon", "children", "music", "performance")
    let meta: MuxAssetMeta?
    let createdAt: String?
    let live_stream_id: String?

    enum CodingKeys: String, CodingKey {
        case id, status, duration, passthrough, meta, live_stream_id
        case playbackIds = "playback_ids"
        case createdAt = "created_at"
    }

    var playbackId: String? {
        playbackIds?.first?.id
    }

    var streamURL: URL? {
        guard let pid = playbackId else { return nil }
        return URL(string: "https://stream.mux.com/\(pid).m3u8")
    }

    /// govideos:// deep link — opens directly in the GO Media app
    var shareURL: URL? {
        guard let stream = streamURL else { return nil }
        var comps = URLComponents()
        comps.scheme = "govideos"
        comps.host   = "play"
        comps.queryItems = [
            URLQueryItem(name: "url",   value: stream.absoluteString),
            URLQueryItem(name: "title", value: title),
        ]
        return comps.url ?? stream
    }

    /// Mux auto-generated thumbnail (always available if playbackId exists).
    var muxThumbnailURL: URL? {
        guard let pid = playbackId else { return nil }
        #if os(tvOS)
        let w = 480
        #else
        let w = UIDevice.current.userInterfaceIdiom == .pad ? 400 : 320
        #endif
        let stableHash = id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let isSermon = category == "sermon"
        let t: Int
        if isSermon, let duration = duration, duration > 30 * 60 {
            let startSec = 17 * 60
            let endSec   = 27 * 60
            let range = endSec - startSec
            t = startSec + (abs(stableHash) % range)
        } else if let duration = duration, duration > 0 {
            let start = duration * 0.10
            let end   = duration * 0.80
            let range = max(Int(end - start), 1)
            t = Int(start) + (abs(stableHash) % range)
        } else {
            t = 10
        }
        return URL(string: "https://image.mux.com/\(pid)/thumbnail.webp?width=\(w)&time=\(t)")
    }

    /// Primary thumbnail: custom if set, otherwise Mux auto-generated.
    var thumbnailURL: URL? {
        if let custom = passthroughJSON?["thumbnail"], let url = URL(string: custom) {
            return url
        }
        return muxThumbnailURL
    }

    /// Fallback thumbnail if primary (custom) fails to load.
    var fallbackThumbnailURL: URL? {
        // Only useful when there's a custom thumbnail to fall back from
        guard passthroughJSON?["thumbnail"] != nil else { return nil }
        return muxThumbnailURL
    }

    /// For featured cards: rotates to a different video frame every 4 hours.
    /// Falls back to custom thumbnail if one is set (never rotates those).
    var featuredThumbnailURL: URL? {
        // Custom thumbnail wins — no rotation (fallback handled by CachedAsyncImage)
        if let custom = passthroughJSON?["thumbnail"], let url = URL(string: custom) {
            return url
        }
        guard let pid = playbackId, let duration = duration, duration > 60 else {
            return thumbnailURL
        }
        #if os(tvOS)
        let w = 480
        #else
        let w = UIDevice.current.userInterfaceIdiom == .pad ? 400 : 320
        #endif
        // 1-hour bucket: changes every hour on the hour
        let bucket = Int(Date().timeIntervalSince1970 / 3600)
        // Stable per-asset hash (not session-randomised like hashValue)
        let stableHash = id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let seed = abs(stableHash &+ bucket)
        // Pick a frame from the middle 80% of the video (skip intro/credits)
        let start = duration * 0.05
        let end   = duration * 0.85
        let range = max(Int(end - start), 1)
        let t     = Int(start) + (seed % range)
        return URL(string: "https://image.mux.com/\(pid)/thumbnail.jpg?width=\(w)&fit_mode=preserve&time=\(t)")
    }

    // Supports plain text passthrough ("sermon", "sermon", "children", etc.) OR JSON
    private var passthroughJSON: [String: String]? {
        guard let data = passthrough?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }

    var title: String {
        // Priority: Mux meta.title → passthrough JSON title → "Sermon"
        meta?.title ?? passthroughJSON?["title"] ?? "Sermon"
    }

    var formattedDate: String? {
        guard let ts = createdAt, let interval = Double(ts) else { return nil }
        let date = Date(timeIntervalSince1970: interval)
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
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

extension MuxAsset {
    /// Minimal stub built from a playback ID + optional title — used for deep-link playback.
    static func stub(playbackId: String, title: String?) -> MuxAsset? {
        // Encode a minimal JSON blob so Decodable initialiser works
        let json: [String: Any] = [
            "id": playbackId,
            "status": "ready",
            "playback_ids": [["id": playbackId, "policy": "public"]],
            "meta": ["title": title ?? "Video"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let asset = try? JSONDecoder().decode(MuxAsset.self, from: data) else { return nil }
        return asset
    }
}

// MARK: - Live Stream

struct MuxLiveStream: Identifiable, Decodable {
    let id: String
    let status: String // "active", "idle", "disabled"
    let playbackIds: [MuxPlaybackId]?
    let streamKey: String?
    let meta: MuxAssetMeta?
    let passthrough: String?
    let recentAssetIds: [String]?   // asset IDs from recent sessions (includes past)
    let activeAssetId: String?       // ID of the asset being recorded RIGHT NOW

    enum CodingKeys: String, CodingKey {
        case id, status, meta, passthrough
        case playbackIds = "playback_ids"
        case streamKey = "stream_key"
        case recentAssetIds = "recent_asset_ids"
        case activeAssetId = "active_asset_id"
    }

    /// Parsed passthrough JSON dictionary (same approach as MuxAsset).
    private var passthroughJSON: [String: String]? {
        guard let data = passthrough?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// The Mux category for this live stream, parsed from passthrough JSON.
    var category: String? {
        if let cat = passthroughJSON?["category"] { return cat.lowercased() }
        guard let raw = passthrough?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty, !raw.hasPrefix("{") else { return nil }
        return raw
    }

    var isSermon: Bool {
        guard let p = passthrough?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return p == "sermon" || p.hasPrefix("{\"category\":\"sermon")
    }

    var isLive: Bool { status == "active" }

    var title: String { meta?.title ?? "Live Service" }

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
