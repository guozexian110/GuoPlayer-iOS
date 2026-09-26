import Foundation

func item(_ id: String, server: UUID, ids: [String: String], year: Int = 2024) throws -> MediaItem {
    let raw: [String: Any] = ["Id": id, "Name": "同一部电影", "Type": "Movie", "ProductionYear": year, "ProviderIds": ids]
    let decoder = JSONDecoder()
    decoder.userInfo[.serverId] = server
    return try decoder.decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: raw))
}

@main struct AggregationSmoke {
    static func main() throws {
        let a = UUID(), b = UUID()
        let sameA = try item("1", server: a, ids: ["Tmdb": "42", "Imdb": "tt0042"])
        let sameB = try item("2", server: b, ids: ["tmdb": "42"])
        let conflict = try item("3", server: b, ids: ["Tmdb": "43", "Imdb": "tt0042"])
        precondition(MediaAggregation.groups([sameA, sameB]).count == 1)
        precondition(MediaAggregation.groups([sameA, conflict]).count == 2)
        precondition(MediaAggregation.groups([sameA, sameB])[0].variants.count == 2)
        print("AggregationSmoke: PASS")
    }
}
