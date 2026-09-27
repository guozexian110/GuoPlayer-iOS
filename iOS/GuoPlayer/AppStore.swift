import Foundation
import Combine
import Security

enum TokenVault {
    static func save(_ token: String, id: UUID) throws {
        let key = id.uuidString
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.guoplayer.emby", kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw EmbyError.message("无法安全保存登录令牌") }
    }
    static func read(_ id: UUID) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.guoplayer.emby", kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ id: UUID) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.guoplayer.emby", kSecAttrAccount as String: id.uuidString] as CFDictionary)
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var servers: [EmbyServer] = []
    @Published var items: [MediaItem] = []
    @Published var continueWatching: [MediaItem] = []
    @Published var libraries: [UUID: [MediaItem]] = [:]
    @Published var searchResults: [MediaItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var tmdbLists: [String: [TMDBTitle]] = [:]
    @Published var tmdbError: String?
    @Published var tmdbLoading = false
    @Published var hasTMDBCredential = TMDBCredential.read() != nil
    let api = EmbyAPI()
    private var offsets: [UUID: Int] = [:]
    private let key = "GuoPlayerServersV1"
    var groups: [MediaGroup] { MediaAggregation.groups(items) }
    var resumeGroups: [MediaGroup] { MediaAggregation.groups(continueWatching, includeEpisodes: true) }
    var searchGroups: [MediaGroup] { MediaAggregation.groups(searchResults) }

    func saveTMDBCredential(_ value: String) async throws {
        try TMDBCredential.save(value)
        hasTMDBCredential = true
        await refreshTMDB()
    }
    func deleteTMDBCredential() {
        TMDBCredential.delete()
        hasTMDBCredential = false
        tmdbLists = [:]
        tmdbError = nil
    }
    func refreshTMDB() async {
        guard !tmdbLoading, let credential = TMDBCredential.read() else { return }
        tmdbLoading = true
        tmdbError = nil
        let requests: [(String, String, [URLQueryItem])] = [
            ("day", "/trending/all/day", []), ("week", "/trending/all/week", []),
            ("now", "/movie/now_playing", [URLQueryItem(name: "region", value: "CN")]),
            ("anime", "/tv/airing_today", [URLQueryItem(name: "timezone", value: "Asia/Shanghai")]),
            ("movie", "/movie/popular", []), ("tv", "/tv/popular", []),
            ("topMovie", "/movie/top_rated", []), ("topTV", "/tv/top_rated", []),
            ("family", "/discover/movie", [URLQueryItem(name: "with_genres", value: "10751"), URLQueryItem(name: "sort_by", value: "popularity.desc")]),
            ("animation", "/discover/movie", [URLQueryItem(name: "with_genres", value: "16"), URLQueryItem(name: "sort_by", value: "popularity.desc")]),
            ("netflix", "/discover/movie", [URLQueryItem(name: "with_watch_providers", value: "8"), URLQueryItem(name: "watch_region", value: "US")]),
            ("disney", "/discover/movie", [URLQueryItem(name: "with_watch_providers", value: "337"), URLQueryItem(name: "watch_region", value: "US")]),
            ("apple", "/discover/movie", [URLQueryItem(name: "with_watch_providers", value: "350"), URLQueryItem(name: "watch_region", value: "US")]),
            ("universal", "/discover/movie", [URLQueryItem(name: "with_companies", value: "33")]),
            ("paramount", "/discover/movie", [URLQueryItem(name: "with_companies", value: "4")]),
            ("columbia", "/discover/movie", [URLQueryItem(name: "with_companies", value: "5")]),
            ("marvel", "/discover/movie", [URLQueryItem(name: "with_companies", value: "420")])
        ]
        let results = await withTaskGroup(of: (String, [TMDBTitle]?, String?).self) { group in
            for (key, path, parameters) in requests {
                group.addTask {
                    do { return (key, try await TMDBClient().list(path, credential: credential, parameters: parameters), nil) }
                    catch { return (key, nil, error.localizedDescription) }
                }
            }
            var output: [(String, [TMDBTitle]?, String?)] = []
            for await result in group { output.append(result) }
            return output
        }
        for (key, titles, _) in results {
            if let titles { tmdbLists[key] = key == "anime" ? titles.filter { $0.genreIds?.contains(16) == true } : titles }
        }
        if let failure = results.first(where: { $0.2 != nil })?.2 { tmdbError = failure }
        tmdbLoading = false
    }
    func embyGroup(for title: TMDBTitle) -> MediaGroup? {
        groups.first { group in
            guard group.primary.type == (title.kind == "movie" ? "Movie" : "Series") else { return false }
            return group.variants.contains { item in
                item.providerIds.first { $0.key.caseInsensitiveCompare("Tmdb") == .orderedSame }?.value == String(title.id)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode([EmbyServer].self, from: data) { servers = stored }
        if let cache = try? Data(contentsOf: cacheURL), let stored = try? JSONDecoder().decode([CachedItem].self, from: cache) {
            items = stored.compactMap { $0.decode() }
        }
    }
    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("guoplayer-media.json") }
    private func persist() { if let data = try? JSONEncoder().encode(servers) { UserDefaults.standard.set(data, forKey: key) } }

    func addServer(name: String, address: String, username: String, password: String) async throws {
        let base = try EmbyServer.normalize(address)
        let auth = try await api.login(base: base, username: username, password: password)
        let id = UUID()
        try TokenVault.save(auth.token, id: id)
        servers.append(EmbyServer(id: id, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? auth.serverName : name, baseURL: base, userId: auth.userId, username: username))
        persist()
        await refresh()
    }
    func remove(_ server: EmbyServer) {
        TokenVault.delete(server.id)
        servers.removeAll { $0.id == server.id }
        items.removeAll { $0.serverId == server.id }
        continueWatching.removeAll { $0.serverId == server.id }
        libraries.removeValue(forKey: server.id)
        persist(); saveCache()
    }
    func rename(_ server: EmbyServer, to name: String) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].name = name
        persist()
    }
    func updateServer(_ server: EmbyServer, name: String, address: String, username: String, password: String) async throws {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { throw EmbyError.message("服务器已删除") }
        let base = try EmbyServer.normalize(address)
        var updated = server
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? server.name : name
        if base != server.baseURL || username != server.username || !password.isEmpty {
            guard !password.isEmpty else { throw EmbyError.message("更改地址或用户名时需要重新输入密码") }
            let auth = try await api.login(base: base, username: username, password: password)
            try TokenVault.save(auth.token, id: server.id)
            updated.baseURL = base; updated.username = username; updated.userId = auth.userId
            items.removeAll { $0.serverId == server.id }
        }
        servers[index] = updated
        persist()
        await refresh()
    }
    func refresh() async {
        guard !servers.isEmpty else { return }
        isLoading = true; error = nil
        var fetched: [MediaItem] = []
        var resumed: [MediaItem] = []
        for server in servers {
            guard let token = TokenVault.read(server.id) else { error = "\(server.name)：登录令牌丢失，请重新添加"; continue }
            do {
                var page = try await api.items(server, token: token)
                offsets[server.id] = page.count
                if page.isEmpty {
                    let views = try await api.views(server, token: token)
                    libraries[server.id] = views
                    for view in views.prefix(10) { page += (try? await api.items(server, token: token, parentId: view.id, limit: 50)) ?? [] }
                } else {
                    libraries[server.id] = (try? await api.views(server, token: token)) ?? []
                }
                fetched += page
                resumed += (try? await api.resume(server, token: token)) ?? []
            } catch { self.error = "\(server.name)：\(error.localizedDescription)" }
        }
        let updated = Set(fetched.map { "\($0.serverId):\($0.id)" })
        items = fetched + items.filter { item in !updated.contains("\(item.serverId):\(item.id)") && servers.contains(where: { $0.id == item.serverId }) }
        continueWatching = resumed
        saveCache()
        isLoading = false
    }
    func search(_ term: String) async {
        guard !term.isEmpty else { searchResults = []; return }
        var found: [MediaItem] = []
        for server in servers {
            guard let token = TokenVault.read(server.id) else { continue }
            found += (try? await api.items(server, token: token, search: term, limit: 80)) ?? []
        }
        searchResults = found
    }
    func loadMore(serverId: UUID?) async -> Int {
        var added = 0
        for server in servers where serverId == nil || server.id == serverId {
            guard let token = TokenVault.read(server.id) else { continue }
            let start = offsets[server.id] ?? 0
            guard let page = try? await api.items(server, token: token, limit: 200, start: start), !page.isEmpty else { continue }
            offsets[server.id] = start + page.count
            let known = Set(items.map { "\($0.serverId):\($0.id)" })
            let unique = page.filter { !known.contains("\($0.serverId):\($0.id)") }
            items += unique; added += unique.count
        }
        saveCache()
        return added
    }
    func server(for item: MediaItem) -> EmbyServer? { servers.first { $0.id == item.serverId } }
    func poster(_ item: MediaItem, backdrop: Bool = false) -> URL? {
        guard let server = server(for: item), let token = TokenVault.read(server.id) else { return nil }
        return api.imageURL(server, token: token, item: item, backdrop: backdrop)
    }
    func toggleFavorite(_ item: MediaItem) async {
        guard let server = server(for: item), let token = TokenVault.read(server.id) else { return }
        do { try await api.favorite(server, token: token, item: item, enable: item.userData?.isFavorite != true); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func saveCache() {
        let encoded = items.prefix(1000).compactMap { CachedItem($0) }
        if let data = try? JSONEncoder().encode(encoded) { try? data.write(to: cacheURL, options: .atomic) }
    }
}

// Stores the original Emby JSON fields plus the owning server ID. Tokens are never cached here.
private struct CachedItem: Codable {
    let serverId: UUID
    let json: Data
    init?(_ item: MediaItem) {
        serverId = item.serverId
        var fields: [String: Any] = ["Id": item.id, "Name": item.name, "Type": item.type, "ProviderIds": item.providerIds, "ImageTags": item.imageTags, "BackdropImageTags": item.backdropImageTags]
        if let year = item.year { fields["ProductionYear"] = year }
        if let overview = item.overview { fields["Overview"] = overview }
        guard let data = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        json = data
    }
    func decode() -> MediaItem? {
        let decoder = JSONDecoder(); decoder.userInfo[.serverId] = serverId
        return try? decoder.decode(MediaItem.self, from: json)
    }
}
