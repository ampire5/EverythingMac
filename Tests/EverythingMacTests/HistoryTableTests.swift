import XCTest
import AppKit
import SwiftUI
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class HistoryTableTests: XCTestCase {
    @MainActor func testRestorationSelectsIdentitiesAndDoesNotReapplyAfterUserScrolls() throws {
        _ = NSApplication.shared
        let rows = (0..<100).map { SearchResult(name: "Example\($0).txt", path: "C:\\Examples") }
        let restoration = TableRestoration(location: .init(topID: rows[50].id, offset: 4, fallbackRow: 50, selectedIDs: [rows[52].id], loadedCount: 100))
        let view = ResultsTable(rows: rows, fontSize: 11.5, windowID: UUID(), applications: [], sort: .constant(.init()), selection: { _ in }, perform: { _, _ in }, more: {}, restoration: restoration)
        let host = NSHostingView(rootView: view)
        host.frame = .init(x: 0, y: 0, width: 800, height: 300)
        host.layoutSubtreeIfNeeded()
        func find(_ v: NSView) -> FileTableView? { (v as? FileTableView) ?? v.subviews.lazy.compactMap(find).first }
        let table = try XCTUnwrap(find(host))
        let coordinator = try XCTUnwrap(table.delegate as? ResultsTable.Coordinator)
        coordinator.restoreIfNeeded()
        XCTAssertEqual(table.selectedRow, 52)
        XCTAssertEqual(table.enclosingScrollView!.contentView.bounds.minY, table.rect(ofRow: 50).minY + 4, accuracy: 1)
        table.enclosingScrollView!.contentView.scroll(to: .zero)
        coordinator.restoreIfNeeded()
        XCTAssertEqual(table.enclosingScrollView!.contentView.bounds.minY, 0, accuracy: 1)
    }
    func testFolderScopeUsesFolderItselfOrFilesParent() {
        XCTAssertEqual(SearchScope.folder(containing: .init(type: "folder", name: "Examples", path: "C:")), "C:\\Examples")
        XCTAssertEqual(SearchScope.folder(containing: .init(name: "Example.txt", path: "\\\\server\\Share\\Examples")), "\\\\server\\Share\\Examples")
    }
}
