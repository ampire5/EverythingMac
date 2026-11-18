import AppKit
import SwiftUI
import EverythingCore
import EverythingSearchUI

@main enum Bootstrap {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--import-credentials"), args.indices.contains(index + 1) {
            do {
                // Import directly into Keychain. Never echo credentials or copy the source file.
                let data = try Data(contentsOf: URL(fileURLWithPath: args[index + 1]))
                struct Credentials: Decodable { let login: String; let password: String }
                let credentials = try JSONDecoder().decode(Credentials.self, from: data)
                try PasswordStore.save(credentials.password)
                print("Credentials imported into Keychain.")
                exit(0)
            } catch { fputs("Credential import failed. Check file access and Keychain.\n", stderr); exit(1) }
        }
        if args.contains("--check-connection") {
            let store = SettingsStore()
            Task { @MainActor in
                do {
                    if let error = store.storageError { throw NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                    let api = EverythingAPI()
                    let page = try await api.search(server: store.config.server, login: store.config.login, password: store.password, query: "ext:mp4", sort: .init(), offset: 0)
                    print("Connection OK; total: \(page.totalResults); decoded rows: \(page.results.count)")
                    exit(0)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NetworkEverythingApp.main()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let router = WindowRouter()
    private var activation: SearchActivationController?
    private var menuBar: MenuBarController?
    private lazy var serviceProvider = SearchServiceProvider(router: router)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        activation = SearchActivationController(router: router)
        menuBar = MenuBarController(router: router)
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        router.reopen()
        return false
    }
}
struct NetworkEverythingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = SettingsStore()
    @StateObject private var library = LibraryStore(fileURL: SettingsStore.fileURL.deletingLastPathComponent().appendingPathComponent("library.json"))
    var body: some Scene {
        WindowGroup("Network Everything", for: UUID.self) { $id in
            SearchWindow(id: id, store: store, library: library, router: delegate.router)
        } defaultValue: { UUID() }
        .defaultSize(width: 1060, height: 680)
        .commands { SearchCommands(router: delegate.router) }
        Settings { SettingsView(store: store) }
    }
}
struct SearchWindow: View {
    @StateObject private var session: SearchSession
    let router: WindowRouter
    @Environment(\.openWindow) private var openWindow
    init(id: UUID, store: SettingsStore, library: LibraryStore, router: WindowRouter) {
        self.router = router
        _session = StateObject(wrappedValue: SearchSession(id: id, store: store, library: library))
    }
    var body: some View {
        SearchContent(session: session, standalone: true)
            .focusedSceneObject(session)
            .background(SearchWindowBridge(id: session.id, router: router, title: session.model.query.isEmpty ? "Network Everything" : session.model.query) { window in
                session.window = window; session.preview.window = window
                router.register(window, id: session.id, receiveText: { [weak searchSession = session] in searchSession?.receiveSelectedText($0) })
            })
            .onAppear { router.openWindow = { id in openWindow(value: id) } }
    }
}

// Settings and Keychain remain owned by the standalone application.
extension SearchSession {
    convenience init(id: UUID, store: SettingsStore, library: LibraryStore, model: SearchModel? = nil) {
        let api = EverythingAPI()
        self.init(id: id, library: library, model: model ?? SearchModel { query, sort, offset in
            if let error = store.storageError {
                throw NSError(domain: "Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            let config = store.config
            return try await api.search(server: config.server, login: config.login, password: store.password,
                                        query: query, sort: sort, offset: offset)
        }, mappings: { store.config.mappings })
    }
}
