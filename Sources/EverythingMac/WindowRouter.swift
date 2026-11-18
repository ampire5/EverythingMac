import EverythingSearchUI
import AppKit
import SwiftUI

@MainActor final class WindowRouter {
    private struct Entry {
        weak var window: NSWindow?
        let closeObserver: NSObjectProtocol
        var receiveText: ((String) -> Void)?
        let closeDelegate: SearchWindowCloseDelegate
    }
    private var windows: [UUID: Entry] = [:]
    private var tabParents: [UUID: NSWindow] = [:]
    private var pendingQueries: [UUID: String] = [:]
    private var launchQuery: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var hasSearchWindow: Bool { windows.values.contains(where: { $0.window != nil }) }
    var openWindow: ((UUID) -> Void)? {
        didSet {
            if openWindow != nil, let text = launchQuery { launchQuery = nil; searchSelectedText(text) }
        }
    }
    var activeSearchID: UUID? {
        guard NSApp.modalWindow == nil, let key = NSApp.keyWindow, key.attachedSheet == nil else { return nil }
        return windows.first(where: { $0.value.window === key })?.key
    }
    func searchSelectedText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let available = windows.values.filter { $0.window != nil && $0.window?.attachedSheet == nil && $0.receiveText != nil }
        if let entry = available.first(where: { $0.window?.isKeyWindow == true }) ?? available.first,
           let window = entry.window, let receive = entry.receiveText {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            receive(text)
        } else if let openWindow {
            let id = UUID(); pendingQueries[id] = text; openWindow(id)
        } else { launchQuery = text }
    }
    func newWindow() { openWindow?(UUID()) }
    func newTab() {
        let id = UUID()
        let parent = NSApp.orderedWindows.first(where: { window in windows.values.contains(where: { $0.window === window }) })
            ?? windows.values.compactMap(\.window).first
        if let parent { tabParents[id] = parent }
        openWindow?(id)
    }
    func reopen() {
        let window = windows.values.compactMap(\.window).first(where: \.isKeyWindow)
            ?? windows.values.compactMap(\.window).first
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else { newWindow() }
    }
    func register(_ window: NSWindow, id: UUID, receiveText: ((String) -> Void)? = nil) {
        if windows[id]?.window === window {
            if let receiveText { windows[id]?.receiveText = receiveText }
            deliverPending(id)
            return
        }
        window.tabbingIdentifier = "NetworkEverything.Search"
        window.tabbingMode = .automatic
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove(id) }
        }
        let closeDelegate = SearchWindowCloseDelegate(original: window.delegate) { [weak self] window in
            guard let self, self.defaults.bool(forKey: MenuBarPreferences.closeToMenuBar),
                  self.windows.values.filter({ $0.window != nil }).count == 1,
                  window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            return true
        }
        window.delegate = closeDelegate
        windows[id] = Entry(window: window, closeObserver: observer, receiveText: receiveText, closeDelegate: closeDelegate)
        if let parent = tabParents.removeValue(forKey: id), parent !== window {
            parent.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
        deliverPending(id)
    }
    private func deliverPending(_ id: UUID) {
        guard let receive = windows[id]?.receiveText, let text = pendingQueries.removeValue(forKey: id) else { return }
        windows[id]?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        receive(text)
    }
    private func remove(_ id: UUID) {
        pendingQueries.removeValue(forKey: id)
        if let entry = windows.removeValue(forKey: id) { NotificationCenter.default.removeObserver(entry.closeObserver) }
    }
    isolated deinit { for entry in windows.values { NotificationCenter.default.removeObserver(entry.closeObserver) } }
}
struct SearchWindowBridge: NSViewRepresentable {
    let id: UUID
    let router: WindowRouter
    let title: String
    let ready: (NSWindow) -> Void
    func makeNSView(context: Context) -> Host {
        let view = Host()
        view.attach = { window in router.register(window, id: id); ready(window) }
        return view
    }
    func updateNSView(_ view: Host, context: Context) {
        view.attach = { window in router.register(window, id: id); ready(window) }
        if let window = view.window { window.title = title; view.attach?(window) }
    }
    final class Host: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { attach?(window) } }
    }
}
struct SearchCommands: Commands {
    @FocusedObject private var session: SearchSession?
    @Environment(\.openWindow) private var openWindow
    @AppStorage("Results.fontSize") private var resultsFontSize = 11.5
    let router: WindowRouter
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Новое окно") { openWindow(value: UUID()) }.keyboardShortcut("n")
            Button("Новая вкладка") { router.newTab() }.keyboardShortcut("t")
        }
        CommandGroup(after: .newItem) {
            Button("Найти") { session?.focusSearch() }.keyboardShortcut("f").disabled(session == nil)
            Button("Предыдущий поиск") { session?.goBack() }.keyboardShortcut("[").disabled(!(session?.history.canGoBack ?? false))
            Button("Следующий поиск") { session?.goForward() }.keyboardShortcut("]").disabled(!(session?.history.canGoForward ?? false))
            Button("Повторить поиск") { session?.refresh() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(session == nil)
            Button("Сохранить запрос…") { session?.beginSaveQuery() }.keyboardShortcut("d").disabled(session == nil)
            Divider()
            Button("Открыть выбранное") { session?.perform("open") }.keyboardShortcut("o").disabled(session?.selected.isEmpty ?? true)
            Button("Открыть выбранное в…") { session?.chooseApplication() }.disabled(session?.selected.isEmpty ?? true)
            Button("Показать в Finder") { session?.perform("reveal") }.keyboardShortcut("r").disabled(session?.selected.isEmpty ?? true)
            Button("Искать в этой папке") { session?.perform("searchInFolder") }.disabled(session?.selected.count != 1)
            Button("Копировать Windows-пути") { session?.perform("copyWindows") }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(session?.selected.isEmpty ?? true)
            Divider()
            Button("Удалить выбранное…", role: .destructive) { session?.perform("delete") }
                .disabled((session?.selected.isEmpty ?? true) || session?.deletion.working == true)
        }
        CommandGroup(after: .sidebar) {
            Picker("Размер текста результатов", selection: $resultsFontSize) {
                Text("Компактный (11,5)").tag(11.5)
                Text("Обычный (12)").tag(12.0)
                Text("Крупный (13)").tag(13.0)
            }

            Button("Превью файла") { session?.preview.toggle() }.keyboardShortcut(.rightArrow, modifiers: [.control, .command]).disabled(session == nil)
        }
    }
}
