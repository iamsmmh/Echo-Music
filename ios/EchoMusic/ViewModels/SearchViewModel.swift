import Foundation

@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query = ""
    @Published var sections: [SearchSection] = []
    @Published var suggestions: [String] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    private let api: InnertubeAPI
    private let database: AppDatabase
    private var debounceTask: Task<Void, Never>?
    private var lastContinuation: String?

    init(api: InnertubeAPI, database: AppDatabase) {
        self.api = api
        self.database = database
    }

    // MARK: - Input

    /// Call from `.onChange(of: query)`. Debounces, then fetches suggestions + results.
    func queryChanged(_ newValue: String) {
        query = newValue
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        debounceTask?.cancel()
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
            async let searchSections = api.search(query: trimmed)

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
