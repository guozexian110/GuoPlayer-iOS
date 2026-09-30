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

    static func normalize(_ raw: String, port: String = "") throws -> URL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw EmbyError.message("请输入有效的 HTTP 或 HTTPS 服务器地址")
        }
        let value = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            guard let number = Int(value), (1...65535).contains(number), value.allSatisfy({ $0.isNumber }) else { throw EmbyError.message("端口必须是 1–65535 之间的整数") }
            components.port = number
        }
        if let number = components.port, !(1...65535).contains(number) { throw EmbyError.message("端口必须是 1–65535 之间的整数") }
        guard let url = components.url else { throw EmbyError.message("服务器地址无效") }
        return url
    }
    static func addressFields(_ url: URL) -> (address: String, port: String) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let port = components.port.map(String.init) ?? ""
        components.port = nil
        return (components.string ?? url.absoluteString, port)
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
    let people: [MediaPerson]

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", year = "ProductionYear", overview = "Overview"
        case communityRating = "CommunityRating", providerIds = "ProviderIds", imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags", userData = "UserData", seriesId = "SeriesId"
        case parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber"
        case runTimeTicks = "RunTimeTicks", dateCreated = "DateCreated", people = "People"
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
        people = try c.decodeIfPresent([MediaPerson].self, forKey: .people) ?? []
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

struct MediaPerson: Decodable {
    let id: String?
    let name: String
    let role: String?
    let primaryImageTag: String?
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", role = "Role", primaryImageTag = "PrimaryImageTag" }
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
    static func groups(_ items: [MediaItem], includeEpisodes: Bool = false) -> [MediaGroup] {
        var groups: [MediaGroup] = []
        for item in items where item.type == "Movie" || item.type == "Series" || (includeEpisodes && item.type == "Episode") {
            if item.type == "Episode" {
                groups.append(MediaGroup(id: "\(item.serverId):\(item.id)", variants: [item]))
                continue
            }
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
    let path: String?
    let requiredHttpHeaders: [String: String]?
    let directStreamUrl: String?
    let transcodingUrl: String?
    let mediaStreams: [MediaStream]
    let size: Int64?
    let bitrate: Int?
    enum CodingKeys: String, CodingKey { case id = "Id", container = "Container", supportsDirectPlay = "SupportsDirectPlay", supportsDirectStream = "SupportsDirectStream", path = "Path", requiredHttpHeaders = "RequiredHttpHeaders", directStreamUrl = "DirectStreamUrl", transcodingUrl = "TranscodingUrl", mediaStreams = "MediaStreams", size = "Size", bitrate = "Bitrate" }
    var resolutionLabel: String {
        let height = mediaStreams.first { $0.type == "Video" }?.height ?? 0
        if height >= 2000 { return "4K" }
        if height >= 1000 { return "1080P" }
        if height >= 700 { return "720P" }
        return container?.uppercased() ?? "视频"
    }
    var requiresVLC: Bool {
        let format = container?.lowercased() ?? ""
        let video = mediaStreams.filter { $0.type == "Video" }.compactMap { $0.codec?.lowercased() }
        let audio = mediaStreams.filter { $0.type == "Audio" }.compactMap { $0.codec?.lowercased() }
        return !["mp4", "m4v", "mov", "ts", "mpegts", "hls", "m3u8"].contains(format)
            || video.contains { !["h264", "hevc", "h265"].contains($0) }
            || audio.contains { !["aac", "mp3", "ac3", "eac3", "alac"].contains($0) }
    }
    var canDirectStreamOnApple: Bool {
        supportsDirectStream == true && directStreamUrl?.isEmpty == false && !requiresVLC
    }
    var remoteHTTPURL: URL? {
        guard let path, let url = URL(string: path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    var canTryRemoteOnApple: Bool {
        guard remoteHTTPURL != nil else { return false }
        return mediaStreams.filter { $0.type == "Video" }.compactMap { $0.codec?.lowercased() }.allSatisfy { ["h264", "hevc", "h265"].contains($0) }
            && mediaStreams.filter { $0.type == "Audio" }.compactMap { $0.codec?.lowercased() }.allSatisfy { ["aac", "mp3", "ac3", "eac3", "alac"].contains($0) }
    }
    var canDirectPlayOnApple: Bool {
        guard supportsDirectPlay == true, ["mp4", "m4v", "mov"].contains(container?.lowercased() ?? "") else { return false }
        let video = mediaStreams.filter { $0.type == "Video" }.compactMap { $0.codec?.lowercased() }
        let audio = mediaStreams.filter { $0.type == "Audio" }.compactMap { $0.codec?.lowercased() }
        return video.allSatisfy { ["h264", "hevc", "h265"].contains($0) }
            && audio.allSatisfy { ["aac", "mp3", "ac3", "eac3", "alac"].contains($0) }
    }
}
struct MediaStream: Decodable, Identifiable {
    let index: Int
    let type: String
    let displayTitle: String?
    let language: String?
    let isExternal: Bool?
    let width: Int?
    let height: Int?
    let codec: String?
    enum CodingKeys: String, CodingKey { case index = "Index", type = "Type", displayTitle = "DisplayTitle", language = "Language", isExternal = "IsExternal", width = "Width", height = "Height", codec = "Codec" }
    var id: Int { index }
}

struct ItemsPage: Decodable { let items: [MediaItem]; enum CodingKeys: String, CodingKey { case items = "Items" } }
