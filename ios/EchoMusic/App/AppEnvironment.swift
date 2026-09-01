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

    init() {
        let client = InnertubeClient()
        let api = InnertubeAPI(client: client)
        let database = try! AppDatabase()
        let player = PlaybackManager(api: api, audioSession: .shared)
        self.client = client
        self.api = api
        self.database = database
        self.player = player
    }
}
