import Foundation

struct LoginResult { let userId: String; let token: String; let serverName: String }

final class EmbyAPI {
    private let session: URLSession
    private let deviceId: String
    init(session: URLSession = .shared) {
        self.session = session
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "GuoPlayerDeviceId") { deviceId = value }
        else { let value = UUID().uuidString; defaults.set(value, forKey: "GuoPlayerDeviceId"); deviceId = value }
    }

    private func endpoints(_ server: URL, _ path: String, query: [String: String] = [:]) -> [URL] {
        let root = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bases = root.lowercased().hasSuffix("/emby") ? [root] : [root + "/emby", root]
        return bases.compactMap { base in
            var components = URLComponents(string: base + "/" + path)
            components?.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
            return components?.url
        }
    }
    func url(_ server: EmbyServer, _ path: String, query: [String: String] = [:]) -> URL {
        endpoints(server.baseURL, path, query: query)[0]
    }
    private func request(_ base: URL, _ path: String, token: String? = nil, query: [String: String] = [:], method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        var lastError: Error = EmbyError.message("Emby 服务器不可用")
        for target in endpoints(base, path, query: query) {
            var req = URLRequest(url: target)
            req.httpMethod = method
            req.timeoutInterval = 35
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("MediaBrowser Client=\"GuoPlayer\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\"", forHTTPHeaderField: "X-Emby-Authorization")
            if let token { req.setValue(token, forHTTPHeaderField: "X-Emby-Token") }
            if let body {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let (data, response) = try await session.data(for: req)
                guard let status = (response as? HTTPURLResponse)?.statusCode else { throw EmbyError.message("服务器无有效 HTTP 响应") }
                if (200..<300).contains(status) { return data }
                if status == 401 { throw EmbyError.message("登录已过期，请重新登录") }
                lastError = EmbyError.message("Emby HTTP \(status)")
                if status != 404 { throw lastError }
            } catch { lastError = error; if (error as? EmbyError)?.errorDescription != "Emby HTTP 404" { throw error } }
        }
        throw lastError
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, serverId: UUID? = nil) throws -> T {
        let decoder = JSONDecoder()
        if let serverId { decoder.userInfo[.serverId] = serverId }
        return try decoder.decode(type, from: data)
    }
    func login(base: URL, username: String, password: String) async throws -> LoginResult {
        let auth = try await request(base, "Users/AuthenticateByName", method: "POST", body: ["Username": username, "Pw": password])
        let json = try JSONSerialization.jsonObject(with: auth) as? [String: Any]
        guard let user = json?["User"] as? [String: Any], let id = user["Id"] as? String,
              let token = json?["AccessToken"] as? String else { throw EmbyError.message("Emby 登录响应缺少账户信息") }
        let info = try? await request(base, "System/Info/Public")
        let publicInfo = info.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return LoginResult(userId: id, token: token, serverName: publicInfo?["ServerName"] as? String ?? "Emby")
    }
    func items(_ server: EmbyServer, token: String, parentId: String? = nil, search: String? = nil, types: String = "Movie,Series", limit: Int = 200, start: Int = 0, sort: String = "DateCreated") async throws -> [MediaItem] {
        var query = ["Recursive": "true", "IncludeItemTypes": types, "Fields": "ProviderIds,Overview,DateCreated,MediaSources,UserData,RunTimeTicks,People", "SortBy": sort, "SortOrder": "Descending", "Limit": "\(limit)", "StartIndex": "\(start)"]
        if let parentId { query["ParentId"] = parentId }
        if let search, !search.isEmpty { query["SearchTerm"] = search }
        let data = try await request(server.baseURL, "Users/\(server.userId)/Items", token: token, query: query)
        return try decode(ItemsPage.self, data, serverId: server.id).items
    }
    func resume(_ server: EmbyServer, token: String) async throws -> [MediaItem] {
        let data = try await request(server.baseURL, "Users/\(server.userId)/Items/Resume", token: token, query: ["Limit": "30", "Fields": "ProviderIds,Overview,UserData,RunTimeTicks"])
        return try decode(ItemsPage.self, data, serverId: server.id).items
    }
    func views(_ server: EmbyServer, token: String) async throws -> [MediaItem] {
        let data = try await request(server.baseURL, "Users/\(server.userId)/Views", token: token)
        return try decode(ItemsPage.self, data, serverId: server.id).items
    }
    func episodes(_ server: EmbyServer, token: String, seriesId: String) async throws -> [MediaItem] {
        let data = try await request(server.baseURL, "Shows/\(seriesId)/Episodes", token: token, query: ["UserId": server.userId, "Fields": "Overview,UserData,RunTimeTicks", "Limit": "500"])
        return try decode(ItemsPage.self, data, serverId: server.id).items
    }
    // Negotiate URLs for AVFoundation instead of relying on the server's default profile.
    static var appleProfile: [String: Any] {
        ["Name": "GuoPlayer AVFoundation", "MaxStreamingBitrate": 40_000_000,
         "DirectPlayProfiles": [["Container": "mp4,m4v,mov", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,mp3,ac3,eac3,alac"]],
         "TranscodingProfiles": [["Container": "ts", "Type": "Video", "Protocol": "hls", "VideoCodec": "h264", "AudioCodec": "aac", "Context": "Streaming", "MaxAudioChannels": "2", "MinSegments": 2, "BreakOnNonKeyFrames": false]],
         "SubtitleProfiles": [["Format": "vtt", "Method": "External"], ["Format": "srt", "Method": "Encode"], ["Format": "ass", "Method": "Encode"], ["Format": "pgssub", "Method": "Encode"]]]
    }
    func playback(_ server: EmbyServer, token: String, item: MediaItem) async throws -> PlaybackInfo {
        let path = "Items/\(item.id)/PlaybackInfo"
        let data: Data
        do { data = try await request(server.baseURL, path, token: token, query: ["UserId": server.userId], method: "POST", body: ["UserId": server.userId, "StartTimeTicks": item.userData?.playbackPositionTicks ?? 0, "MaxStreamingBitrate": 40_000_000, "IsPlayback": true, "AutoOpenLiveStream": true, "DeviceProfile": Self.appleProfile]) }
        catch { data = try await request(server.baseURL, path, token: token, query: ["UserId": server.userId]) }
        return try decode(PlaybackInfo.self, data)
    }
    func imageURL(_ server: EmbyServer, token: String, item: MediaItem, backdrop: Bool = false) -> URL? {
        guard backdrop ? !item.backdropImageTags.isEmpty : item.imageTags["Primary"] != nil else { return nil }
        return url(server, "Items/\(item.id)/Images/" + (backdrop ? "Backdrop/0" : "Primary"), query: ["maxWidth": backdrop ? "1400" : "450", "api_key": token])
    }
    private func playbackURL(_ server: EmbyServer, value: String, token: String, audio: Int?, subtitle: Int?) -> URL? {
        let root = server.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiRoot = root.lowercased().hasSuffix("/emby") ? root : root + "/emby"
        let raw: String
        if let absolute = URL(string: value), absolute.scheme != nil { raw = value }
        else if value.hasPrefix("/") {
            let origin = "\(server.baseURL.scheme ?? "https")://\(server.baseURL.host ?? "")\(server.baseURL.port.map { ":\($0)" } ?? "")"
            // Leading slash is an origin-relative URL supplied by Emby.
            // Prefix variants are handled by streamURLs when a proxy needs /emby.
            raw = origin + value
        } else { raw = apiRoot + "/" + value }
        guard var components = URLComponents(string: raw) else { return nil }
        var query = components.queryItems ?? []
        if !query.contains(where: { $0.name.lowercased() == "api_key" }) { query.append(URLQueryItem(name: "api_key", value: token)) }
        if let audio { query.removeAll { $0.name == "AudioStreamIndex" }; query.append(URLQueryItem(name: "AudioStreamIndex", value: "\(audio)")) }
        if let subtitle { query.removeAll { $0.name == "SubtitleStreamIndex" }; query.append(URLQueryItem(name: "SubtitleStreamIndex", value: "\(subtitle)")) }
        components.queryItems = query
        return components.url
    }
    func streamURL(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource, forceTranscode: Bool, audio: Int? = nil, subtitle: Int? = nil, sessionId: String? = nil, preferServerTranscodingURL: Bool = true) -> URL {
        if !forceTranscode && !source.canDirectPlayOnApple && source.canDirectStreamOnApple,
           let value = source.directStreamUrl {
            if let resolved = playbackURL(server, value: value, token: token, audio: audio, subtitle: subtitle) { return resolved }
        }
        if forceTranscode && preferServerTranscodingURL, let value = source.transcodingUrl,
           let resolved = playbackURL(server, value: value, token: token, audio: audio, subtitle: subtitle) {
            return resolved
        }
        if forceTranscode {
            var query = ["api_key": token, "MediaSourceId": source.id, "VideoCodec": "h264", "AudioCodec": "aac", "MaxStreamingBitrate": "40000000", "TranscodingContainer": "ts", "TranscodingProtocol": "hls", "RequireAvc": "true"]
            if let sessionId { query["PlaySessionId"] = sessionId }
            if let audio { query["AudioStreamIndex"] = "\(audio)" }
            if let subtitle { query["SubtitleStreamIndex"] = "\(subtitle)" }
            return url(server, "Videos/\(item.id)/master.m3u8", query: query)
        }
        var query = ["api_key": token, "MediaSourceId": source.id, "Static": "true"]
        if let audio { query["AudioStreamIndex"] = "\(audio)" }
        if let subtitle { query["SubtitleStreamIndex"] = "\(subtitle)" }
        return url(server, "Videos/\(item.id)/stream", query: query)
    }
    func streamURLs(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource, forceTranscode: Bool, audio: Int? = nil, subtitle: Int? = nil, sessionId: String? = nil, preferServerTranscodingURL: Bool = true) -> [URL] {
        let primary = streamURL(server, token: token, item: item, source: source, forceTranscode: forceTranscode,
                                audio: audio, subtitle: subtitle, sessionId: sessionId,
                                preferServerTranscodingURL: preferServerTranscodingURL)
        var candidates = [primary]
        guard primary.host?.lowercased() == server.baseURL.host?.lowercased(),
              var alternative = URLComponents(url: primary, resolvingAgainstBaseURL: false) else { return candidates }
        var path = alternative.percentEncodedPath
        if let range = path.range(of: "/emby/Videos/", options: .caseInsensitive) {
            path.replaceSubrange(range, with: "/Videos/")
        } else if let range = path.range(of: "/Videos/", options: .caseInsensitive) {
            path.replaceSubrange(range, with: "/emby/Videos/")
        } else { return candidates }
        alternative.percentEncodedPath = path
        if let alternateURL = alternative.url, alternateURL != primary { candidates.append(alternateURL) }
        return candidates
    }
    func report(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource, session: String?, position: Int64, phase: String, paused: Bool = false, method: String = "DirectPlay") async {
        var body: [String: Any] = ["ItemId": item.id, "MediaSourceId": source.id, "PositionTicks": position, "IsPaused": paused, "PlayMethod": method]
        if let session { body["PlaySessionId"] = session }
        _ = try? await request(server.baseURL, "Sessions/Playing" + phase, token: token, method: "POST", body: body)
    }
    func favorite(_ server: EmbyServer, token: String, item: MediaItem, enable: Bool) async throws {
        _ = try await request(server.baseURL, "Users/\(server.userId)/FavoriteItems/\(item.id)", token: token, method: enable ? "POST" : "DELETE")
    }
}
