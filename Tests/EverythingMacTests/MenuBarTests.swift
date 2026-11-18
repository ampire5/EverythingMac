import XCTest
import AppKit
@testable import EverythingMac

final class MenuBarTests: XCTestCase {
    @MainActor func testSingleClickShowsSearchImmediatelyAndRightClickOpensMenu() {
        _ = NSApplication.shared
        let router = WindowRouter()
        var creations = 0, menus = 0
        router.openWindow = { _ in creations += 1 }
        let controller = MenuBarController(router: router, presentMenu: { _, _ in menus += 1 })
        controller.handleClick()
        XCTAssertEqual(creations, 1, "Showing search must not wait for the double-click interval")
        XCTAssertEqual(menus, 0)
        controller.handleClick(right: true)
        XCTAssertEqual(menus, 1)
        XCTAssertEqual(creations, 1)
    }
    @MainActor func testTwoButtonActionsStillFormDoubleClickWhenNativeCountIsMissing() async throws {
        _ = NSApplication.shared
        let suite = "MenuBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("window", forKey: MenuBarPreferences.doubleClickAction)
        let router = WindowRouter(defaults: defaults)
        let existing = makeSearchWindow(router)
        defer { existing.close() }
        var creations = 0, menus = 0
        router.openWindow = { _ in creations += 1 }
        let controller = MenuBarController(router: router, defaults: defaults, doubleClickInterval: .milliseconds(30), presentMenu: { _, _ in menus += 1 })
        controller.handleClick()
        XCTAssertEqual(creations, 0)
        controller.handleClick()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(menus, 0)
    }
    @MainActor func testButtonActionWithoutMouseEventStillShowsSearch() async throws {
        _ = NSApplication.shared
        let router = WindowRouter()
        var menus = 0, creations = 0
        router.openWindow = { _ in creations += 1 }
        let controller = MenuBarController(router: router, doubleClickInterval: .milliseconds(10), presentMenu: { _, _ in menus += 1 })
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("clicked:"), to: controller, from: nil))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(menus, 0)
        XCTAssertEqual(creations, 1)
    }
    @MainActor func testCloseDelegationPreservesOriginalVetoAndNotification() {
        final class Original: NSObject, NSWindowDelegate {
            var allowClose = false
            var notified = false
            func windowShouldClose(_ sender: NSWindow) -> Bool { allowClose }
            func windowWillClose(_ notification: Notification) { notified = true }
        }
        _ = NSApplication.shared
        let suite = "MenuBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = WindowRouter(defaults: defaults)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let original = Original()
        window.delegate = original
        router.register(window, id: UUID())
        window.makeKeyAndOrderFront(nil)
        window.performClose(nil)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(original.notified)
        original.allowClose = true
        window.performClose(nil)
        XCTAssertTrue(original.notified)
    }
    @MainActor func testNewTabUsesExistingSearchWhenAnotherWindowIsKey() {
        _ = NSApplication.shared
        let router = WindowRouter()
        let makeWindow = { NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false) }
        let search = makeWindow(), settings = makeWindow(), new = makeWindow()
        for window in [search, settings, new] { window.isReleasedWhenClosed = false }
        defer { for window in [new, search, settings] { window.close() } }
        router.register(search, id: UUID())
        settings.makeKeyAndOrderFront(nil)
        var newID: UUID?
        router.openWindow = { newID = $0 }
        router.newTab()
        router.register(new, id: newID!)
        XCTAssertTrue(search.tabbedWindows?.contains(where: { $0 === new }) == true)
        XCTAssertNil(settings.tabbedWindows)
    }
    @MainActor func testClosingLastSearchHidesItAndReopenPreservesWindow() throws {
        _ = NSApplication.shared
        let suite = "MenuBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: MenuBarPreferences.closeToMenuBar)
        let router = WindowRouter(defaults: defaults)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        router.register(window, id: UUID())
        window.makeKeyAndOrderFront(nil)
        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertNotNil(window.contentView)
        var creations = 0
        router.openWindow = { _ in creations += 1 }
        router.reopen()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(creations, 0)
    }
    @MainActor func testOtherWindowsCloseNormallyAndDisabledOptionReleasesLast() {
        _ = NSApplication.shared
        let suite = "MenuBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: MenuBarPreferences.closeToMenuBar)
        let router = WindowRouter(defaults: defaults)
        let windows = (0..<2).map { _ in NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false) }
        for window in windows { window.isReleasedWhenClosed = false; router.register(window, id: UUID()) }
        windows[0].performClose(nil)
        defaults.set(false, forKey: MenuBarPreferences.closeToMenuBar)
        windows[1].performClose(nil)
        var creations = 0
        router.openWindow = { _ in creations += 1 }
        router.reopen()
        XCTAssertEqual(creations, 1)
    }
    @MainActor func testDoubleClickCreatesOneNewSearchWithoutOpeningMenu() async throws {
        _ = NSApplication.shared
        let suite = "MenuBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("window", forKey: MenuBarPreferences.doubleClickAction)
        let router = WindowRouter(defaults: defaults)
        let existing = makeSearchWindow(router)
        defer { existing.close() }
        var creations = 0, menus = 0
        router.openWindow = { _ in creations += 1 }
        let controller = MenuBarController(router: router, defaults: defaults, doubleClickInterval: .milliseconds(20), presentMenu: { _, _ in menus += 1 })
        controller.handleClick()
        controller.handleClick()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(menus, 0)
        controller.handleClick(right: true)
        XCTAssertEqual(menus, 1)
    }
    @MainActor private func makeSearchWindow(_ router: WindowRouter) -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        router.register(window, id: UUID())
        return window
    }
    @MainActor func testDoubleClickReusesHiddenParentAndLastTabHidesAgain() {
        _ = NSApplication.shared
        let suite = "MenuBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: MenuBarPreferences.closeToMenuBar)
        let router = WindowRouter(defaults: defaults)
        let existing = makeSearchWindow(router)
        existing.title = "Retained search"
        existing.orderOut(nil)
        var newID: UUID?
        router.openWindow = { newID = $0 }
        let controller = MenuBarController(router: router, defaults: defaults, presentMenu: { _, _ in })
        controller.handleClick()
        XCTAssertTrue(existing.isVisible)
        XCTAssertNil(newID)
        controller.handleClick()
        let new = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        new.isReleasedWhenClosed = false
        defer { new.close(); existing.close() }
        router.register(new, id: newID!)
        XCTAssertTrue(existing.tabbedWindows?.contains(where: { $0 === new }) == true)
        new.performClose(nil)
        existing.performClose(nil)
        XCTAssertFalse(existing.isVisible)
        router.reopen()
        XCTAssertTrue(existing.isVisible)
        XCTAssertEqual(existing.title, "Retained search")
    }
}
