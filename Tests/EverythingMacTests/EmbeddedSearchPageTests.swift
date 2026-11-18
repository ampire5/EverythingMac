import AppKit
import XCTest
import EverythingCore
@testable import EverythingSearchUI

final class EmbeddedSearchPageTests: XCTestCase {
    @MainActor func testReopenedPageRestoresLastSearchAndFavorite() async throws {
        _ = NSApplication.shared
        let load: @MainActor () async throws -> EverythingConnection = { throw CocoaError(.fileReadNoSuchFile) }
        let suiteName = "EverythingSearchUI.EmbeddedTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = EmbeddedSearchPreferences(defaults: defaults)
        let page = EverythingSearchPage(loadConnection: load, preferences: preferences, open: { _, _ in })
        let firstWindow = makeWindow(for: page)
        defer { firstWindow.close() }
        try await waitForSearch(on: page)

        page.session.editQuery("embedded persistence example")
        page.session.setSort(.init(field: "size", ascending: false))
        page.session.setScope(.init(kind: .video, folder: "C:\\Examples"))
        page.session.bookmarkName = "Persistence example"
        page.session.saveQuery()

        try page.session.library.recordQuery(page.session.state.query, sort: page.session.state.sort,
                                             scope: page.session.state.scope)
        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reloadedPreferences = EmbeddedSearchPreferences(defaults: reloadedDefaults)
        let reopened = EverythingSearchPage(loadConnection: load, preferences: reloadedPreferences, open: { _, _ in })
        let nextWindow = makeWindow(for: reopened)
        defer { nextWindow.close() }
        try await waitForSearch(on: reopened)

        XCTAssertEqual(reopened.session.state, page.session.state)
        XCTAssertEqual(reopened.session.library.state.savedQueries.first(where: { $0.name == "Persistence example" })?.query,
                       "embedded persistence example")
        XCTAssertEqual(reopened.session.library.state.recentQueries.first?.scope, page.session.state.scope)
    }

    @MainActor private func makeWindow(for page: EverythingSearchPage) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        page.frame = window.contentLayoutRect
        window.contentView = page
        window.displayIfNeeded()
        return window
    }

    @MainActor private func waitForSearch(on page: EverythingSearchPage) async throws {
        for _ in 0..<100 where page.session.model.error == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(page.session.model.error)
    }

    @MainActor func testConnectionLoadsOnFirstVisitOnly() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let suiteName = "EverythingSearchUI.EmbeddedTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var loadCount = 0
        let page = EverythingSearchPage(loadConnection: {
            loadCount += 1
            throw CocoaError(.fileReadNoSuchFile)
        }, preferences: EmbeddedSearchPreferences(defaults: defaults), open: { _, _ in XCTFail("Opening the page must not open a file") })
        page.isHidden = true
        let container = NSView(frame: window.contentLayoutRect)
        page.frame = container.bounds
        container.addSubview(page)
        window.contentView = container

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(loadCount, 0)

        page.isHidden = false
        window.displayIfNeeded()
        for _ in 0..<100 where loadCount == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(loadCount, 1)

        page.isHidden = true
        page.isHidden = false
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(loadCount, 1)
    }
}
