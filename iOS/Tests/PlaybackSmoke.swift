import Foundation

@main struct PlaybackSmoke {
    static func main() throws {
        let server = EmbyServer(id: UUID(), name: "Test", baseURL: URL(string: "https://example.test/emby")!, userId: "user", username: "test")
        let decoder = JSONDecoder()
        decoder.userInfo[.serverId] = server.id
        let item = try decoder.decode(MediaItem.self, from: Data(#"{"Id":"video","Name":"Test","Type":"Movie"}"#.utf8))
        let source = try decoder.decode(PlaybackSource.self, from: Data(#"{"Id":"source","Container":"mkv","SupportsDirectPlay":true,"SupportsDirectStream":false,"TranscodingUrl":"/emby/Videos/video/master.m3u8?MediaSourceId=source","MediaStreams":[{"Index":0,"Type":"Video","Codec":"hevc","Height":2160},{"Index":1,"Type":"Audio","Codec":"dts"}]}"#.utf8))
        precondition(!source.canDirectPlayOnApple)
        let api = EmbyAPI()
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
        print("PlaybackSmoke: PASS")
    }
}
