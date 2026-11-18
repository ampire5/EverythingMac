import SwiftUI
import EverythingCore

struct SearchNavigationControls: View {
    @ObservedObject var session: SearchSession
    var body: some View {
        HStack(spacing: 4) {
            Button { session.goBack() } label: { Image(systemName: "chevron.left").frame(width: 24, height: 28) }
                .disabled(!session.history.canGoBack).help("Предыдущий поиск (⌘[)").accessibilityLabel("Предыдущий поиск")
            Button { session.goForward() } label: { Image(systemName: "chevron.right").frame(width: 24, height: 28) }
                .disabled(!session.history.canGoForward).help("Следующий поиск (⌘])").accessibilityLabel("Следующий поиск")
        }.buttonStyle(.borderless).font(.system(size: 14, weight: .medium))
    }
}

struct RecentSearchMenu: View {
    @ObservedObject var session: SearchSession
    @ObservedObject var library: LibraryStore
    var body: some View {
        Menu {
            if library.state.recentQueries.isEmpty { Text("История пока пуста") }
            ForEach(library.state.recentQueries) { saved in
                Button { session.apply(saved) } label: {
                    Text(label(saved))
                }.help(saved.scope.expression(for: saved.query))
            }
            if !library.state.recentQueries.isEmpty {
                Divider()
                Button("Очистить историю") {
                    do { try library.clearRecentQueries() } catch { session.actions.message = error.localizedDescription }
                }
            }
        } label: { Image(systemName: "clock") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("История поиска").accessibilityLabel("История поиска")
    }
    private func label(_ saved: SavedQuery) -> String {
        var parts = [saved.query.isEmpty ? "Все результаты" : saved.query]
        if saved.scope.kind != .all { parts.append(saved.scope.kind.title) }
        if let folder = saved.scope.folder { parts.append(folder) }
        return parts.joined(separator: " · ")
    }
}

struct SearchFilters: View {
    @ObservedObject var session: SearchSession
    @ObservedObject var model: SearchModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Тип файлов", selection: Binding(get: { model.scope.kind }, set: { kind in
                var scope = model.scope; scope.kind = kind; session.setScope(scope)
            })) {
                ForEach(SearchKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
            if let folder = model.scope.folder {
                HStack(spacing: 8) {
                    Label("Папка", systemImage: "folder").foregroundStyle(.secondary)
                    Text(folder).font(.system(.caption, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button {
                        var scope = model.scope; scope.folder = nil; session.setScope(scope)
                    } label: { Image(systemName: "xmark").frame(width: 16, height: 16) }
                    .buttonStyle(.borderless).help("Искать во всех папках").accessibilityLabel("Снять ограничение папки")
                }.font(.callout).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4)).help(folder)
            }
        }
    }
}
