import XCTest
import AppKit
import SwiftUI
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class ResultsSortingTests: XCTestCase {
    @MainActor func testColumnClickUsesModelDirectionWhenNativeDescriptorIsStale() throws {
        _ = NSApplication.shared
        let model = SearchModel(delay: 0) { _, _, _ in
            try EverythingAPI.decode(Data(#"{"totalResults":0,"results":[]}"#.utf8), status: 200)
        }
        let view = ResultsTable(rows: [], fontSize: 11.5, windowID: UUID(), applications: [],
                                sort: Binding(get: { model.sort }, set: { model.setSort($0) }),
                                selection: { _ in }, perform: { _, _ in }, more: {})
        let host = NSHostingView(rootView: view)
        host.frame = .init(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        func findTable(_ root: NSView) -> FileTableView? {
            if let table = root as? FileTableView { return table }
            return root.subviews.lazy.compactMap(findTable).first
        }
        let table = try XCTUnwrap(findTable(host))
        let column = try XCTUnwrap(table.tableColumn(withIdentifier: .init("size")))
        table.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        table.delegate?.tableView?(table, didClick: column)
        XCTAssertEqual(model.sort, .init(field: "size", ascending: true))
        table.sortDescriptors = [NSSortDescriptor(key: "size", ascending: true)]
        table.delegate?.tableView?(table, didClick: column)
        XCTAssertEqual(model.sort, .init(field: "size", ascending: false))
        XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
    }
    @MainActor func testExternalSortCanRestoreOriginalValueBeforeHeaderUpdateRenders() throws {
        _ = NSApplication.shared
        let model = SearchModel(delay: 0) { _, _, _ in
            try EverythingAPI.decode(Data(#"{"totalResults":0,"results":[]}"#.utf8), status: 200)
        }
        func view() -> ResultsTable {
            ResultsTable(rows: [], fontSize: 11.5, windowID: UUID(), applications: [],
                         sort: Binding(get: { model.sort }, set: { model.setSort($0) }),
                         selection: { _ in }, perform: { _, _ in }, more: {})
        }
        let host = NSHostingView(rootView: view())
        host.frame = .init(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        func findTable(_ root: NSView) -> FileTableView? {
            if let table = root as? FileTableView { return table }
            return root.subviews.lazy.compactMap(findTable).first
        }
        let table = try XCTUnwrap(findTable(host))
        let column = try XCTUnwrap(table.tableColumn(withIdentifier: .init("size")))
        table.delegate?.tableView?(table, didClick: column)
        model.setSort(.init())
        host.rootView = view()
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.sortDescriptors.first?.key, "name")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, true)
    }
    @MainActor func testQueuedViewUpdateCannotUndoNewerHeaderDirection() throws {
        _ = NSApplication.shared
        let model = SearchModel(delay: 0) { _, _, _ in
            try EverythingAPI.decode(Data(#"{"totalResults":0,"results":[]}"#.utf8), status: 200)
        }
        func view(font: Double) -> ResultsTable {
            ResultsTable(rows: [], fontSize: font, windowID: UUID(), applications: [], sort: Binding(get: { model.sort }, set: { model.setSort($0) }),
                         selection: { _ in }, perform: { _, _ in }, more: {})
        }
        let host = NSHostingView(rootView: view(font: 11.5))
        host.frame = .init(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        func findTable(_ root: NSView) -> FileTableView? {
            if let table = root as? FileTableView { return table }
            return root.subviews.lazy.compactMap(findTable).first
        }
        let table = try XCTUnwrap(findTable(host))
        let column = try XCTUnwrap(table.tableColumn(withIdentifier: .init("size")))
        table.delegate?.tableView?(table, didClick: column)
        let queuedView = view(font: 12)
        table.delegate?.tableView?(table, didClick: column)
        XCTAssertEqual(model.sort, .init(field: "size", ascending: false))
        // SwiftUI may deliver a view prepared between the first and second click.
        host.rootView = queuedView
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.sortDescriptors.first?.key, "size")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
        XCTAssertEqual(model.sort, .init(field: "size", ascending: false))
    }
    @MainActor func testRapidHeaderClicksSelectColumnThenReverseDespiteRowDoubleAction() throws {
        _ = NSApplication.shared
        var changes: [SearchSort] = []
        var currentSort = SearchSort()
        let view = ResultsTable(rows: [], fontSize: 11.5, windowID: UUID(), applications: [], sort: Binding(get: { currentSort }, set: { currentSort = $0; changes.append($0) }),
                                selection: { _ in }, perform: { _, _ in }, more: {})
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func findTable(_ root: NSView) -> FileTableView? {
            if let table = root as? FileTableView { return table }
            return root.subviews.lazy.compactMap(findTable).first
        }
        let table = try XCTUnwrap(findTable(host))
        let header = try XCTUnwrap(table.headerView)
        let column = try XCTUnwrap(table.tableColumns.firstIndex { $0.identifier.rawValue == "size" })
        let rect = header.headerRect(ofColumn: column)
        let point = header.convert(.init(x: rect.midX, y: rect.midY), to: nil)
        for count in [1, 2, 3] {
            let time = ProcessInfo.processInfo.systemUptime
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 0))
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1))
            if count == 1 { NSApp.postEvent(up, atStart: true) }
            header.mouseDown(with: down)
        }
        XCTAssertEqual(changes, [.init(field: "size", ascending: true), .init(field: "size", ascending: false), .init(field: "size", ascending: true)])
        XCTAssertEqual(table.sortDescriptors.first?.key, "size")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, true)
    }
    @MainActor func testRestoringSortDoesNotPublishItAsAHeaderClick() throws {
        _ = NSApplication.shared
        var changes: [SearchSort] = []
        var currentSort = SearchSort()
        func view(_ sort: SearchSort) -> ResultsTable {
            currentSort = sort
            return ResultsTable(rows: [], fontSize: 11.5, windowID: UUID(), applications: [], sort: Binding(get: { currentSort }, set: { currentSort = $0; changes.append($0) }),
                         selection: { _ in }, perform: { _, _ in }, more: {})
        }
        let host = NSHostingView(rootView: view(.init(field: "size", ascending: false)))
        host.frame = .init(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        func findTable(_ root: NSView) -> FileTableView? {
            if let table = root as? FileTableView { return table }
            return root.subviews.lazy.compactMap(findTable).first
        }
        let table = try XCTUnwrap(findTable(host))
        XCTAssertTrue(changes.isEmpty, "Initial model sort must not overwrite the saved default")
        host.rootView = view(.init(field: "path", ascending: true))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.sortDescriptors.first?.key, "path")
        XCTAssertTrue(changes.isEmpty, "Model updates must not feed back into the search")
        let column = try XCTUnwrap(table.tableColumn(withIdentifier: .init("date_modified")))
        table.delegate?.tableView?(table, didClick: column)
        table.delegate?.tableView?(table, didClick: column)
        XCTAssertEqual(changes, [.init(field: "date_modified", ascending: true), .init(field: "date_modified", ascending: false)])
    }

    @MainActor func testHeaderAcceptsTheClickThatActivatesTheWindow() throws {
        _ = NSApplication.shared
        let table = FileTableView()
        table.configureColumns()
        let header = try XCTUnwrap(table.headerView)
        XCTAssertTrue(header.acceptsFirstMouse(for: nil))
    }

    @MainActor func testUnrelatedUpdatePreservesHeaderAndExternalSortStillApplies() throws {
        _ = NSApplication.shared
        var currentSort = SearchSort()
        func view(font: Double) -> ResultsTable {
            ResultsTable(rows: [], fontSize: font, windowID: UUID(), applications: [], sort: Binding(get: { currentSort }, set: { currentSort = $0 }),
                         selection: { _ in }, perform: { _, _ in }, more: {})
        }
        let host = NSHostingView(rootView: view(font: 11.5))
        host.frame = .init(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        func findTable(_ root: NSView) -> FileTableView? {
            if let table = root as? FileTableView { return table }
            return root.subviews.lazy.compactMap(findTable).first
        }
        let table = try XCTUnwrap(findTable(host))
        table.sortDescriptors = [NSSortDescriptor(key: "size", ascending: true)]
        currentSort = .init(field: "size", ascending: true)
        // Unrelated invalidations read the same live model value.
        host.rootView = view(font: 12)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.sortDescriptors.first?.key, "size")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, true)
        currentSort = .init(field: "size", ascending: false)
        table.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        host.rootView = view(font: 13)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.sortDescriptors.first?.key, "size")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
        currentSort = .init(field: "path", ascending: false)
        host.rootView = view(font: 13)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.sortDescriptors.first?.key, "path")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
    }
}
