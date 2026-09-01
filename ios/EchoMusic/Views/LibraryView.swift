import SwiftUI

/// Library tab: favorites (persisted with SwiftData). User playlists and offline
/// tracks slot in here in later milestones.
struct LibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var favorites: [FavoriteSong] = []

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "heart",
                    description: Text("Tap the heart on a track to save it here.")
                )
            } else {
                List {
                    ForEach(favorites, id: \.videoId) { favorite in
                        Button {
                            play(favorite)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(urlString: favorite.thumbnailURL, size: 48, cornerRadius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favorite.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(favorite.artistNames)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                remove(favorite)
                            } label: {
                                Label("Remove", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    private func play(_ favorite: FavoriteSong) {
        let song = Song(
            id: favorite.videoId,
            title: favorite.title,
            artists: [Artist(id: nil, name: favorite.artistNames)],
            album: favorite.albumName.isEmpty ? nil : Album(id: nil, name: favorite.albumName),
            duration: favorite.duration,
            thumbnail: favorite.thumbnailURL,
            explicit: false,
            videoType: nil,
            watchEndpoint: nil
        )
        env.player.play([song], startingAt: 0)
    }

    private func remove(_ favorite: FavoriteSong) {
        env.database.container.mainContext.delete(favorite)
        try? env.database.container.mainContext.save()
        reload()
    }

    private func reload() {
        favorites = (try? env.database.favoriteSongs()) ?? []
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(AppEnvironment.shared)
    }
}
