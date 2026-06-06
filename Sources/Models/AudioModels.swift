import Foundation

struct GOPodcast: Identifiable, Codable {
    let id: String
    var title: String
    var feedUrl: String
    var description: String
    var artworkUrl: String?
    var category: String
    var enabled: Bool
    var featured: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, title, feedUrl, description, artworkUrl, category, enabled, featured, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        feedUrl = try container.decodeIfPresent(String.self, forKey: .feedUrl) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(feedUrl, forKey: .feedUrl)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encode(category, forKey: .category)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(featured, forKey: .featured)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

struct GOPodcastEpisode: Identifiable, Codable {
    var id: String { title + audioUrl }
    var title: String
    var description: String
    var audioUrl: String
    var pubDate: String?
    var duration: String?
    var imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case title, description, audioUrl, pubDate, duration, imageUrl
    }
}

struct GOSeries: Identifiable, Codable {
    let id: String
    var title: String
    var description: String
    var artworkUrl: String?
    var category: String
    var mediaType: String  // "audio", "video", or "mixed"
    var enabled: Bool
    var featured: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description, artworkUrl, category, mediaType, enabled, featured, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "audio"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encode(category, forKey: .category)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(featured, forKey: .featured)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

struct GOAudioAsset: Identifiable, Codable {
    let id: String
    var title: String
    var artist: String
    var description: String
    var audioUrl: String
    var coverImageUrl: String?
    var category: String
    var duration: Double?
    var featured: Bool
    var sortOrder: Int
    var createdAt: Date?
    var seriesId: String?
    var episodeNumber: Int?
    var mediaType: String?  // "audio" or "video"

    enum CodingKeys: String, CodingKey {
        case id, title, artist, description, audioUrl, coverImageUrl, category
        case duration, featured, sortOrder, createdAt
        case seriesId, episodeNumber, mediaType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        audioUrl = try container.decode(String.self, forKey: .audioUrl)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        seriesId = try container.decodeIfPresent(String.self, forKey: .seriesId)
        episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        if let ts = try? container.decode(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: ts)
        } else if let str = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: str)
        } else {
            createdAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(description, forKey: .description)
        try container.encode(audioUrl, forKey: .audioUrl)
        try container.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(featured, forKey: .featured)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(seriesId, forKey: .seriesId)
        try container.encodeIfPresent(episodeNumber, forKey: .episodeNumber)
        try container.encodeIfPresent(mediaType, forKey: .mediaType)
        if let date = createdAt {
            try container.encode(date.timeIntervalSince1970, forKey: .createdAt)
        }
    }
}
