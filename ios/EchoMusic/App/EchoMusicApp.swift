import SwiftData
import SwiftUI

@main
struct EchoMusicApp: App {
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .modelContainer(env.database.container)
                .tint(.red) // YouTube Music red
                .preferredColorScheme(.dark)
        }
    }
}
