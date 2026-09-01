import Foundation

/// Minimal client for LRCLIB (https://lrclib.net) — the same synced-lyrics source
/// the Android repo's `lrclib` module uses. YouTube's own lyrics (via the `next`
/// response) are static text; LRCLIB provides timestamped LRC lines.
struct LrcLibClient {

    struct SearchResult: Decodable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    /// Searches by track metadata. Pass the duration to bias toward exact matches.
    func search(
        track: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        var items = [URLQueryItem(name: "track_name", value: track)]
        if let artist { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components.queryItems = items

        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([SearchResult].self, from: data)
    }
}
