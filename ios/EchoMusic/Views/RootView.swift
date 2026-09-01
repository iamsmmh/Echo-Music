import SwiftUI

/// Root layout:
///   TabView (Home / Search / Library)
///     + mini-player pinned to the bottom via `safeAreaInset`
///     + full-screen player presented as a cover
struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedTab = 0
    @State private var isPlayerPresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(1)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if env.player.currentSong != nil {
                MiniPlayerBar {
                    isPlayerPresented = true
                }
            }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerScreen()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment.shared)
}
