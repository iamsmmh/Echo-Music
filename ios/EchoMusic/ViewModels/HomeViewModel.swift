import Foundation

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var sections: [HomeSection] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: InnertubeAPI

    init(api: InnertubeAPI) {
        self.api = api
    }

    func load(force: Bool = false) async {
        guard force || sections.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            sections = try await api.home()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
