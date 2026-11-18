import XCTest
import AppKit
import SwiftUI
@testable import EverythingMac
@testable import EverythingSearchUI

final class SearchFocusTests: XCTestCase {
    @MainActor func testFocusRequestSelectsLatestBoundTextBeforeSwiftUIRenders() throws {
        _ = NSApplication.shared
        let id = UUID()
        var query = "old"
        let host = NSHostingView(rootView: NativeSearchField(text: Binding(get: { query }, set: { query = $0 }), windowID: id))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func find(_ v: NSView) -> NSSearchField? { (v as? NSSearchField) ?? v.subviews.lazy.compactMap(find).first }
        let field = try XCTUnwrap(find(host))
        query = "new selected text"
        NotificationCenter.default.post(name: .focusSearch, object: id)
        XCTAssertEqual(field.stringValue, "new selected text")
        let editor = try XCTUnwrap(field.currentEditor())
        XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 17))
        editor.insertText("replacement")
        XCTAssertEqual(field.stringValue, "replacement")
    }
}
