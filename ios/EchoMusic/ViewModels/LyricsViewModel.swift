import Foundation

/// Backs the lyrics sheet. Fetches two sources in parallel and prefers the better one:
///
///  1. **Synced LRC** from LRCLIB (`LrcLibClient`) — timestamped lines that scroll
///     with playback.
///  2. **Static lyrics** from YouTube itself via the `next` response's lyrics tab
///     (`browse` on the tab's `BrowseEndpoint`).
@MainActor
final class LyricsViewModel: ObservableObject {

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var staticLyrics: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: InnertubeAPI
    private let lrcClient = LrcLibClient()
    private var loadedSongID: String?

    init(api: InnertubeAPI) {
        self.api = api
    }

    func load(song: Song?, endpoint: BrowseEndpoint?) async {
        guard let song, loadedSongID != song.id else { return }
        loadedSongID = song.id
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let lrcResults = lrcClient.search(
            track: song.title,
            artist: song.artistNames,
            duration: song.duration
        )

        var staticText: String?
        if let endpoint {
            staticText = try? await api.lyrics(endpoint: endpoint)
        }

        // Prefer the longest synced result — LRCLIB can return several variants.
        let synced = (try? await lrcResults)?
            .compactMap { $0.syncedLyrics }
            .compactMap { LrcParser.parse($0) }
            .max { $0.count < $1.count }

        if let synced, !synced.isEmpty {
            lines = synced
            staticLyrics = nil
        } else if let staticText, !staticText.isEmpty {
            staticLyrics = staticText
            lines = []
        } else {
            errorMessage = "No lyrics found for this track."
        }
    }

    /// Forces a fresh fetch (pull-to-refresh / track change).
    func reload(song: Song?, endpoint: BrowseEndpoint?) async {
        loadedSongID = nil
        await load(song: song, endpoint: endpoint)
    }
}
