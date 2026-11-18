import XCTest
import AppKit
@testable import EverythingMac

final class SearchActivationTests: XCTestCase {
    func testReturnOnlyFocusesAfterClipboardChangedWhileAway() {
        var policy = ClipboardReturnPolicy()
        XCTAssertFalse(policy.returned(changeCount: 10, enabled: true, eligible: true))
        policy.left(changeCount: 10)
        XCTAssertFalse(policy.returned(changeCount: 10, enabled: true, eligible: true))
        policy.left(changeCount: 10)
        XCTAssertTrue(policy.returned(changeCount: 11, enabled: true, eligible: true))
        XCTAssertFalse(policy.returned(changeCount: 11, enabled: true, eligible: true))
        policy.left(changeCount: 11)
        XCTAssertFalse(policy.returned(changeCount: 12, enabled: true, eligible: false))
        policy.left(changeCount: 12)
        XCTAssertFalse(policy.returned(changeCount: 13, enabled: false, eligible: true))
    }
    @MainActor func testServiceWaitsForNewSceneAndDeliversOnlyToItsWindow() {
        _ = NSApplication.shared
        let router = WindowRouter()
        var created: UUID?
        router.openWindow = { created = $0 }
        router.searchSelectedText("Example")
        let id = created!
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var received: [String] = []
        router.register(window, id: id, receiveText: { received.append($0) })
        router.register(window, id: id, receiveText: { received.append($0) })
        XCTAssertEqual(received, ["Example"])
    }
    @MainActor func testServiceAcceptsSelectionWithoutChangingPasteboardAndIgnoresBlankText() {
        let router = WindowRouter()
        var creations = 0
        router.openWindow = { _ in creations += 1 }
        let service = SearchServiceProvider(router: router)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(" \n ", forType: .string)
        var error: NSString?
        service.searchInEverything(board, userData: nil, error: &error)
        XCTAssertEqual(creations, 0)
        board.clearContents(); board.setString("Example", forType: .string)
        let count = board.changeCount
        service.searchInEverything(board, userData: nil, error: &error)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(board.string(forType: .string), "Example")
        XCTAssertNil(error)
    }
}
