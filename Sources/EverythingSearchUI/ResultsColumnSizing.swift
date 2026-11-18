import AppKit

enum ResultsColumnSizing {
    static func widths(available: Double, nameShare: Double, size: Double, date: Double) -> [Double] {
        let extra = max(0, available - 12 - 160 - 140 - size - date)
        let share = min(1, max(0, nameShare.isFinite ? nameShare : 0.45))
        return [160 + extra * share, 140 + extra * (1 - share), size, date]
    }
}
final class ResultsHeaderView: NSTableHeaderView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = column(at: point)
        if event.clickCount > 1, column >= 0, let tableView {
            let rect = headerRect(ofColumn: column)
            // AppKit treats a rapid second header click as a double action.
            // A column title should instead toggle sorting on every click.
            // Keep divider double-clicks native for automatic column sizing.
            if point.x > rect.minX + 5, point.x < rect.maxX - 5 {
                tableView.delegate?.tableView?(tableView, didClick: tableView.tableColumns[column])
                return
            }
        }
        super.mouseDown(with: event)
    }
}
/// Refitting is driven by viewport changes, never by individual cell rendering.
final class ResultsScrollView: NSScrollView {
    override func tile() {
        super.tile()
        (documentView as? FileTableView)?.fitColumns(to: contentSize.width)
    }
}
extension FileTableView {
    func configureColumns() {
        headerView = ResultsHeaderView()
        style = .plain
        columnAutoresizingStyle = .noColumnAutoresizing
        intercellSpacing = NSSize(width: 3, height: 2)
        for (id, title, width, minimum) in [("name", "Название", 290.0, 160.0), ("path", "Папка", 390.0, 140.0), ("size", "Размер", 80.0, 70.0), ("date_modified", "Изменён", 125.0, 110.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.minWidth = minimum; column.width = width
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            addTableColumn(column)
        }
    }
    func fitColumns(to width: CGFloat, force: Bool = false) {
        guard width > 0, !fittingColumns, force || abs(width - lastViewportWidth) > 0.5 else { return }
        let keys = ["name", "path", "size", "date_modified"]
        let columns = keys.compactMap { tableColumn(withIdentifier: .init($0)) }
        guard columns.count == 4 else { return }
        fittingColumns = true
        defer { fittingColumns = false }
        lastViewportWidth = width
        let nameExtra = max(0, columns[0].width - 160)
        let pathExtra = max(0, columns[1].width - 140)
        if nameExtra + pathExtra > 0.5 { nameColumnShare = nameExtra / (nameExtra + pathExtra) }
        let widths = ResultsColumnSizing.widths(available: width, nameShare: nameColumnShare, size: metadataSizeWidth, date: metadataDateWidth)
        for (column, value) in zip(columns, widths) { column.width = value }
    }
}
