import Foundation

struct LoginResult { let userId: String; let token: String; let serverName: String }

final class EmbyAPI {
    private let session: URLSession
    private let deviceId: String
    private let routeLock = NSLock()
    private var workingRoots: [String: String] = [:]
    init(session: URLSession = .shared) {
        self.session = session
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "GuoPlayerDeviceId") { deviceId = value }
        else { let value = UUID().uuidString; defaults.set(value, forKey: "GuoPlayerDeviceId"); deviceId = value }
    }

    private func roots(_ server: URL) -> [String] {
        let root = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        routeLock.lock(); let known = workingRoots[root]; routeLock.unlock()
        let defaults = root.lowercased().hasSuffix("/emby") ? [root, String(root.dropLast(5))] : [root + "/emby", root]
        return ([known].compactMap { $0 } + defaults).reduce(into: []) { result, value in if !result.contains(value) { result.append(value) } }
    }
    private func remember(_ base: URL, target: URL, path: String) {
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return }
        components.path = String(components.path.dropLast(path.count + 1)); components.queryItems = nil
        guard let value = components.string else { return }
        let key = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        routeLock.lock(); workingRoots[key] = value; routeLock.unlock()
    }
    private func endpoints(_ server: URL, _ path: String, query: [String: String] = [:]) -> [URL] {
        roots(server).compactMap { base in
            var components = URLComponents(string: base + "/" + path)
            components?.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
            return components?.url
        }
    }
    private func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? (a.scheme == "https" ? 443 : 80)) == (b.port ?? (b.scheme == "https" ? 443 : 80))
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
                if (200..<300).contains(status) { remember(base, target: target, path: path); return data }
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
        let apiRoot = roots(server.baseURL)[0]
        let raw: String
        if let absolute = URL(string: value), absolute.scheme != nil { raw = value }
        else if value.hasPrefix("/") {
            let origin = "\(server.baseURL.scheme ?? "https")://\(server.baseURL.host ?? "")\(server.baseURL.port.map { ":\($0)" } ?? "")"
            // Leading slash is an origin-relative URL supplied by Emby.
            // Prefix variants are handled by streamURLs when a proxy needs /emby.
            raw = origin + value
        } else { raw = apiRoot + "/" + value }
        guard var components = URLComponents(string: raw) else { return nil }
        if let target = components.url, !sameOrigin(target, server.baseURL) { return target }
        var query = components.queryItems ?? []
        if let target = components.url, sameOrigin(target, server.baseURL), !query.contains(where: { ["api_key", "x-emby-token"].contains($0.name.lowercased()) }) { query.append(URLQueryItem(name: "api_key", value: token)) }
        if let audio { query.removeAll { $0.name == "AudioStreamIndex" }; query.append(URLQueryItem(name: "AudioStreamIndex", value: "\(audio)")) }
        if let subtitle { query.removeAll { $0.name == "SubtitleStreamIndex" }; query.append(URLQueryItem(name: "SubtitleStreamIndex", value: "\(subtitle)")) }
        components.queryItems = query
        return components.url
    }
    // VLC can decode the original container without a server transcode.
    func subtitleURL(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource, track: MediaStream) -> URL {
        if let delivery = track.deliveryUrl, let resolved = playbackURL(server, value: delivery, token: token, audio: nil, subtitle: nil) { return resolved }
        let codec = track.codec?.lowercased() ?? "srt"
        let format = ["srt", "ass", "ssa", "vtt"].contains(codec) ? codec : "srt"
        return url(server, "Videos/\(item.id)/\(source.id)/Subtitles/\(track.index)/Stream.\(format)", query: ["api_key": token])
    }
    func originalStreamURLs(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource) -> [URL] {
        var candidates: [URL] = []
        if let value = source.directStreamUrl, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !sameOrigin(url, server.baseURL) { candidates.append(url) }
        if let remote = source.remoteHTTPURL { candidates.append(remote) }
        let query = ["api_key": token, "MediaSourceId": source.id, "DeviceId": deviceId, "Static": "true"]
        for root in roots(server.baseURL) {
            var value = URLComponents(string: root + "/Videos/\(item.id)/stream")!
            value.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let url = value.url, !candidates.contains(url) { candidates.append(url) }
        }
        for candidate in Array(candidates) where sameOrigin(candidate, server.baseURL) && candidate.path.hasSuffix("/stream") {
            var value = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
            let ext = source.container?.lowercased() ?? "mp4"
            value.path += "." + (ext == "m4v" ? "mp4" : ext)
            if let url = value.url, !candidates.contains(url) { candidates.append(url) }
        }
        return candidates
    }
    func streamURL(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource, forceTranscode: Bool, audio: Int? = nil, subtitle: Int? = nil, sessionId: String? = nil, preferServerTranscodingURL: Bool = true) -> URL {
        if !forceTranscode,
           let value = source.directStreamUrl {
            if let resolved = playbackURL(server, value: value, token: token, audio: audio, subtitle: subtitle) { return resolved }
        }
        if !forceTranscode, (source.canDirectPlayOnApple || source.canTryRemoteOnApple), let remote = source.remoteHTTPURL { return remote }
        if forceTranscode && preferServerTranscodingURL, let value = source.transcodingUrl,
           let resolved = playbackURL(server, value: value, token: token, audio: audio, subtitle: subtitle) {
            return resolved
        }
        if forceTranscode {
            var query = ["api_key": token, "MediaSourceId": source.id, "DeviceId": deviceId, "UserId": server.userId, "VideoCodec": "h264", "AudioCodec": "aac", "MaxStreamingBitrate": "40000000", "TranscodingContainer": "ts", "TranscodingProtocol": "hls", "RequireAvc": "true"]
            if let sessionId { query["PlaySessionId"] = sessionId }
            if let audio { query["AudioStreamIndex"] = "\(audio)" }
            if let subtitle { query["SubtitleStreamIndex"] = "\(subtitle)" }
            return url(server, "Videos/\(item.id)/master.m3u8", query: query)
        }
        var query = ["api_key": token, "MediaSourceId": source.id, "DeviceId": deviceId, "Static": "true"]
        if let audio { query["AudioStreamIndex"] = "\(audio)" }
        if let subtitle { query["SubtitleStreamIndex"] = "\(subtitle)" }
        return url(server, "Videos/\(item.id)/stream", query: query)
    }
    func streamURLs(_ server: EmbyServer, token: String, item: MediaItem, source: PlaybackSource, forceTranscode: Bool, audio: Int? = nil, subtitle: Int? = nil, sessionId: String? = nil, preferServerTranscodingURL: Bool = true) -> [URL] {
        let primary = streamURL(server, token: token, item: item, source: source, forceTranscode: forceTranscode,
                                audio: audio, subtitle: subtitle, sessionId: sessionId,
                                preferServerTranscodingURL: preferServerTranscodingURL)
        var candidates = [primary]
        func append(_ url: URL?) { if let url, !candidates.contains(url) { candidates.append(url) } }
        // External signed URLs must remain byte-for-byte intact; never add an Emby token.
        guard sameOrigin(primary, server.baseURL), let original = URLComponents(url: primary, resolvingAgainstBaseURL: false),
              let videoRange = original.path.range(of: "/Videos/", options: .caseInsensitive) else { return candidates }
        let suffix = String(original.path[videoRange.lowerBound...])
        for root in roots(server.baseURL) {
            guard let base = URLComponents(string: root) else { continue }
            var components = original
            components.path = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? suffix : base.path + suffix
            append(components.url)
        }
        // Some Emby versions expose only stream.{container}; preserve the same root.
        if !forceTranscode && suffix.hasSuffix("/stream") {
            for candidate in Array(candidates) {
                var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
                let ext = source.container?.lowercased() ?? "mp4"
                components.path += "." + (ext == "m4v" ? "mp4" : ext)
                append(components.url)
            }
        }
        return candidates
    }
    func resolveStreamURL(_ candidates: [URL], headers: [String: String] = [:]) async throws -> URL {
        var failure = "没有有效的视频地址"
        for url in candidates {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 12
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            request.setValue("GuoPlayer/iOS", forHTTPHeaderField: "User-Agent")
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPURLResponse, Error>) in
                let delegate = StreamHeaderProbe { continuation.resume(with: $0) }
                let connection = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
                delegate.connection = connection
                connection.dataTask(with: request).resume()
            }
            let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if [200, 206].contains(response.statusCode) && !type.contains("text/html") && !type.contains("application/json") { return url }
            if response.statusCode == 401 { throw EmbyError.message("视频地址返回 HTTP 401，请重新登录服务器") }
            failure = "视频地址返回 HTTP \(response.statusCode)" + (type.contains("text/html") ? "（返回了网页）" : "")
        }
        throw EmbyError.message(failure)
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

// Stop after the HTTP response headers so a Range-ignoring server cannot make
// the preflight download an entire movie. One continuation, completed once.
private final class StreamHeaderProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var connection: URLSession?
    private let lock = NSLock()
    private var finished = false
    private let result: (Result<HTTPURLResponse, Error>) -> Void
    init(result: @escaping (Result<HTTPURLResponse, Error>) -> Void) { self.result = result }
    private func finish(_ value: Result<HTTPURLResponse, Error>) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true; lock.unlock()
        result(value)
        connection?.invalidateAndCancel(); connection = nil
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.cancel)
        if let http = response as? HTTPURLResponse { finish(.success(http)) }
        else { finish(.failure(EmbyError.message("视频服务器没有有效 HTTP 响应"))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
