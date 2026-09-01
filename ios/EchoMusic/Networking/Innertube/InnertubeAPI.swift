import Foundation

/// Typed, domain-level access to YouTube Music's InnerTube endpoints.
/// Wraps `InnertubeClient` (transport) + `MediaParser` (renderer → domain models).
///
/// Endpoint → JSON-path cheat sheet (all verified against the Android repo):
///   search  → contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content
///             .sectionListRenderer.contents[].musicShelfRenderer
///   browse  → contents.{single|two}ColumnBrowseResultsRenderer.tabs[0].tabRenderer
///             .content.sectionListRenderer.contents[].musicPlaylistShelfRenderer
///   player  → streamingData.adaptiveFormats[] / playabilityStatus / playbackTracking
///   next    → contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer
///             .watchNextTabbedResultsRenderer.tabs[0].tabRenderer.content
///             .musicQueueRenderer.content.playlistPanelRenderer
final class InnertubeAPI {

    enum SearchFilter {
        case songs, videos, albums, artists, playlists

        var params: String {
            switch self {
            case .songs: "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
            case .videos: "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
            case .albums: "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
            case .artists: "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
            case .playlists: "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"
            }
        }
    }

    let client: InnertubeClient

    init(client: InnertubeClient) {
        self.client = client
    }

    // MARK: - Search

    func search(query: String, filter: SearchFilter? = nil) async throws -> [SearchSection] {
        try await client.ensureVisitorData()
        let body = SearchBody(
            context: client.context(profile: .webRemix),
            query: query,
            params: filter?.params
        )
        let response: SearchResponse = try await client.post("search", profile: .webRemix, body: body)
        return MediaParser.searchSections(from: response)
    }

    func searchContinuation(_ token: String) async throws -> (items: [SearchItem], continuation: String?) {
        let body = SearchBody(context: client.context(profile: .webRemix), query: nil, params: nil)
        let response: SearchResponse = try await client.post(
            "search",
            profile: .webRemix,
            body: body,
            query: [
                URLQueryItem(name: "continuation", value: token),
                URLQueryItem(name: "ctoken", value: token)
            ]
        )
        return MediaParser.searchContinuation(from: response)
    }

    func searchSuggestions(input: String) async throws -> [String] {
        try await client.ensureVisitorData()
        let body = SuggestionsBody(context: client.context(profile: .webRemix), input: input)
        let response: SuggestionsResponse = try await client.post(
            "music/get_search_suggestions",
            profile: .webRemix,
            body: body
        )
        return MediaParser.suggestions(from: response)
    }

    // MARK: - Browse (home / playlists / albums)

    func home() async throws -> [HomeSection] {
        let response: BrowseResponse = try await browse(browseId: "FEmusic_home")
        return MediaParser.homeSections(from: response)
    }

    func playlist(browseId: String) async throws -> PlaylistDetail {
        let response: BrowseResponse = try await browse(browseId: browseId)
        guard let detail = MediaParser.playlistDetail(from: response, browseId: browseId) else {
            throw InnertubeError.parsing("playlist")
        }
        return detail
    }

    func playlistContinuation(_ token: String) async throws -> (songs: [Song], continuation: String?) {
        let body = BrowseBody(
            context: client.context(profile: .webRemix),
            browseId: nil,
            params: nil,
            continuation: token
        )
        let response: BrowseResponse = try await client.post("browse", profile: .webRemix, body: body)
        return MediaParser.playlistContinuation(from: response)
    }

    private func browse(browseId: String, params: String? = nil) async throws -> BrowseResponse {
        try await client.ensureVisitorData()
        let body = BrowseBody(
            context: client.context(profile: .webRemix),
            browseId: browseId,
            params: params,
            continuation: nil
        )
        return try await client.post("browse", profile: .webRemix, body: body)
    }

    // MARK: - Player (stream resolution)

    /// Fetches a playable `player` response. Tries the direct-URL clients first
    /// (VISIONOS → IOS → ANDROID_VR) and only returns a response that is playable and
    /// contains audio formats.
    func player(videoId: String, playlistId: String? = nil) async throws -> PlayerResponse {
        try await client.ensureVisitorData()

        let profiles: [InnertubeClientProfile] = [.visionOS, .ios, .androidVR16510]
        var lastError: Error?

        for profile in profiles {
            do {
                let body = PlayerBody(
                    context: client.context(profile: profile),
                    videoId: videoId,
                    playlistId: playlistId,
                    playbackContext: nil,
                    contentCheckOk: true,
                    racyCheckOk: true
                )
                let response: PlayerResponse = try await client.post("player", profile: profile, body: body)
                if response.isPlayable,
                   let formats = response.streamingData?.adaptiveFormats,
                   !formats.isEmpty {
                    return response
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? InnertubeError.playbackUnavailable(nil)
    }

    // MARK: - Queue (`next`)

    func queue(
        videoId: String?,
        playlistId: String?,
        playlistSetVideoId: String?,
        index: Int?,
        params: String?,
        continuation: String? = nil
    ) async throws -> QueueResult {
        try await client.ensureVisitorData()
        let body = NextBody(
            context: client.context(profile: .webRemix),
            videoId: videoId,
            playlistId: playlistId,
            playlistSetVideoId: playlistSetVideoId,
            index: index,
            params: params,
            continuation: continuation
        )
        let response: NextResponse = try await client.post("next", profile: .webRemix, body: body)
        return MediaParser.queueResult(from: response)
    }

    // MARK: - Lyrics (YouTube's own static lyrics)

    func lyrics(endpoint: BrowseEndpoint) async throws -> String {
        let response: BrowseResponse = try await browse(browseId: endpoint.browseId, params: endpoint.params)
        guard let text = MediaParser.lyrics(from: response) else {
            throw InnertubeError.parsing("lyrics")
        }
        return text
    }

    // MARK: - Playback registration

    func registerPlayback(baseURL: String, playlistId: String?) async throws {
        try await client.registerPlayback(baseURL: baseURL, playlistId: playlistId)
    }
}
