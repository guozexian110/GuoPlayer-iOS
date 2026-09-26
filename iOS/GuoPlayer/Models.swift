import Foundation

enum EmbyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct EmbyServer: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var baseURL: URL
    var userId: String
    var username: String

    static func normalize(_ raw: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw EmbyError.message("请输入有效的 HTTP 或 HTTPS 服务器地址")
        }
        return url
    }
}

struct MediaItem: Decodable, Identifiable, Hashable {
    let id: String
    let serverId: UUID
    let name: String
    let type: String
    let year: Int?
    let overview: String?
    let communityRating: Double?
    let providerIds: [String: String]
    let imageTags: [String: String]
    let backdropImageTags: [String]
    let userData: UserData?
    let seriesId: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let runTimeTicks: Int64?
    let dateCreated: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", year = "ProductionYear", overview = "Overview"
        case communityRating = "CommunityRating", providerIds = "ProviderIds", imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags", userData = "UserData", seriesId = "SeriesId"
        case parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber"
        case runTimeTicks = "RunTimeTicks", dateCreated = "DateCreated"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名"
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "Video"
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        communityRating = try c.decodeIfPresent(Double.self, forKey: .communityRating)
        providerIds = try c.decodeIfPresent([String: String].self, forKey: .providerIds) ?? [:]
        imageTags = try c.decodeIfPresent([String: String].self, forKey: .imageTags) ?? [:]
        backdropImageTags = try c.decodeIfPresent([String].self, forKey: .backdropImageTags) ?? []
        userData = try c.decodeIfPresent(UserData.self, forKey: .userData)
        seriesId = try c.decodeIfPresent(String.self, forKey: .seriesId)
        parentIndexNumber = try c.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
        indexNumber = try c.decodeIfPresent(Int.self, forKey: .indexNumber)
        runTimeTicks = try c.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
        dateCreated = try c.decodeIfPresent(String.self, forKey: .dateCreated)
        serverId = decoder.userInfo[.serverId] as? UUID ?? UUID()
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.serverId == rhs.serverId && lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(serverId); hasher.combine(id) }
    var isSeries: Bool { type == "Series" }
    var progress: Double {
        guard let ticks = userData?.playbackPositionTicks, let total = runTimeTicks, total > 0 else { return 0 }
        return min(1, Double(ticks) / Double(total))
    }
}

extension CodingUserInfoKey { static let serverId = CodingUserInfoKey(rawValue: "serverId")! }

struct UserData: Decodable {
    let playbackPositionTicks: Int64?
    let isFavorite: Bool?
    let played: Bool?
    enum CodingKeys: String, CodingKey { case playbackPositionTicks = "PlaybackPositionTicks", isFavorite = "IsFavorite", played = "Played" }
}

struct MediaGroup: Identifiable {
    let id: String
    var variants: [MediaItem]
    var primary: MediaItem { variants[0] }
    var title: String { primary.name }
    var isFavorite: Bool { variants.contains { $0.userData?.isFavorite == true } }
}

enum MediaAggregation {
    static func groups(_ items: [MediaItem]) -> [MediaGroup] {
        var groups: [MediaGroup] = []
        for item in items where item.type == "Movie" || item.type == "Series" {
            if let index = groups.firstIndex(where: { group in group.variants.contains { matches($0, item) } }) {
                if !groups[index].variants.contains(item) { groups[index].variants.append(item) }
            } else {
                groups.append(MediaGroup(id: "\(item.serverId):\(item.id)", variants: [item]))
            }
        }
        return groups
    }
    static func matches(_ a: MediaItem, _ b: MediaItem) -> Bool {
        guard a.type == b.type else { return false }
        let keys = ["Tmdb", "Imdb", "Tvdb"]
        for key in keys {
            if let x = provider(a, key), let y = provider(b, key), x != y { return false }
        }
        for key in keys {
            if let x = provider(a, key), let y = provider(b, key), x == y { return true }
        }
        guard a.providerIds.isEmpty, b.providerIds.isEmpty, let year = a.year, year == b.year else { return false }
        return a.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == b.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
    private static func provider(_ item: MediaItem, _ key: String) -> String? {
        item.providerIds.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value.lowercased()
    }
}

struct PlaybackInfo: Decodable {
    let mediaSources: [PlaybackSource]
    let playSessionId: String?
    enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources", playSessionId = "PlaySessionId" }
}
struct PlaybackSource: Decodable, Identifiable {
    let id: String
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let directStreamUrl: String?
    let transcodingUrl: String?
    let mediaStreams: [MediaStream]
    enum CodingKeys: String, CodingKey { case id = "Id", container = "Container", supportsDirectPlay = "SupportsDirectPlay", supportsDirectStream = "SupportsDirectStream", directStreamUrl = "DirectStreamUrl", transcodingUrl = "TranscodingUrl", mediaStreams = "MediaStreams" }
    var canDirectStreamOnApple: Bool {
        guard supportsDirectStream == true, let value = directStreamUrl?.lowercased() else { return false }
        return value.contains(".m3u8") || value.contains(".mp4") || value.contains(".mov")
    }
}
struct MediaStream: Decodable, Identifiable {
    let index: Int
    let type: String
    let displayTitle: String?
    let language: String?
    let isExternal: Bool?
    enum CodingKeys: String, CodingKey { case index = "Index", type = "Type", displayTitle = "DisplayTitle", language = "Language", isExternal = "IsExternal" }
    var id: Int { index }
}

struct ItemsPage: Decodable { let items: [MediaItem]; enum CodingKeys: String, CodingKey { case items = "Items" } }
