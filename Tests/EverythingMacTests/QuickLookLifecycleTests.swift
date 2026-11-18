import XCTest
import AppKit
import SwiftUI
import Quartz
@testable import EverythingMac
@testable import EverythingSearchUI

final class QuickLookLifecycleTests: XCTestCase {
    @MainActor func testUnmountedPreviewCanBeFinishedWithoutActivatingQuickLook() {
        _ = NSApplication.shared
        let host = LocalQuickLook.makePreviewView()
        XCTAssertTrue(host.subviews.isEmpty)
        host.finish()
        host.finish()
        host.setItem(URL(fileURLWithPath: "/tmp/unused-quicklook.txt"))
        XCTAssertTrue(host.subviews.isEmpty)
    }
    @MainActor func testClosingInactiveTabThenDismantlingPreviewIsSafeAndIdempotent() throws {
        _ = NSApplication.shared
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Neutral Quick Look lifecycle fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let preview = LocalQuickLook.makePreviewView()
        preview.setItem(fixture)
        let background = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let foreground = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        background.isReleasedWhenClosed = false; foreground.isReleasedWhenClosed = false
        background.contentView = preview
        let quickLook = try XCTUnwrap(preview.subviews.compactMap { $0 as? QLPreviewView }.first)
        XCTAssertFalse(quickLook.shouldCloseWithWindow)
        background.addTabbedWindow(foreground, ordered: .above)
        // No user window or media is used. The closing window is not key.
        XCTAssertFalse(background.isKeyWindow)
        background.close()
        LocalQuickLook.dismantleNSView(preview, coordinator: ())
        LocalQuickLook.dismantleNSView(preview, coordinator: ())
        background.contentView = nil
        foreground.close()
    }
    @MainActor func testSwiftUIHostingTreeCanTearDownAfterInactiveTabCloses() throws {
        _ = NSApplication.shared
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Neutral inactive-tab Quick Look fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        for _ in 0..<3 {
            autoreleasepool {
                let background = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
                let foreground = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
                background.isReleasedWhenClosed = false; foreground.isReleasedWhenClosed = false
                var hosting: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(LocalQuickLook(url: fixture)))
                background.contentView = hosting
                background.addTabbedWindow(foreground, ordered: .above)
                hosting?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                XCTAssertFalse(background.isKeyWindow)
                background.close()
                hosting?.rootView = AnyView(EmptyView())
                hosting?.layoutSubtreeIfNeeded()
                background.contentView = nil
                hosting = nil
                foreground.close()
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
    }
    @MainActor func testDetachedPreviewIsRecreatedForNewWindow() throws {
        _ = NSApplication.shared
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Neutral reattachment fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let host = LocalQuickLook.makePreviewView()
        host.setItem(fixture)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let first = try XCTUnwrap(host.subviews.compactMap { $0 as? QLPreviewView }.first)
        window.contentView = nil
        XCTAssertTrue(host.subviews.isEmpty)
        window.contentView = host
        let next = try XCTUnwrap(host.subviews.compactMap { $0 as? QLPreviewView }.first)
        XCTAssertFalse(first === next)
        XCTAssertEqual((next.previewItem as? NSURL) as URL?, fixture)
        host.finish()
        host.setItem(fixture)
        XCTAssertTrue(host.subviews.isEmpty)
        window.close()
    }

}
