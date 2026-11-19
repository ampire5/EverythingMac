import AppKit
import SwiftUI
import EverythingCore

package struct SearchContent: View {
    @ObservedObject private var session: SearchSession
    @ObservedObject private var model: SearchModel
    @ObservedObject private var actions: FileActions
    @ObservedObject private var deletion: FileDeletionController
    @ObservedObject private var library: LibraryStore
    @ObservedObject private var preview: PreviewController
    private let standalone: Bool
    private let active: Bool

    package init(session: SearchSession, standalone: Bool, active: Bool = true) {
        self.session = session
        model = session.model
        actions = session.actions
        deletion = session.deletion
        library = session.library
        preview = session.preview
        self.standalone = standalone
        self.active = active
    }

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("query") private var restoredQuery = ""
    @SceneStorage("sortField") private var restoredSort = ""
    @SceneStorage("sortAscending") private var restoredAscending = true
    @SceneStorage("filterKind") private var restoredKind = "all"
    @SceneStorage("folderScope") private var restoredFolder = ""
    @State private var started = false
    @AppStorage("Results.fontSize") private var resultsFontSize = 11.5
    package var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SearchNavigationControls(session: session)
                    NativeSearchField(text: Binding(get: { model.query }, set: session.editQuery), windowID: session.id, onCommit: session.commitQuery)
                        .frame(height: 32)
                        .layoutPriority(1)
                    HStack(spacing: 4) {
                        RecentSearchMenu(session: session, library: library)
                        queryMenu
                        if standalone {
                            Divider().frame(height: 16).padding(.horizontal, 4)
                            Button { preview.toggle() } label: {
                                Image(systemName: "sidebar.right").frame(width: 24, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(preview.visible ? Color.accentColor : Color.secondary)
                            .help("Превью файла (⌃⌘→ или пробел в таблице)")
                            .accessibilityLabel(preview.visible ? "Скрыть превью" : "Показать превью")
                            SettingsLink { Image(systemName: "gearshape").frame(width: 24, height: 28) }
                                .buttonStyle(.borderless)
                                .help("Подключение и сетевые папки")
                                .accessibilityLabel("Настройки")
                        }
                    }.font(.system(size: 14, weight: .medium))
                }
                SearchFilters(session: session, model: model)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if let error = model.error { errorBanner(error) }
            if let error = library.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).textSelection(.enabled)
                    Spacer()
                }.font(.callout).padding(.horizontal, 16).padding(.vertical, 8)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    resultsArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if standalone && preview.visible && preview.pinned {
                        searchSidebar
                            .frame(width: preview.width(available: geometry.size.width))
                            .overlay(alignment: .leading) { PreviewResizeHandle(controller: preview, availableWidth: geometry.size.width) }
                    }
                }
                .overlay(alignment: .trailing) {
                    ZStack(alignment: .trailing) {
                        if standalone && preview.visible && !preview.pinned {
                            searchSidebar
                                .frame(width: preview.width(available: geometry.size.width))
                                .overlay(alignment: .leading) { PreviewResizeHandle(controller: preview, availableWidth: geometry.size.width) }
                                .padding(12)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else if standalone && !preview.visible, let hint = preview.edgeHint {
                            GeometryReader { edge in
                                Button { preview.show() } label: {
                                    Capsule().fill(.secondary).frame(width: 4, height: 40)
                                        .frame(width: 16, height: 48)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).help("Показать превью").accessibilityLabel("Показать превью")
                                .opacity(hint.opacity)
                                .position(x: edge.size.width / 2, y: hint.y)
                            }.frame(width: 16)
                            .transition(.identity)
                        }
                    }
                    .animation(previewAnimation, value: preview.visible)
                }
                .clipped()
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named("SearchContent"))
                } action: { frame in
                    preview.resultsFrame = frame
                }
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .coordinateSpace(name: "SearchContent")
        .frame(minWidth: standalone ? 780 : nil, minHeight: standalone ? 440 : nil)
        .task(id: active) {
            guard active else { return }
            guard standalone else {
                session.startEmbedded()
                return
            }
            preview.startMonitoring()
            guard !started else { return }
            started = true
            let initialSort = SearchPreferences.initialSort(sceneField: restoredSort, sceneAscending: restoredAscending)
            session.start(.init(query: restoredQuery, sort: initialSort,
                                scope: .init(kind: SearchKind(rawValue: restoredKind) ?? .all, folder: restoredFolder.isEmpty ? nil : restoredFolder)))
            // A Service may have initialized the session before scene restoration.
            restoredQuery = model.query
            restoredSort = model.sort.field; restoredAscending = model.sort.ascending
            restoredKind = model.scope.kind.rawValue; restoredFolder = model.scope.folder ?? ""
        }
        .onDisappear { preview.stopMonitoring(); actions.cancel() }
        .onChange(of: model.query) { _, value in
            guard standalone else { return }
            restoredQuery = value
            session.window?.title = value.isEmpty ? "Network Everything" : value
        }
        .onChange(of: model.sort) { _, value in
            guard standalone else { return }
            restoredSort = value.field; restoredAscending = value.ascending
        }
        .onChange(of: model.scope) { _, scope in
            guard standalone else { return }
            restoredKind = scope.kind.rawValue; restoredFolder = scope.folder ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadConnection)) { _ in if standalone { session.refresh() } }
        .alert("Сохранить запрос", isPresented: $session.savingQuery) {
            TextField("Название", text: $session.bookmarkName)
            Button("Отмена", role: .cancel) { }
            Button("Сохранить") { session.saveQuery() }.disabled(session.bookmarkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Сохраняются запрос, сортировка, тип файлов и папка поиска. Совпадающее название обновляет закладку.") }
        .alert("Действие с файлом", isPresented: Binding(get: { actions.message != nil }, set: { if !$0 { actions.message = nil } })) {
            if standalone { Button("Настройки") { openSettings() } }
            Button("OK", role: .cancel) { actions.message = nil }
        } message: { Text(actions.message ?? "") }
        .onReceive(deletion.$message.compactMap { $0 }) { actions.message = $0 }
        .sheet(item: $deletion.confirmation) { request in
            DeletionSheet(request: request, cancel: { deletion.confirmation = nil }, confirm: { deletion.confirm(mappings: session.mappings) })
        }
        .sheet(item: $actions.pending) { pending in
            VStack(alignment: .leading, spacing: 16) {
                Text("Сетевая папка не подключена").font(.title2.weight(.medium))
                Text(pending.mapping.shareURL).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("Откройте сетевую папку в Finder. Если Finder запросит пароль SMB, введите его там. После подключения нажмите «Повторить действие».")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Отмена", role: .cancel) { actions.pending = nil }
                    if standalone { Button("Настройки") { actions.pending = nil; openSettings() } }
                    Spacer()
                    Button("Открыть в Finder") { actions.connect() }.keyboardShortcut(.defaultAction)
                    Button("Повторить действие") { actions.retry(mappings: session.mappings, library: library) }
                }
            }.padding(24).frame(width: 560)
        }
    }
    private var searchSidebar: some View {
        SearchSidebar(result: deletion.working || deletion.confirmation != nil ? nil : session.selected.first, mappings: session.mappings, controller: preview, library: library, query: model.query, sort: model.sort, scope: model.scope, applyQuery: session.apply, saveQuery: session.beginSaveQuery, reportError: { actions.message = $0 })
    }
    private var previewAnimation: Animation? {
        guard !preview.pinned, !reduceMotion else { return nil }
        return preview.visible ? .interpolatingSpring(mass: 1, stiffness: 300, damping: 28.4) : .easeOut(duration: 0.15)
    }
    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.busy { ProgressView().controlSize(.mini).accessibilityHidden(true) }
            Text(searchStatus).monospacedDigit().lineLimit(1)
            if model.hasMore && !model.busy && model.error == nil {
                Button("Загрузить ещё") { model.loadMore() }
                    .buttonStyle(.link).foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 4)
            if deletion.working || actions.working {
                ProgressView().controlSize(.mini).accessibilityHidden(true)
                Text(deletion.working ? "Удаление…" : "Открытие…")
            } else if !session.selected.isEmpty {
                Text("Выбрано \(session.selected.count.formatted())").monospacedDigit().fixedSize()
            }
        }
        .font(.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 16).frame(minHeight: 32)
    }
    private var searchStatus: String {
        if model.busy {
            if model.loadingMore { return "Загрузка следующей страницы…" }
            return model.rows.isEmpty ? "Поиск…" : "Обновление результатов…"
        }
        if model.error != nil {
            return model.rows.isEmpty ? "Поиск прерван" : "Показаны ранее загруженные результаты"
        }
        if model.rows.count == model.total { return "Найдено \(model.total.formatted())" }
        return "\(model.rows.count.formatted()) из \(model.total.formatted())"
    }
    private var resultsArea: some View {
        ZStack {
            ResultsTable(rows: model.rows, fontSize: resultsFontSize, windowID: session.id, applications: library.state.applications, sort: Binding(get: { model.sort }, set: session.setSort), selection: { session.selected = $0 }, perform: { session.perform($0, results: $1) }, more: { model.loadMore() }, restoration: session.tableRestoration, standalone: standalone, viewport: { [state = session.state] in session.updateLocation($0, for: state) })
            if started || !standalone, model.rows.isEmpty && !model.busy && model.error == nil {
                let filtered = model.scope != SearchScope()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(model.query.isEmpty && !filtered ? "Индекс Everything пуст" : "Совпадений нет")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    Text(filtered ? "Попробуйте поиск по всем типам файлов и папкам." :
                            model.query.isEmpty ? "Проверьте, какие папки индексирует Everything." : "Уточните имя файла или попробуйте более короткий запрос.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if filtered {
                        Button("Сбросить фильтры") { session.setScope(.init()) }.buttonStyle(.link)
                    } else if !model.query.isEmpty {
                        Button("Изменить запрос") { session.focusSearch() }.buttonStyle(.link)
                    }
                }
                .frame(maxWidth: 340)
                .padding(.horizontal, 16)
            }
        }
    }
    private var queryMenu: some View {
        Menu {
            Button("Сохранить запрос…") { session.beginSaveQuery() }
            if !library.state.savedQueries.isEmpty {
                Section("Сохранённые") {
                    ForEach(library.state.savedQueries) { saved in
                        Button(saved.name) { session.apply(saved) }
                    }
                }
                Menu("Удалить закладку") {
                    ForEach(library.state.savedQueries) { saved in
                        Button(saved.name) {
                            do { try library.removeQuery(saved.id) } catch { actions.message = error.localizedDescription }
                        }
                    }
                }
            }
        } label: { Image(systemName: "star") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Закладки запросов").accessibilityLabel("Закладки запросов")
    }
    private func errorBanner(_ error: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(nsColor: .systemOrange))
                    .accessibilityHidden(true).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Не удалось загрузить результаты").font(.callout.weight(.semibold))
                    Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if standalone { SettingsLink { Text("Настройки") } }
                    Button("Повторить") { model.retry() }
                }.fixedSize()
            }.padding(.horizontal, 16).padding(.vertical, 10).background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
    }
}
