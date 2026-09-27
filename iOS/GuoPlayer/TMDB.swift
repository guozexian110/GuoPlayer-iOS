import Foundation
import Security

struct TMDBTitle: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let name: String?
    let mediaType: String?
    let backdropPath: String?
    let posterPath: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case mediaType = "media_type", backdropPath = "backdrop_path", posterPath = "poster_path"
        case releaseDate = "release_date", firstAirDate = "first_air_date"
        case voteAverage = "vote_average", genreIds = "genre_ids"
    }
    var displayTitle: String { title ?? name ?? "未命名" }
    var year: String { String((releaseDate ?? firstAirDate ?? "").prefix(4)) }
    var kind: String { mediaType ?? (title == nil ? "tv" : "movie") }
    var imageURL: URL? { image(posterPath, size: "w500") }
    var backdropURL: URL? { image(backdropPath ?? posterPath, size: "w1280") }
    private func image(_ path: String?, size: String) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

private struct TMDBResponse: Decodable { let results: [TMDBTitle] }

enum TMDBCredential {
    private static let account = "tmdb-api"
    private static let service = "com.guoplayer.tmdb"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbyError.message("请输入 TMDb API 凭据") }
        delete()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecValueData as String: Data(trimmed.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw EmbyError.message("TMDb 凭据保存失败") }
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

struct TMDBClient {
    var session: URLSession = .shared

    func list(_ path: String, credential: String, parameters: [URLQueryItem] = []) async throws -> [TMDBTitle] {
        guard path.hasPrefix("/") && !path.contains(".."),
              var components = URLComponents(string: "https://api.themoviedb.org/3\(path)") else {
            throw EmbyError.message("TMDb 请求无效")
        }
        var query = [URLQueryItem(name: "language", value: "zh-CN"), URLQueryItem(name: "page", value: "1")]
        query += parameters
        if !credential.contains(".") { query.append(URLQueryItem(name: "api_key", value: credential)) }
        components.queryItems = query
        guard let url = components.url else { throw EmbyError.message("TMDb 地址无效") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if credential.contains(".") { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw EmbyError.message("TMDb 请求失败，请检查网络与 API 凭据")
        }
        return try JSONDecoder().decode(TMDBResponse.self, from: data).results.filter { $0.imageURL != nil }
    }
}
