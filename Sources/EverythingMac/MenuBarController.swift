import EverythingSearchUI
import AppKit

enum MenuBarPreferences {
    static let closeToMenuBar = "Window.closeToMenuBar"
    static let doubleClickAction = "MenuBar.doubleClickAction"
}

@MainActor final class MenuBarController: NSObject {
    private let router: WindowRouter
    private let defaults: UserDefaults
    private let item: NSStatusItem
    private let doubleClickInterval: Duration
    private let presentMenu: @MainActor (NSMenu, NSStatusBarButton) -> Void
    private var lastClick: ContinuousClock.Instant?
    private var lastClickCreatedWindow = false
    init(router: WindowRouter, defaults: UserDefaults = .standard,
         doubleClickInterval: Duration = .seconds(NSEvent.doubleClickInterval),
         presentMenu: @escaping @MainActor (NSMenu, NSStatusBarButton) -> Void = { menu, button in
             button.highlight(true)
             defer { button.highlight(false) }
             menu.popUp(positioning: nil, at: .init(x: 0, y: button.bounds.maxY + 4), in: button)
         }) {
        self.router = router; self.defaults = defaults; self.doubleClickInterval = doubleClickInterval; self.presentMenu = presentMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Network Everything")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Network Everything — двойной щелчок: новый поиск"
            button.setAccessibilityLabel("Network Everything")
            button.target = self; button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    @objc private func clicked(_ sender: Any?) {
        // Status-item target/action delivery does not guarantee currentEvent is
        // the originating mouse event. Never read its clickCount here.
        handleClick(right: NSApp.currentEvent?.type == .rightMouseUp)
    }
    func handleClick(right: Bool = false) {
        let now = ContinuousClock.now
        let double = lastClick.map { now - $0 < doubleClickInterval } ?? false
        if right { lastClick = nil; showMenu(); return }
        if double {
            lastClick = nil
            // If the first click had to create a search, it already fulfils
            // the double-click request; do not create two empty scenes.
            guard !lastClickCreatedWindow else { return }
            if defaults.string(forKey: MenuBarPreferences.doubleClickAction) == "window" { newWindow() }
            else { newTab() }
        } else {
            lastClick = now
            lastClickCreatedWindow = !router.hasSearchWindow
            showSearch()
        }
    }
    private func showMenu() {
        guard let button = item.button else { return }
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self; menu.addItem(item)
        }
        add("Показать поиск", #selector(showSearch))
        add("Новая вкладка", #selector(newTab))
        add("Новое окно", #selector(newWindow))
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "При закрытии оставлять в строке меню", action: #selector(toggleClose), keyEquivalent: "")
        closeItem.target = self
        closeItem.state = defaults.bool(forKey: MenuBarPreferences.closeToMenuBar) ? .on : .off
        menu.addItem(closeItem)
        menu.addItem(.separator())
        add("Завершить Network Everything", #selector(quit), key: "q")
        presentMenu(menu, button)
    }
    @objc private func showSearch() {
        router.reopen(); NSApp.activate(ignoringOtherApps: true)
        if let id = router.activeSearchID { NotificationCenter.default.post(name: .focusSearch, object: id) }
    }
    @objc private func newWindow() { router.newWindow(); NSApp.activate(ignoringOtherApps: true) }
    @objc private func newTab() {
        router.newTab(); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleClose() { defaults.set(!defaults.bool(forKey: MenuBarPreferences.closeToMenuBar), forKey: MenuBarPreferences.closeToMenuBar) }
    @objc private func quit() { NSApp.terminate(nil) }
    isolated deinit { NSStatusBar.system.removeStatusItem(item) }
}

// Keep SwiftUI's delegate in the forwarding chain for native tabs and scene disposal.
nonisolated final class SearchWindowCloseDelegate: NSObject, NSWindowDelegate {
    let original: (any NSWindowDelegate)?
    private let hide: @MainActor (NSWindow) -> Bool
    init(original: (any NSWindowDelegate)?, hide: @escaping @MainActor (NSWindow) -> Bool) {
        self.original = original; self.hide = hide
    }
    @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
        if hide(sender) { sender.orderOut(nil); return false }
        return original?.windowShouldClose?(sender) ?? true
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}
