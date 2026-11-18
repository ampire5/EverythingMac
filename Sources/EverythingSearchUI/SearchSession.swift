import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine
import EverythingCore

@MainActor package final class SearchSession: ObservableObject {
    package let id: UUID
    package let model: SearchModel
    let actions = FileActions()
    package let deletion = FileDeletionController()
    package let preview = PreviewController()
    private let mappingProvider: @MainActor () -> [PathMapping]
    let standalone: Bool
    var embeddedPreferences: EmbeddedSearchPreferences?
    private var suspended = false
    var mappings: [PathMapping] { mappingProvider() }
    package let library: LibraryStore
    @Published package var selected: [SearchResult] = []
    @Published var savingQuery = false
    @Published var bookmarkName = ""
    @Published package var history = SearchHistory()
    @Published var tableRestoration: TableRestoration?
    private var tableLocation = TableLocation()
    private var pendingLocation: TableLocation?
    private var completionObserver: AnyCancellable?
    private var recordTask: Task<Void, Never>?
    private var revision = UUID()
    private var initialized = false
    var state: SearchState { .init(query: model.query, sort: model.sort, scope: model.scope) }
    package weak var window: NSWindow?
    package init(id: UUID, library: LibraryStore, standalone: Bool = true, model: SearchModel,
                 mappings: @escaping @MainActor () -> [PathMapping]) {
        self.id = id
        self.library = library
        self.standalone = standalone
        self.model = model
        self.mappingProvider = mappings
        completionObserver = self.model.$busy.dropFirst().filter { !$0 }.sink { [weak self] _ in
            guard let self else { return }
            let revision = self.revision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == revision, !self.model.busy, !self.suspended else { return }
                self.searchFinished()
            }
        }
        deletion.onRemoved = { [weak self] results in
            guard let self else { return }
            self.model.removeDeleted(results)
            let remaining = Set(self.model.rows.map(\.id))
            self.selected.removeAll { !remaining.contains($0.id) }
        }
    }
    func setActive(_ active: Bool) {
        suspended = !active
        if active {
            model.resume()
        } else {
            recordTask?.cancel()
            actions.cancel()
            actions.pending = nil
            model.suspend()
        }
    }

    package func focusSearch() { NotificationCenter.default.post(name: .focusSearch, object: id) }
    func startEmbedded() {
        setActive(true)
        guard !initialized, let embeddedPreferences else { return }
        start(embeddedPreferences.restoreSearch())
    }

    func start(_ initial: SearchState) {
        guard !initialized else { return }
        initialized = true
        history = SearchHistory(initial: initial)
        load(initial, remember: false)
        focusSearch()
    }
    func editQuery(_ query: String) {
        guard model.query != query else { return }
        captureLocation()
        invalidateRestoration()
        var next = state; next.query = query
        history.edit(next)
        tableLocation = .init()
        selected = []
        model.query = query
        embeddedPreferences?.saveSearch(next)
    }
    func commitQuery() { captureLocation(); history.commit() }
    package func receiveSelectedText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        initialized = true
        transition(.init(query: text, sort: model.sort))
        focusSearch()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isKeyWindow == true, self.window?.attachedSheet == nil else { return }
            self.focusSearch()
        }
    }
    func setScope(_ scope: SearchScope) {
        guard scope != model.scope else { return }
        var next = state; next.scope = scope
        transition(next)
        focusSearch()
    }
    func searchInFolder(_ result: SearchResult) {
        var scope = model.scope; scope.folder = SearchScope.folder(containing: result)
        setScope(scope)
    }
    package func goBack() {
        captureLocation()
        guard let entry = history.back() else { return }
        load(entry.state, location: entry.location)
    }
    package func goForward() {
        captureLocation()
        guard let entry = history.forward() else { return }
        load(entry.state, location: entry.location)
    }
    func updateLocation(_ location: TableLocation, for state: SearchState) {
        guard self.state == state, !model.busy, pendingLocation == nil else { return }
        tableLocation = location
    }
    private func captureLocation() {
        guard pendingLocation == nil else { return }
        var location = tableLocation
        location.selectedIDs = Set(selected.map(\.id)); location.loadedCount = model.rows.count
        history.updateLocation(location)
    }
    private func invalidateRestoration() {
        revision = UUID(); recordTask?.cancel()
        pendingLocation = nil; tableRestoration = nil
    }
    private func transition(_ state: SearchState) {
        captureLocation(); history.transition(to: state); load(state)
    }
    private func load(_ state: SearchState, location: TableLocation? = nil, remember: Bool = true) {
        invalidateRestoration()
        pendingLocation = location; tableLocation = location ?? .init()
        selected = []
        model.setSearch(query: state.query, sort: state.sort, scope: state.scope)
        if remember { embeddedPreferences?.saveSearch(state) }
    }
    private func searchFinished() {
        guard model.error == nil else { return }
        if let location = pendingLocation {
            if model.rows.count < location.loadedCount, model.hasMore {
                model.loadMore(); return
            }
            pendingLocation = nil
            selected = model.rows.filter { location.selectedIDs.contains($0.id) }
            tableRestoration = .init(location: location)
        }
        recordTask?.cancel()
        let snapshot = state, revision = revision, historyRevision = library.historyRevision
        recordTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.revision == revision, !self.model.busy, !self.suspended,
                  self.library.historyRevision == historyRevision else { return }
            try? self.library.recordQuery(snapshot.query, sort: snapshot.sort, scope: snapshot.scope)
        }
    }
    package func refresh() { selected = []; model.restart() }
    package func beginSaveQuery() { bookmarkName = model.query; savingQuery = true }
    func saveQuery() {
        do { try library.saveQuery(name: bookmarkName, query: model.query, sort: model.sort, scope: model.scope) }
        catch { actions.message = error.localizedDescription }
    }
    func setSort(_ value: SearchSort) {
        guard model.sort != value else { return }
        if standalone { SearchPreferences.saveSort(value) }
        var next = state; next.sort = value
        captureLocation(); history.transition(to: next)
        invalidateRestoration(); tableLocation = .init(); selected = []
        model.setSort(value)
        embeddedPreferences?.saveSearch(next)
    }
    func apply(_ saved: SavedQuery) {
        if standalone { SearchPreferences.saveSort(saved.sort) }
        transition(.init(query: saved.query, sort: saved.sort, scope: saved.scope))
        focusSearch()
    }
    package func perform(_ action: String, results: [SearchResult]? = nil) {
        let values = results ?? selected
        guard !values.isEmpty else { return }
        if deletion.working { return }
        if !standalone && (action == "delete" || action == "preview" || action == "chooseApplication" || action.hasPrefix("app:")) { return }
        switch action {
        case "searchInFolder": if values.count == 1, let first = values.first { searchInFolder(first) }
        case "delete":
            guard !actions.working, actions.pending == nil else { return }
            deletion.prepare(values, mappings: mappings)
        case "open": if let first = values.first { actions.perform([first], operation: .open, mappings: mappings, library: library) }
        case "reveal": actions.perform(values, operation: .reveal, mappings: mappings, library: library)
        case "copyMac": actions.copy(values, mac: true, mappings: mappings)
        case "copyWindows": actions.copy(values, mac: false, mappings: mappings)
        case "preview": selected = values; preview.toggle()
        case "chooseApplication": chooseApplication(results: values)
        default:
            if action.hasPrefix("app:"), let app = library.state.applications.first(where: { $0.path == String(action.dropFirst(4)) }) {
                actions.perform(values, operation: .application(app), mappings: mappings, library: library)
            }
        }
    }
    package func chooseApplication(results: [SearchResult]? = nil) {
        let values = results ?? selected
        guard !values.isEmpty, let window else { return }
        guard !values.contains(where: { $0.type == "folder" }) else {
            actions.message = "Для «Открыть в…» выберите только файлы. Папки можно открыть или показать в Finder."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Открыть выбранные файлы в…"
        panel.prompt = "Открыть"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let appURL = panel.url, let self else { return }
            let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
            let application = ApplicationChoice(name: name, path: appURL.resolvingSymlinksInPath().path)
            self.actions.perform(values, operation: .application(application), mappings: self.mappings, library: self.library)
        }
    }
}
