import SwiftUI
import EverythingCore

struct SearchSidebar: View {
    let result: SearchResult?
    let mappings: [PathMapping]
    @ObservedObject var controller: PreviewController
    @ObservedObject var library: LibraryStore
    let query: String
    let sort: SearchSort
    var scope = SearchScope()
    let applyQuery: (SavedQuery) -> Void
    let saveQuery: () -> Void
    let reportError: (String) -> Void
    @State private var hoveredQuery: UUID?
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button { controller.favoritesExpanded.toggle() } label: {
                        Label("Избранное", systemImage: controller.favoritesExpanded ? "chevron.down" : "chevron.right")
                            .font(.callout.weight(.medium))
                    }.help(controller.favoritesExpanded ? "Свернуть избранные запросы" : "Развернуть избранные запросы")
                    Spacer(minLength: 0)
                    Button(action: saveQuery) { Image(systemName: "plus").frame(width: 24, height: 24) }
                        .help("Сохранить текущий запрос").accessibilityLabel("Сохранить текущий запрос")
                    Button { controller.pinned.toggle() } label: {
                        Image(systemName: controller.pinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
                    }.help(controller.pinned ? "Открепить панель" : "Закрепить панель")
                        .accessibilityLabel(controller.pinned ? "Открепить панель" : "Закрепить панель")
                    Button { controller.hide() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .help("Закрыть боковую панель").accessibilityLabel("Закрыть боковую панель")
                }
                .buttonStyle(.borderless).font(.system(size: 14, weight: .medium))
                .padding(.leading, 16).padding(.trailing, 12).frame(height: 44)
                if controller.favoritesExpanded {
                    if library.state.savedQueries.isEmpty {
                        Button("Сохранить текущий запрос…", action: saveQuery)
                            .buttonStyle(.link).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.bottom, 12)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(library.state.savedQueries) { saved in
                                    let active = saved.query == query && saved.sort == sort && saved.scope == scope
                                    Button { applyQuery(saved) } label: {
                                        HStack(spacing: 8) {
                                            Text(saved.name).lineLimit(1).truncationMode(.tail)
                                            Spacer(minLength: 0)
                                            if active { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                                        }
                                        .font(.callout).padding(.horizontal, 8).frame(height: 28)
                                        .background(.white.opacity(active ? 0.10 : hoveredQuery == saved.id ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 4))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { hovering in
                                        if hovering { hoveredQuery = saved.id }
                                        else if hoveredQuery == saved.id { hoveredQuery = nil }
                                    }
                                    .accessibilityAddTraits(active ? .isSelected : [])
                                    .help(saved.query.isEmpty ? "Все результаты" : saved.query)
                                    .contextMenu {
                                        Button("Удалить из избранного", role: .destructive) {
                                            do { try library.removeQuery(saved.id) } catch { reportError(error.localizedDescription) }
                                        }
                                    }
                                }
                            }.padding(.horizontal, 8).padding(.bottom, 8)
                        }
                        .frame(height: min(CGFloat(library.state.savedQueries.count) * 32 + 4, max(64, min(176, geometry.size.height * 0.3))))
                    }
                }
                Divider()
                FilePreviewPanel(result: result, mappings: mappings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.11).overlay(Color.black.opacity(0.35)))
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: controller.pinned ? 0 : 12))
        .overlay(RoundedRectangle(cornerRadius: controller.pinned ? 0 : 12).strokeBorder(.white.opacity(controller.pinned ? 0 : 0.12)).allowsHitTesting(false))
        .shadow(color: .black.opacity(controller.pinned ? 0 : 0.24), radius: 16, y: 4)
    }
}
