import Foundation
import Combine

@MainActor public final class SearchModel: ObservableObject {
    public typealias Loader = @MainActor (String, SearchSort, Int) async throws -> SearchPage
    @Published public var query = "" { didSet { if !changingSearch { restart() } } }
    @Published public private(set) var scope = SearchScope()
    @Published public private(set) var rows: [SearchResult] = []
    @Published public private(set) var total = 0
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?
    @Published public private(set) var sort = SearchSort()
    private let loader: Loader
    private let delay: UInt64
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var nextOffset = 0
    private var currentOffset: Int?
    private var suspended = false
    private var deletedInCurrentSearch: [SearchResult] = []
    private var changingSearch = false
    public var hasMore: Bool { nextOffset < total }
    public init(delay: UInt64 = 200_000_000, loader: @escaping Loader) { self.loader = loader; self.delay = delay }
    public func restart() {
        restart(keepingRows: false)
    }
    public func setSearch(query: String, sort: SearchSort, scope: SearchScope) {
        changingSearch = true
        self.query = query; self.sort = sort; self.scope = scope
        changingSearch = false
        restart()
    }
    private func restart(keepingRows: Bool) {
        task?.cancel()
        generation = UUID()
        if !keepingRows { rows = []; total = 0 }
        nextOffset = 0; error = nil; deletedInCurrentSearch = []
        fetch(offset: 0, debounce: true)
    }
    public func setSort(_ value: SearchSort) {
        guard sort != value else { return }
        sort = value; restart(keepingRows: true)
    }
    /// Preserve the rows and retry only the interrupted request when its page is shown again.
    package func suspend() {
        suspended = true
        generation = UUID()
        task?.cancel()
        task = nil
        if busy { busy = false }
    }

    package func resume() {
        guard suspended else { return }
        suspended = false
        if let currentOffset { fetch(offset: currentOffset, debounce: false) }
    }

    public func loadMore() {
        guard !suspended, !busy, hasMore else { return }
        error = nil
        fetch(offset: nextOffset, debounce: false)
    }
    public func removeDeleted(_ results: [SearchResult]) {
        deletedInCurrentSearch += results
        rows.removeAll(where: isDeleted)
    }
    private func isDeleted(_ row: SearchResult) -> Bool {
        let path = row.windowsPath.replacingOccurrences(of: "/", with: "\\").lowercased()
        return deletedInCurrentSearch.contains { deleted in
            let root = deleted.windowsPath.replacingOccurrences(of: "/", with: "\\").lowercased()
            return path == root || (deleted.type == "folder" && path.hasPrefix(root + "\\"))
        }
    }
    private func fetch(offset: Int, debounce: Bool) {
        currentOffset = offset
        guard !suspended else { return }
        let token = generation, query = scope.expression(for: query), sort = sort
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if debounce { try await Task.sleep(nanoseconds: self.delay) }
                try Task.checkCancellation()
                let page = try await self.loader(query, sort, offset)
                guard self.generation == token, !Task.isCancelled else { return }
                if offset == 0 { self.rows = page.results.filter { !self.isDeleted($0) } }
                else {
                    var ids = Set(self.rows.map(\.id))
                    self.rows += page.results.filter { !self.isDeleted($0) && ids.insert($0.id).inserted }
                }
                self.total = max(0, page.totalResults)
                self.nextOffset = page.results.isEmpty ? self.total : offset + page.results.count
                self.currentOffset = nil
                self.busy = false
            } catch {
                guard self.generation == token else { return }
                self.currentOffset = nil
                self.busy = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}
