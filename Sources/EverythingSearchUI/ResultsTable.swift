import AppKit
import SwiftUI
import EverythingCore

extension Notification.Name {
    package static let focusSearch = Notification.Name("NetworkEverything.focusSearch")
    static let focusResults = Notification.Name("NetworkEverything.focusResults")
    package static let reloadConnection = Notification.Name("NetworkEverything.reloadConnection")
    static let fileAction = Notification.Name("NetworkEverything.fileAction")
}
final class FileTableView: NSTableView {
    var fileAction: ((String) -> Void)?
    var updateMenu: (() -> Void)?
    var fittingColumns = false
    var lastViewportWidth: CGFloat = -1
    var nameColumnShare: CGFloat = 0.45
    var metadataSizeWidth: CGFloat = 80
    var metadataDateWidth: CGFloat = 125
    @objc func copy(_ sender: Any?) { fileAction?("copyMac") }
    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        if event.keyCode == 36 || event.keyCode == 76 { fileAction?("open"); return }
        if command && event.keyCode == 51 && event.modifierFlags.intersection([.shift, .option, .control]).isEmpty { fileAction?("delete"); return }
        if command && event.keyCode == 125 { fileAction?("open"); return }
        if command && event.keyCode == 8 { fileAction?(event.modifierFlags.contains(.shift) ? "copyWindows" : "copyMac"); return }
        if command && event.keyCode == 15 { fileAction?("reveal"); return }
        if event.keyCode == 49 { fileAction?("preview"); return }
        if event.keyCode == 53 { fileAction?("focusSearch"); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        updateMenu?()
        return super.menu(for: event)
    }
}
struct ResultsTable: NSViewRepresentable {
    let rows: [SearchResult]
    let fontSize: Double
    let windowID: UUID
    let applications: [ApplicationChoice]
    let sort: Binding<SearchSort>
    let selection: ([SearchResult]) -> Void
    let perform: (String, [SearchResult]) -> Void
    let more: () -> Void
    var restoration: TableRestoration? = nil
    var standalone = true
    var viewport: (TableLocation) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ResultsScrollView()
        let table = FileTableView()
        context.coordinator.table = table
        table.allowsMultipleSelection = true
        table.rowHeight = ceil(max(11.5, min(14, fontSize)) + 12)
        table.configureColumns()
        table.autosaveName = "NetworkEverything.Results"; table.autosaveTableColumns = true
        context.coordinator.applySort(sort.wrappedValue, to: table)
        // Restoring AppKit's saved columns may restore old sort descriptors too.
        // The model owns sorting; install the delegate only after initialization.
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.doubleClick)
        table.fileAction = { [weak coordinator = context.coordinator] action in coordinator?.run(action) }
        table.updateMenu = { [weak coordinator = context.coordinator] in coordinator?.rebuildMenu() }
        context.coordinator.rebuildMenu()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak coordinator = context.coordinator, weak scroll] _ in
            // These AppKit notifications are delivered synchronously on the main queue.
            MainActor.assumeIsolated {
                guard let coordinator, let scroll else { return }
                coordinator.reportLocation()
                let remaining = (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.maxY
                if remaining < 250 && !coordinator.parent.rows.isEmpty { coordinator.parent.more() }
            }
        }
        let contextID = windowID
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(forName: .focusResults, object: nil, queue: .main) { [weak table] notification in
            let targetID = notification.object as? UUID
            MainActor.assumeIsolated {
                guard let table, targetID == contextID else { return }
                table.window?.makeFirstResponder(table)
                if table.selectedRow < 0 && table.numberOfRows > 0 { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
            }
        }
        context.coordinator.updateMetadataWidths()
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in coordinator?.restoreIfNeeded() }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        let changed = c.parent.rows != rows
        let fontChanged = c.parent.fontSize != fontSize
        let currentSort = sort.wrappedValue
        c.parent = self
        guard let table = c.table else { return }
        // A queued representable can predate the last click. Read through the binding
        // so even that update uses the current model rather than its old snapshot.
        c.applySort(currentSort, to: table)
        if changed || fontChanged {
            table.rowHeight = ceil(max(11.5, min(14, fontSize)) + 12)
            c.updateMetadataWidths()
            table.fitColumns(to: scroll.contentSize.width, force: true)
            let selected = Set(table.selectedRowIndexes.compactMap { c.previousRows.indices.contains($0) ? c.previousRows[$0].id : nil })
            c.previousRows = rows
            table.reloadData()
            table.selectRowIndexes(IndexSet(rows.indices.filter { selected.contains(rows[$0].id) }), byExtendingSelection: false)
            c.notifySelection()
        }
        c.restoreIfNeeded()
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: ResultsTable
        var previousRows: [SearchResult]
        weak var table: FileTableView?
        var focusObserver: NSObjectProtocol?
        var scrollObserver: NSObjectProtocol?
        private var publishingHeaderClick = false
        private var restoredID: UUID?
        let sizeFormatter: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .file; return f }()
        let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f }()
        init(_ parent: ResultsTable) { self.parent = parent; previousRows = parent.rows }
        isolated deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.rows.indices.contains(row), let key = tableColumn?.identifier.rawValue else { return nil }
            let result = parent.rows[row]
            let id = NSUserInterfaceItemIdentifier(key + ".cell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView { cell = reused }
            else {
                cell = NSTableCellView(); cell.identifier = id
                let text = NSTextField(labelWithString: "")
                text.lineBreakMode = key == "path" ? .byTruncatingMiddle : .byTruncatingTail
                text.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(text); cell.textField = text
                NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: key == "name" ? 32 : 8), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                if key == "name" {
                    let icon = NSImageView(); icon.translatesAutoresizingMaskIntoConstraints = false
                    icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
                    icon.contentTintColor = .secondaryLabelColor
                    cell.addSubview(icon); cell.imageView = icon
                    NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                }
            }
            cell.textField?.font = cellFont(for: key)
            switch key {
            case "name":
                cell.textField?.stringValue = result.name
                cell.imageView?.image = NSImage(systemSymbolName: result.type == "folder" ? "folder" : "doc", accessibilityDescription: nil)
            case "path": cell.textField?.stringValue = result.path
            case "size": cell.textField?.stringValue = result.size.flatMap { $0 <= UInt64(Int64.max) ? sizeFormatter.string(fromByteCount: Int64($0)) : nil } ?? "—"; cell.textField?.alignment = .right
            default: cell.textField?.stringValue = result.date_modified.map { dateFormatter.string(from: $0) } ?? "—"; cell.textField?.alignment = .right
            }
            cell.toolTip = result.windowsPath
            return cell
        }
        private func cellFont(for key: String) -> NSFont {
            let size = max(11.5, min(14, parent.fontSize))
            switch key {
            case "size", "date_modified": return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            default: return .systemFont(ofSize: size)
            }
        }
        private func displayText(_ result: SearchResult, key: String) -> String {
            switch key {
            case "name": return result.name
            case "path": return result.path
            case "size": return result.size.flatMap { $0 <= UInt64(Int64.max) ? sizeFormatter.string(fromByteCount: Int64($0)) : nil } ?? "—"
            default: return result.date_modified.map { dateFormatter.string(from: $0) } ?? "—"
            }
        }
        private func contentWidth(key: String, title: String) -> CGFloat {
            let font = cellFont(for: key)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let header = (title as NSString).size(withAttributes: attributes).width + 30
            // Bound measurement work to a page; all input is already in memory.
            let text = parent.rows.prefix(200).map { (displayText($0, key: key) as NSString).size(withAttributes: attributes).width }.max() ?? 0
            return ceil(max(header, text + (key == "name" ? 40 : 16)))
        }
        func updateMetadataWidths() {
            table?.metadataSizeWidth = max(78, min(120, contentWidth(key: "size", title: "Размер")))
            table?.metadataDateWidth = max(118, min(180, contentWidth(key: "date_modified", title: "Изменён")))
        }
        func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
            guard tableView.tableColumns.indices.contains(column) else { return 100 }
            let item = tableView.tableColumns[column]
            let measured = contentWidth(key: item.identifier.rawValue, title: item.title)
            return max(item.minWidth, min(900, measured))
        }
        func tableViewSelectionDidChange(_ notification: Notification) { notifySelection() }
        func reportLocation() {
            guard let table, let scroll = table.enclosingScrollView else { return }
            let y = scroll.contentView.bounds.minY
            let row = max(0, table.row(at: .init(x: 0, y: y)))
            let location = TableLocation(topID: parent.rows.indices.contains(row) ? parent.rows[row].id : nil,
                                         offset: y - table.rect(ofRow: row).minY, fallbackRow: row,
                                         selectedIDs: Set(selectedResults().map(\.id)), loadedCount: parent.rows.count)
            let callback = parent.viewport
            DispatchQueue.main.async { callback(location) }
        }
        func restoreIfNeeded() {
            guard let restoration = parent.restoration, restoredID != restoration.id,
                  let table, let scroll = table.enclosingScrollView else { return }
            restoredID = restoration.id
            let location = restoration.location
            let indexes = IndexSet(parent.rows.indices.filter { location.selectedIDs.contains(parent.rows[$0].id) })
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            if !parent.rows.isEmpty {
                let row = parent.rows.firstIndex(where: { $0.id == location.topID }) ?? min(max(0, location.fallbackRow), parent.rows.count - 1)
                table.layoutSubtreeIfNeeded()
                let target = table.rect(ofRow: row).minY + location.offset
                let maximum = max(0, table.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: .init(x: scroll.contentView.bounds.minX, y: min(maximum, max(0, target))))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            notifySelection(); reportLocation()
        }
        func notifySelection() {
            guard table != nil else { return }
            // Read the current selection when publishing, never a snapshot from an older reload.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.selection(self.selectedResults())
            }
        }
        func applySort(_ sort: SearchSort, to table: NSTableView) {
            guard !publishingHeaderClick else { return }
            guard table.sortDescriptors.first?.key != sort.field || table.sortDescriptors.first?.ascending != sort.ascending else { return }
            table.sortDescriptors = [NSSortDescriptor(key: sort.field, ascending: sort.ascending)]
        }
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let current = parent.sort.wrappedValue
            let field = tableColumn.identifier.rawValue
            let next = SearchSort(field: field, ascending: current.field == field ? !current.ascending : true)
            // Publish exactly one intent per column click. Native descriptor updates
            // also occur for restoration and are not a reliable input event.
            publishingHeaderClick = true
            parent.sort.wrappedValue = next
            publishingHeaderClick = false
            applySort(parent.sort.wrappedValue, to: tableView)
        }
        @objc func doubleClick() {
            guard let table, table.clickedRow >= 0, parent.rows.indices.contains(table.clickedRow) else { return }
            run("open")
        }
        func selectedResults() -> [SearchResult] {
            guard let table else { return [] }
            return table.selectedRowIndexes.compactMap { parent.rows.indices.contains($0) ? parent.rows[$0] : nil }
        }
        func run(_ action: String) {
            if action == "focusSearch" { NotificationCenter.default.post(name: .focusSearch, object: parent.windowID); return }
            parent.perform(action, selectedResults())
        }
        func rebuildMenu() {
            guard let table else { return }
            let menu = NSMenu()
            func item(_ title: String, _ action: String) -> NSMenuItem {
                let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = action
                return item
            }
            menu.addItem(item("Открыть", "open"))
            let folderSearch = item("Искать в этой папке", "searchInFolder")
            folderSearch.isEnabled = table.selectedRowIndexes.count == 1
            menu.addItem(folderSearch)
            if parent.standalone {
                if let last = parent.applications.first { menu.addItem(item("Открыть в \(last.name)", "app:" + last.path)) }
                let openWith = NSMenuItem(title: "Открыть в…", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for app in parent.applications { submenu.addItem(item(app.name, "app:" + app.path)) }
                if !parent.applications.isEmpty { submenu.addItem(.separator()) }
                submenu.addItem(item("Выбрать приложение…", "chooseApplication"))
                openWith.submenu = submenu; menu.addItem(openWith)
            }
            menu.addItem(.separator())
            if parent.standalone { menu.addItem(item("Превью", "preview")) }
            for (title, action) in [("Показать в Finder", "reveal"), ("Копировать Mac-пути", "copyMac"), ("Копировать Windows-пути", "copyWindows")] { menu.addItem(item(title, action)) }
            if parent.standalone {
                menu.addItem(.separator())
                menu.addItem(item("Удалить…", "delete"))
            }
            table.menu = menu
        }
        @objc func menuAction(_ item: NSMenuItem) { if let value = item.representedObject as? String { run(value) } }
    }
}
