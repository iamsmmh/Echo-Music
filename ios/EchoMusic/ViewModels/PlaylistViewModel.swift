import Foundation

@MainActor
final class PlaylistViewModel: ObservableObject {

    @Published private(set) var detail: PlaylistDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: InnertubeAPI

    init(api: InnertubeAPI) {
        self.api = api
    }

    /// Fetches the playlist/album page. Re-entry is a no-op while `detail` is already
    /// populated, so the tracks the user is scrolling through don't get refetched.
    func load(browseId: String) async {
        guard detail == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await api.playlist(browseId: browseId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let token = detail?.continuation, let current = detail else { return }
        do {
            let result = try await api.playlistContinuation(token)
            detail = PlaylistDetail(
                browseId: current.browseId,
                playlistId: current.playlistId,
                title: current.title,
                subtitle: current.subtitle,
                thumbnail: current.thumbnail,
                songs: current.songs + result.songs,
                continuation: result.continuation
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts playback of the whole playlist from a row.
    func play(startingAt index: Int) {
        guard let detail else { return }
        AppEnvironment.shared.player.play(
            detail.songs,
            startingAt: index,
            playlistId: detail.playlistId
        )
    }
}
