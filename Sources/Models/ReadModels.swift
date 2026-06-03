import Foundation

struct GOBook: Identifiable, Codable {
    let id: String
    var title: String
    var author: String
    var description: String
    var coverImageUrl: String?
    var category: String
    var amazonUrl: String?
    var kindleUrl: String?
    var audiobookUrl: String?
    var featured: Bool
    var sortOrder: Int
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, author, description, coverImageUrl, category
        case amazonUrl, kindleUrl, audiobookUrl, featured, sortOrder, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        description = try container.decode(String.self, forKey: .description)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        amazonUrl = try container.decodeIfPresent(String.self, forKey: .amazonUrl)
        kindleUrl = try container.decodeIfPresent(String.self, forKey: .kindleUrl)
        audiobookUrl = try container.decodeIfPresent(String.self, forKey: .audiobookUrl)
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        // Handle both ISO string and numeric timestamp
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
        try container.encode(author, forKey: .author)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(amazonUrl, forKey: .amazonUrl)
        try container.encodeIfPresent(kindleUrl, forKey: .kindleUrl)
        try container.encodeIfPresent(audiobookUrl, forKey: .audiobookUrl)
        try container.encode(featured, forKey: .featured)
        try container.encode(sortOrder, forKey: .sortOrder)
        if let date = createdAt {
            try container.encode(date.timeIntervalSince1970, forKey: .createdAt)
        }
    }
}

struct GOArticle: Identifiable, Codable {
    let id: String
    var title: String
    var author: String
    var content: String // HTML
    var excerpt: String
    var coverImageUrl: String?
    var category: String
    var published: Bool
    var featured: Bool
    var sortOrder: Int
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, author, content, excerpt, coverImageUrl, category
        case published, featured, sortOrder, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? true
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
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
        try container.encode(author, forKey: .author)
        try container.encode(content, forKey: .content)
        try container.encode(excerpt, forKey: .excerpt)
        try container.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
        try container.encode(category, forKey: .category)
        try container.encode(published, forKey: .published)
        try container.encode(featured, forKey: .featured)
        try container.encode(sortOrder, forKey: .sortOrder)
        if let date = createdAt {
            try container.encode(date.timeIntervalSince1970, forKey: .createdAt)
        }
    }
}
