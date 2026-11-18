import Foundation

/// The last search and library belong to the host application, while each open page keeps its own session.
@MainActor final class EmbeddedSearchPreferences {
    static let application = EmbeddedSearchPreferences(defaults: .standard)

    private static let lastSearchKey = "Everything.embeddedLastSearch"
    private let defaults: UserDefaults
    let library: LibraryStore

    init(defaults: UserDefaults) {
        self.defaults = defaults
        library = LibraryStore(defaults: defaults)
    }

    func restoreSearch() -> SearchState {
        guard let data = defaults.data(forKey: Self.lastSearchKey),
              var search = try? JSONDecoder().decode(SearchState.self, from: data) else {
            return .init(sort: SearchPreferences.initialSort(sceneField: "", sceneAscending: true, defaults: defaults))
        }
        search.sort = SearchPreferences.initialSort(sceneField: search.sort.field, sceneAscending: search.sort.ascending,
                                                    defaults: defaults)
        return search
    }

    func saveSearch(_ search: SearchState) {
        guard let data = try? JSONEncoder().encode(search) else { return }
        defaults.set(data, forKey: Self.lastSearchKey)
    }
}
