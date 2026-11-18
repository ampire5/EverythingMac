import XCTest
import AppKit
@testable import EverythingMac
@testable import EverythingSearchUI

final class WindowTests: XCTestCase {
    @MainActor func testReopenCreatesSearchEvenWhenOnlySettingsRemains() {
        let router = WindowRouter()
        var opened: [UUID] = []
        router.openWindow = { opened.append($0) }
        router.reopen()
        router.reopen()
        XCTAssertEqual(opened.count, 2)
        XCTAssertNotEqual(opened[0], opened[1])
    }
    @MainActor func testClosingSearchWindowDoesNotReopenSettingsInstead() {
        _ = NSApplication.shared
        let router = WindowRouter()
        let search = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let settings = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        search.isReleasedWhenClosed = false; settings.isReleasedWhenClosed = false
        defer { settings.close() }
        var opened = 0
        router.openWindow = { _ in opened += 1 }
        router.register(search, id: UUID())
        search.close()
        router.reopen()
        XCTAssertEqual(opened, 1, "Closing a search scene must create a new search, irrespective of Settings")
        XCTAssertFalse(settings.isVisible, "The router must not reveal an unrelated Settings window")
    }
    @MainActor func testPreviewKeyboardRevealWaitsForPointerEntryThenHidesAfterGrace() {
        var policy = PreviewHoverPolicy()
        policy.show()
        XCTAssertFalse(policy.shouldHide(inside: false, inOvershoot: false, held: false, now: 1))
        XCTAssertFalse(policy.shouldHide(inside: true, inOvershoot: false, held: false, now: 2))
        XCTAssertFalse(policy.shouldHide(inside: false, inOvershoot: false, held: false, now: 3))
        XCTAssertFalse(policy.shouldHide(inside: false, inOvershoot: false, held: false, now: 3.1))
        XCTAssertTrue(policy.shouldHide(inside: false, inOvershoot: false, held: false, now: 3.16))
    }
    @MainActor func testPreviewStaysDuringOvershootAndInteraction() {
        var policy = PreviewHoverPolicy()
        policy.show()
        _ = policy.shouldHide(inside: true, inOvershoot: false, held: false, now: 0)
        XCTAssertFalse(policy.shouldHide(inside: false, inOvershoot: true, held: false, now: 1))
        XCTAssertFalse(policy.shouldHide(inside: false, inOvershoot: false, held: true, now: 2))
        XCTAssertFalse(policy.shouldHide(inside: false, inOvershoot: false, held: false, now: 3))
        XCTAssertTrue(policy.shouldHide(inside: false, inOvershoot: false, held: false, now: 3.2))
    }
    func testPreviewEdgeHintFollowsPointerWithinResultsArea() throws {
        let frame = CGRect(x: 0, y: 88, width: 780, height: 320)
        let upper = try XCTUnwrap(PreviewEdgeHint(point: CGPoint(x: 780, y: 90), in: frame))
        XCTAssertEqual(upper.y, 24)
        XCTAssertEqual(upper.opacity, 1)
        let middle = try XCTUnwrap(PreviewEdgeHint(point: CGPoint(x: 705, y: 200), in: frame))
        XCTAssertEqual(middle.y, 112)
        XCTAssertEqual(middle.opacity, 0.25)
        let lower = try XCTUnwrap(PreviewEdgeHint(point: CGPoint(x: 779, y: 407), in: frame))
        XCTAssertEqual(lower.y, 296)
        XCTAssertNil(PreviewEdgeHint(point: CGPoint(x: 780, y: 87), in: frame))
        XCTAssertNil(PreviewEdgeHint(point: CGPoint(x: 630, y: 200), in: frame))
        XCTAssertNil(PreviewEdgeHint(point: CGPoint(x: 781, y: 200), in: frame))
    }
}
