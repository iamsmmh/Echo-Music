import SwiftUI

/// Playlist / album page: header + track list. Data comes from the `browse` endpoint.
struct PlaylistView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel: PlaylistViewModel
    @State private var favoriteIDs: Set<String> = []

    init(browseId: String) {
        _viewModel = StateObject(wrappedValue: PlaylistViewModel(
            browseId: browseId,
            api: AppEnvironment.shared.api
        ))
    }

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                trackList(detail)
            } else if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't load playlist",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.detail?.title ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
            favoriteIDs = Set((try? env.database.favoriteSongs())?.map(\.videoId) ?? [])
        }
    }

    private func trackList(_ detail: PlaylistDetail) -> some View {
        List {
            PlaylistHeader(detail: detail) {
                env.player.play(detail.songs, startingAt: 0, playlistId: detail.playlistId)
            }

            ForEach(Array(detail.songs.enumerated()), id: \.element.id) { index, song in
                SongRowView(
                    song: song,
                    onTap: {
                        env.player.play(detail.songs, startingAt: index, playlistId: detail.playlistId)
                    },
                    offline: env.offline,
                    isFavorite: favoriteIDs.contains(song.id),
                    onToggleFavorite: { toggleFavorite($0) }
                )
            }

            if detail.continuation != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await viewModel.loadMore() }
                    }
            }
        }
        .listStyle(.plain)
    }

    private func toggleFavorite(_ song: Song) {
        try? env.database.toggleFavorite(song)
        if favoriteIDs.contains(song.id) {
            favoriteIDs.remove(song.id)
        } else {
            favoriteIDs.insert(song.id)
        }
    }
}

// MARK: - Playlist header

struct PlaylistHeader: View {
    let detail: PlaylistDetail
    var onPlay: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ArtworkView(urlString: detail.thumbnail, size: 200, cornerRadius: 16)

            VStack(spacing: 6) {
                Text(detail.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let subtitle = detail.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
        }
        .padding(.vertical, 16)
    }
}

#Preview {
    NavigationStack {
        PlaylistView(browseId: "PL4fGSI1pDJnDkCzJxISLdQl8RkKkN9ZzZ")
            .environmentObject(AppEnvironment.shared)
    }
}
