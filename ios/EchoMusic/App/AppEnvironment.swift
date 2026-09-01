import SwiftUI

/// Simple dependency container. Every layer (networking → API → playback → storage)
/// is created here once and shared app-wide through `@EnvironmentObject`.
@MainActor
final class AppEnvironment: ObservableObject {

    static let shared = AppEnvironment()

    let client: InnertubeClient
    let api: InnertubeAPI
    let player: PlaybackManager
    let database: AppDatabase
    let offline: OfflineManager

    init() {
        // Shared URL cache (20 MB memory / 200 MB disk). `AsyncImage` and
        // `URLSession.shared` pick this up, so thumbnail/artwork URLs hit the
        // disk cache on subsequent loads (blueprint M9 — thumbnail caching).
        URLCache.shared = URLCache(memoryCapacity: 20_000_000, diskCapacity: 200_000_000)

        let client = InnertubeClient()
        let api = InnertubeAPI(client: client)
        let database = try! AppDatabase()
        let offline = OfflineManager(api: api, database: database)
        let player = PlaybackManager(api: api, audioSession: .shared, offline: offline)
        self.client = client
        self.api = api
        self.database = database
        self.offline = offline
        self.player = player
    }
}
