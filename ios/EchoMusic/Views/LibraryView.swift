import SwiftUI

/// Library tab: favorites (persisted with SwiftData) and offline downloads.
struct LibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var favorites: [FavoriteSong] = []
    @State private var downloads: [OfflineTrack] = []

    var body: some View {
        Group {
            if favorites.isEmpty && downloads.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "music.note.list",
                    description: Text("Heart tracks to save them here, or download them for offline listening.")
                )
            } else {
                List {
                    if !favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(favorites, id: \.videoId) { favorite in
                                favoriteRow(favorite)
                            }
                        }
                    }

                    if !downloads.isEmpty {
                        Section("Downloads") {
                            ForEach(downloads, id: \.videoId) { track in
                                downloadRow(track)
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
        .onReceive(env.offline.objectWillChange) { reload() }
    }

    // MARK: - Favorites

    private func favoriteRow(_ favorite: FavoriteSong) -> some View {
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

    // MARK: - Downloads

    private func downloadRow(_ track: OfflineTrack) -> some View {
        Button {
            play(track)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(urlString: track.thumbnailURL, size: 48, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                removeDownload(track)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func play(_ favorite: FavoriteSong) {
        env.player.play([song(from: favorite)], startingAt: 0)
    }

    private func play(_ track: OfflineTrack) {
        env.player.play([song(from: track)], startingAt: 0)
    }

    private func remove(_ favorite: FavoriteSong) {
        env.database.container.mainContext.delete(favorite)
        try? env.database.container.mainContext.save()
        reload()
    }

    private func removeDownload(_ track: OfflineTrack) {
        env.offline.delete(track)
        reload()
    }

    private func reload() {
        favorites = (try? env.database.favoriteSongs()) ?? []
        downloads = (try? env.database.offlineTracks()) ?? []
    }

    // MARK: - Mapping

    private func song(from favorite: FavoriteSong) -> Song {
        Song(
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
    }

    private func song(from track: OfflineTrack) -> Song {
        Song(
            id: track.videoId,
            title: track.title,
            artists: [Artist(id: nil, name: track.artistNames)],
            album: nil,
            duration: track.duration,
            thumbnail: track.thumbnailURL,
            explicit: false,
            videoType: nil,
            watchEndpoint: nil
        )
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(AppEnvironment.shared)
    }
}
