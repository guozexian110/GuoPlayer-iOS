import Foundation

@main struct PlaybackSmoke {
    static func main() async throws {
        let server = EmbyServer(id: UUID(), name: "Test", baseURL: URL(string: "https://example.test/emby")!, userId: "user", username: "test")
        let decoder = JSONDecoder()
        decoder.userInfo[.serverId] = server.id
        let item = try decoder.decode(MediaItem.self, from: Data(#"{"Id":"video","Name":"Test","Type":"Movie"}"#.utf8))
        let source = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"source","Container":"mkv","SupportsDirectPlay":true,"SupportsDirectStream":false,"TranscodingUrl":"/emby/Videos/video/master.m3u8?MediaSourceId=source","MediaStreams":[{"Index":0,"Type":"Video","Codec":"hevc","Height":2160},{"Index":1,"Type":"Audio","Codec":"dts"}]}"#.utf8))
        precondition(!source.canDirectPlayOnApple && source.requiresVLC)
        let noTranscode = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"mkv","Container":"mkv","SupportsDirectPlay":true,"SupportsDirectStream":true,"DirectStreamUrl":"/emby/Videos/video/stream","MediaStreams":[{"Index":0,"Type":"Video","Codec":"hevc"},{"Index":1,"Type":"Audio","Codec":"flac"}]}"#.utf8))
        precondition(noTranscode.requiresVLC && !noTranscode.canDirectStreamOnApple && noTranscode.transcodingUrl == nil)
        let api = EmbyAPI()
        let originals = api.originalStreamURLs(server, token: "test-token", item: item, source: noTranscode)
        precondition(originals.first?.path == "/emby/Videos/video/stream")
        precondition(originals.allSatisfy { !$0.path.contains("m3u8") && URLComponents(url: $0, resolvingAgainstBaseURL: false)!.queryItems!.contains(URLQueryItem(name: "Static", value: "true")) })
        let serverURL = api.streamURL(server, token: "test-token", item: item, source: source, forceTranscode: true, audio: 1)
        let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        precondition(components.path == "/emby/Videos/video/master.m3u8")
        precondition(components.queryItems?.contains(URLQueryItem(name: "api_key", value: "test-token")) == true)
        precondition(components.queryItems?.contains(URLQueryItem(name: "AudioStreamIndex", value: "1")) == true)
        let fallback = api.streamURL(server, token: "test-token", item: item, source: source, forceTranscode: true, sessionId: "session", preferServerTranscodingURL: false)
        let fallbackQuery = URLComponents(url: fallback, resolvingAgainstBaseURL: false)!.queryItems ?? []
        precondition(fallback.path == "/emby/Videos/video/master.m3u8")
        precondition(fallbackQuery.contains(URLQueryItem(name: "PlaySessionId", value: "session")))
        let candidates = api.streamURLs(server, token: "test-token", item: item, source: source, forceTranscode: true)
        precondition(candidates.count == 2)
        precondition(candidates[0].path == "/emby/Videos/video/master.m3u8")
        precondition(candidates[1].path == "/Videos/video/master.m3u8")
        precondition(URLComponents(url: candidates[1], resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "api_key", value: "test-token")) == true)
        let relative = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"source","Container":"mkv","TranscodingUrl":"/Videos/video/master.m3u8?MediaSourceId=source","MediaStreams":[]}"#.utf8))
        precondition(api.streamURL(server, token: "test-token", item: item, source: relative, forceTranscode: true).path == "/Videos/video/master.m3u8")
        let mp4 = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"mp4","Container":"mp4","SupportsDirectPlay":true,"MediaStreams":[]}"#.utf8))
        precondition(api.streamURL(server, token: "test-token", item: item, source: mp4, forceTranscode: false).path == "/emby/Videos/video/stream")
        let proxied = EmbyServer(id: server.id, name: "Proxy", baseURL: URL(string: "https://example.test/proxy/emby")!, userId: "user", username: "test")
        let proxyURLs = api.streamURLs(proxied, token: "test-token", item: item, source: source, forceTranscode: true)
        precondition(proxyURLs.map(\.path).contains("/proxy/emby/Videos/video/master.m3u8"))
        precondition(proxyURLs.map(\.path).contains("/proxy/Videos/video/master.m3u8"))
        let external = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"external","Container":"mp4","DirectStreamUrl":"https://cdn.test/movie.mp4?signature=abc%2Fdef&expires=123","MediaStreams":[]}"#.utf8))
        let externalURLs = api.streamURLs(server, token: "private-emby-token", item: item, source: external, forceTranscode: false, audio: 1, subtitle: 2)
        precondition(externalURLs.count == 1)
        precondition(externalURLs[0].absoluteString == "https://cdn.test/movie.mp4?signature=abc%2Fdef&expires=123")
        let remoteSource = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"strm","Container":"strm","Path":"https://cdn.test/remote.mp4?signature=xyz","SupportsDirectPlay":false,"MediaStreams":[]}"#.utf8))
        precondition(remoteSource.canTryRemoteOnApple)
        precondition(api.streamURL(server, token: "private-emby-token", item: item, source: remoteSource, forceTranscode: false).absoluteString == "https://cdn.test/remote.mp4?signature=xyz")
        let addedPort = try EmbyServer.normalize("example.test/proxy", port: "8096")
        precondition(addedPort.absoluteString == "http://example.test:8096/proxy")
        let replacedPort = try EmbyServer.normalize("https://example.test:8920/emby", port: "443")
        precondition(replacedPort.absoluteString == "https://example.test:443/emby")
        let preservedPort = try EmbyServer.normalize("https://example.test:8920/emby")
        precondition(preservedPort.port == 8920)
        let ipv6 = try EmbyServer.normalize("http://[::1]/emby", port: "8096")
        precondition(ipv6.host != nil)
        let fields = EmbyServer.addressFields(URL(string: "https://example.test:8920/proxy/emby")!)
        precondition(fields.address == "https://example.test/proxy/emby" && fields.port == "8920")
        for port in ["0", "65536", "abc", "-1"] {
            do { _ = try EmbyServer.normalize("https://example.test", port: port); fatalError("Invalid port accepted") }
            catch { /* expected */ }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockEmby.self]
        let integration = EmbyAPI(session: URLSession(configuration: configuration))
        let rootServer = EmbyServer(id: server.id, name: "Mock", baseURL: URL(string: "https://example.test")!, userId: "user", username: "test")
        let result = try await integration.playback(rootServer, token: "test-token", item: item)
        precondition(result.playSessionId == "mock-session")
        precondition(integration.url(rootServer, "Videos/video/stream").path == "/Videos/video/stream")
        await integration.report(rootServer, token: "test-token", item: item, source: result.mediaSources[0], session: result.playSessionId, position: 20_000_000, phase: "/Progress")
        precondition(MockEmby.sawProfile && MockEmby.sawProgress && MockEmby.sawFallback)
        print("PlaybackSmoke: PASS (profile negotiation, 404 API fallback, URL resolution and progress request)")
    }
}

// Uses the real EmbyAPI with controlled HTTP responses, without any user credentials.
final class MockEmby: URLProtocol {
    static var sawProfile = false
    static var sawProgress = false
    static var sawFallback = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let path = request.url!.path
        var status = 200
        var response = Data()
        if path.hasPrefix("/emby/") { status = 404 }
        else if path.hasSuffix("PlaybackInfo") {
            Self.sawFallback = true
            Self.sawProfile = (body?["DeviceProfile"] as? [String: Any])?["TranscodingProfiles"] != nil && body?["IsPlayback"] as? Bool == true
            response = Data(#"{"MediaSources":[{"Id":"source","Container":"mp4","SupportsDirectPlay":true,"MediaStreams":[]}],"PlaySessionId":"mock-session"}"#.utf8)
        } else if path == "/Sessions/Playing/Progress" {
            Self.sawProgress = body?["PositionTicks"] as? Int == 20_000_000 && body?["PlaySessionId"] as? String == "mock-session"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
