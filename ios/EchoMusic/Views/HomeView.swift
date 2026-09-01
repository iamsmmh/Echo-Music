import SwiftUI

/// Home tab: vertical stack of horizontal carousels
/// (mirrors `MusicCarouselShelfRenderer` sections).
struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel = HomeViewModel(api: AppEnvironment.shared.api)

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.sections.isEmpty {
                ProgressView()
            } else if let error = viewModel.errorMessage, viewModel.sections.isEmpty {
                ContentUnavailableView(
                    "Couldn't load Home",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(viewModel.sections) { section in
                            HomeSectionView(section: section)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .refreshable {
                    await viewModel.load(force: true)
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlaylistDestination.self) { destination in
            PlaylistView(browseId: destination.browseId)
        }
        .task { await viewModel.load() }
    }
}

// MARK: - Carousel row

struct HomeSectionView: View {
    let section: HomeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(section.items) { item in
                        HomeCard(item: item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Card

struct HomeCard: View {
    @EnvironmentObject private var env: AppEnvironment
    let item: SearchItem

    @ViewBuilder
    var body: some View {
        switch item {
        case .song(let song):
            Button {
                env.player.play([song], startingAt: 0)
            } label: {
                cardContent
            }
            .buttonStyle(.plain)

        case .playlist(let playlist):
            NavigationLink(value: PlaylistDestination(browseId: playlist.browseId)) {
                cardContent
            }
            .buttonStyle(.plain)

        case .album(let album):
            NavigationLink(value: PlaylistDestination(browseId: album.browseId)) {
                cardContent
            }
            .buttonStyle(.plain)

        case .artist(let artist):
            // Artist pages are a later milestone; show as a static card for now.
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(urlString: item.thumbnail, size: 150, cornerRadius: 12)
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppEnvironment.shared)
    }
}
