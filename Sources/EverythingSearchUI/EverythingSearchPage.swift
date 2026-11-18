import AppKit
import EverythingCore
import SwiftUI

/// The host supplies connection data and receives the verified local URL on an explicit Open action.
public struct EverythingConnection: Sendable {
    public let server: String
    public let login: String
    public let password: String
    public let mappings: [PathMapping]

    public init(server: String, login: String, password: String, mappings: [PathMapping] = []) {
        self.server = server
        self.login = login
        self.password = password
        self.mappings = mappings
    }
}

@MainActor private final class PageState: ObservableObject {
    @Published var active = false
}

@MainActor private final class PageConnection {
    let load: @MainActor () async throws -> EverythingConnection
    var current: EverythingConnection?

    init(load: @escaping @MainActor () async throws -> EverythingConnection) { self.load = load }

    func connection() async throws -> EverythingConnection {
        if let current { return current }
        let value = try await load()
        try Task.checkCancellation()
        current = value
        return value
    }
}

private struct EmbeddedSearchContent: View {
    let session: SearchSession
    @ObservedObject var state: PageState

    var body: some View {
        SearchContent(session: session, standalone: false, active: state.active)
    }
}

/// A retained, per-window search page for an AppKit host. Hiding the page pauses requests.
@MainActor public final class EverythingSearchPage: NSView {
    let session: SearchSession
    private let state = PageState()

    public convenience init(loadConnection: @escaping @MainActor () async throws -> EverythingConnection,
                            open: @escaping @MainActor (URL, Bool) -> Void) {
        self.init(loadConnection: loadConnection, preferences: .application, open: open)
    }

    init(loadConnection: @escaping @MainActor () async throws -> EverythingConnection,
         preferences: EmbeddedSearchPreferences,
         open: @escaping @MainActor (URL, Bool) -> Void) {
        let connection = PageConnection(load: loadConnection)
        let api = EverythingAPI()
        let model = SearchModel { query, sort, offset in
            let value = try await connection.connection()
            return try await api.search(server: value.server, login: value.login, password: value.password,
                                        query: query, sort: sort, offset: offset)
        }
        session = SearchSession(id: UUID(), library: preferences.library, standalone: false, model: model,
                                mappings: { connection.current?.mappings ?? [] })
        super.init(frame: .zero)
        session.embeddedPreferences = preferences
        session.actions.openResult = open
        session.setActive(false)

        let content = NSHostingView(rootView: EmbeddedSearchContent(session: session, state: state))
        content.sizingOptions = []
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public required init?(coder: NSCoder) { nil }

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in
            guard let self, state.active, window?.firstResponder === self else { return }
            session.focusSearch()
        }
        return true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        session.window = window
        updateActivity()
    }

    public override func viewDidHide() { super.viewDidHide(); updateActivity() }
    public override func viewDidUnhide() { super.viewDidUnhide(); updateActivity() }

    public var containsKeyboardFocus: Bool {
        if let field = window?.firstResponder as? NSTextView, field.isFieldEditor {
            return (field.delegate as? NSView)?.isDescendant(of: self) == true
        }
        return (window?.firstResponder as? NSView)?.isDescendant(of: self) == true
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard state.active, containsKeyboardFocus, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "f": session.focusSearch()
        case "o" where window?.firstResponder is FileTableView: session.perform("open")
        case "r" where window?.firstResponder is FileTableView: session.perform("reveal")
        case "[": session.goBack()
        case "]": session.goForward()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func updateActivity() {
        let active = window != nil && !isHiddenOrHasHiddenAncestor
        guard state.active != active else { return }
        if !active {
            session.setActive(false)
        }
        state.active = active
    }
}
