import SwiftUI

/// Search tab: debounced query → suggestions + shelf sections.
/// Sections mirror `MusicShelfRenderer` ("Top result", "Songs", "Albums", ...).
struct SearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel: SearchViewModel

    init() {
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            api: AppEnvironment.shared.api,
            database: AppEnvironment.shared.database
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if trimmedQuery.isEmpty {
                recentSearches
            } else {
                resultsList
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlaylistDestination.self) { destination in
            PlaylistView(browseId: destination.browseId)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Songs, albums, artists…", text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: viewModel.query) { _, newValue in
                    viewModel.queryChanged(newValue)
                }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.queryChanged("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Recent searches

    private var recentSearches: some View {
        List {
            Section("Recent searches") {
                ForEach(viewModel.recentQueries, id: \.self) { query in
                    Button {
                        viewModel.query = query
                        viewModel.queryChanged(query)
                    } label: {
                        Label(query, systemImage: "clock")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Results

    private var resultsList: some View {
        List {
            if viewModel.isSearching && viewModel.sections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(viewModel.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            row(for: item, in: section)
                        }
                    }
                }

                if viewModel.sections.last?.continuation != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task { await viewModel.loadMore() }
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func row(for item: SearchItem, in section: SearchSection) -> some View {
        switch item {
        case .song(let song):
            let songs = self.songs(in: section)
            let index = songs.firstIndex(of: song) ?? 0
            SongRowView(song: song) {
                env.player.play(songs, startingAt: index)
            }

        case .playlist(let playlist):
            NavigationLink(value: PlaylistDestination(browseId: playlist.browseId)) {
                SearchResultRow(
                    title: playlist.title,
                    subtitle: playlist.subtitle,
                    thumbnail: playlist.thumbnail
                )
            }

        case .album(let album):
            NavigationLink(value: PlaylistDestination(browseId: album.browseId)) {
                SearchResultRow(
                    title: album.title,
                    subtitle: album.subtitle,
                    thumbnail: album.thumbnail
                )
            }

        case .artist(let artist):
            SearchResultRow(
                title: artist.title,
                subtitle: artist.subtitle,
                thumbnail: artist.thumbnail
            )
        }
    }

    private func songs(in section: SearchSection) -> [Song] {
        section.items.compactMap { item in
            if case .song(let song) = item { return song }
            return nil
        }
    }

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .environmentObject(AppEnvironment.shared)
    }
}
