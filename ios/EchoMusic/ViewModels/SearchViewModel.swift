import Foundation

/// The filter chips shown under the search field (blueprint M8). Maps 1:1 onto
/// `InnertubeAPI.SearchFilter`'s typed params tokens.
enum SearchFilterKind: String, CaseIterable, Identifiable {
    case all, songs, albums, artists, playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        }
    }

    var filter: InnertubeAPI.SearchFilter? {
        switch self {
        case .all: nil
        case .songs: .songs
        case .albums: .albums
        case .artists: .artists
        case .playlists: .playlists
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query = ""
    @Published var sections: [SearchSection] = []
    @Published var suggestions: [String] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var activeFilter: SearchFilterKind = .all

    private let api: InnertubeAPI
    private let database: AppDatabase
    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var lastContinuation: String?

    init(api: InnertubeAPI, database: AppDatabase) {
        self.api = api
        self.database = database
    }

    /// Switches the active filter chip and re-runs the current query immediately
    /// (no debounce — the user already finished typing).
    func setFilter(_ kind: SearchFilterKind) {
        guard kind != activeFilter else { return }
        activeFilter = kind

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        debounceTask?.cancel()
        fetchTask?.cancel()
        sections = []
        suggestions = []
        lastContinuation = nil
        isSearching = true
        fetchTask = Task { [weak self] in
            await self?.fetch(trimmed)
        }
    }

    // MARK: - Input

    /// Call from `.onChange(of: query)`. Debounces, then fetches suggestions + results.
    func queryChanged(_ newValue: String) {
        query = newValue
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        debounceTask?.cancel()
        fetchTask?.cancel()
        guard !trimmed.isEmpty else {
            sections = []
            suggestions = []
            lastContinuation = nil
            isSearching = false
            errorMessage = nil
            return
        }

        isSearching = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000) // 350 ms debounce
            guard !Task.isCancelled else { return }
            await self?.fetch(trimmed)
        }
    }

    // MARK: - Fetching

    private func fetch(_ trimmed: String) async {
        do {
            async let suggestionList = api.searchSuggestions(input: trimmed)
            async let searchSections = api.search(query: trimmed, filter: activeFilter.filter)

            suggestions = try await suggestionList
            let result = try await searchSections

            guard !Task.isCancelled else { return }
            sections = result
            lastContinuation = result.last?.continuation
            try? database.recordSearch(trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    /// Infinite scroll: append the next page of results to the last section.
    func loadMore() async {
        guard let token = lastContinuation else { return }
        lastContinuation = nil
        do {
            let result = try await api.searchContinuation(token)
            guard !result.items.isEmpty else { return }

            if var last = sections.last {
                last = SearchSection(
                    id: last.id,
                    title: last.title,
                    items: last.items + result.items,
                    continuation: result.continuation
                )
                sections[sections.count - 1] = last
            } else {
                sections = [SearchSection(
                    id: "more",
                    title: "More results",
                    items: result.items,
                    continuation: result.continuation
                )]
            }
            lastContinuation = result.continuation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - History

    var recentQueries: [String] {
        (try? database.recentSearches()) ?? []
    }
}
