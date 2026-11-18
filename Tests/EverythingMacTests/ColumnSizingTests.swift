import XCTest
import AppKit
@testable import EverythingMac
@testable import EverythingSearchUI

final class ColumnSizingTests: XCTestCase {
    func testColumnsFitAvailableWidthAndProtectMetadata() {
        let sizes = ResultsColumnSizing.widths(available: 680, nameShare: 0.45, size: 80, date: 125)
        XCTAssertEqual(sizes.reduce(0, +) + 12, 680, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(sizes[0], 160)
        XCTAssertGreaterThanOrEqual(sizes[1], 140)
        XCTAssertEqual(sizes[2], 80)
        XCTAssertEqual(sizes[3], 125)
    }
    func testNarrowViewportUsesReadableMinimumsInsteadOfCrushingColumns() {
        let sizes = ResultsColumnSizing.widths(available: 320, nameShare: 0.45, size: 80, date: 125)
        XCTAssertEqual(sizes, [160, 140, 80, 125])
    }
    func testWiderViewportGivesExtraSpaceToNamesAndPathsOnly() {
        let narrow = ResultsColumnSizing.widths(available: 680, nameShare: 0.6, size: 80, date: 125)
        let wide = ResultsColumnSizing.widths(available: 1000, nameShare: 0.6, size: 80, date: 125)
        XCTAssertGreaterThan(wide[0], narrow[0])
        XCTAssertGreaterThan(wide[1], narrow[1])
        XCTAssertEqual(Array(wide.suffix(2)), [80, 125])
    }
    @MainActor func testActualTableRefitsWhenClipWidthChanges() {
        _ = NSApplication.shared
        let scroll = ResultsScrollView(frame: .init(x: 0, y: 0, width: 1000, height: 400))
        let table = FileTableView()
        table.configureColumns()
        scroll.documentView = table
        scroll.tile()
        let before = table.tableColumns.map(\.width)
        scroll.setFrameSize(.init(width: 680, height: 400))
        scroll.tile()
        let after = table.tableColumns.map(\.width)
        XCTAssertLessThan(after[0], before[0])
        XCTAssertLessThan(after[1], before[1])
        XCTAssertLessThanOrEqual(table.rect(ofColumn: 3).maxX, scroll.contentSize.width + 1)
    }
    @MainActor func testRepeatedFittingKeepsDividerAndRestoresItAfterNarrowWindow() {
        _ = NSApplication.shared
        let table = FileTableView()
        table.configureColumns()
        table.fitColumns(to: 680)
        let before = table.tableColumns.map(\.width)
        for _ in 0..<10 { table.fitColumns(to: 680, force: true) }
        XCTAssertEqual(table.tableColumns[0].width, before[0], accuracy: 0.01)
        XCTAssertEqual(table.tableColumns[1].width, before[1], accuracy: 0.01)
        table.fitColumns(to: 320)
        table.fitColumns(to: 680)
        XCTAssertEqual(table.tableColumns[0].width, before[0], accuracy: 0.01)
        XCTAssertEqual(table.tableColumns[1].width, before[1], accuracy: 0.01)
    }

}
