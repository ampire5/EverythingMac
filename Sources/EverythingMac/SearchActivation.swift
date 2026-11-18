import EverythingSearchUI
import AppKit

struct ClipboardReturnPolicy {
    private var countWhenLeaving: Int?
    mutating func left(changeCount: Int) { countWhenLeaving = changeCount }
    mutating func returned(changeCount: Int, enabled: Bool, eligible: Bool) -> Bool {
        defer { countWhenLeaving = nil }
        guard enabled, eligible, let previous = countWhenLeaving else { return false }
        return previous != changeCount
    }
}

@MainActor final class SearchActivationController {
    static let preferenceKey = "Search.focusAfterClipboardChange"
    private let router: WindowRouter
    private var policy = ClipboardReturnPolicy()
    private var observers: [NSObjectProtocol] = []
    init(router: WindowRouter) {
        self.router = router
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.policy.left(changeCount: NSPasteboard.general.changeCount) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let target = self.router.activeSearchID
                let shouldFocus = self.policy.returned(changeCount: NSPasteboard.general.changeCount,
                    enabled: UserDefaults.standard.bool(forKey: Self.preferenceKey), eligible: target != nil)
                if shouldFocus, let target {
                    // Finish native window activation first, then recheck sheets and the key scene.
                    DispatchQueue.main.async { [weak self] in
                        guard NSApp.isActive, self?.router.activeSearchID == target else { return }
                        NotificationCenter.default.post(name: .focusSearch, object: target)
                    }
                }
            }
        })
    }
    isolated deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}

@MainActor final class SearchServiceProvider: NSObject {
    private let router: WindowRouter
    init(router: WindowRouter) { self.router = router }
    @objc func searchInEverything(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        router.searchSelectedText(text)
    }
}
