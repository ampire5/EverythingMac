import Foundation
import EverythingCore

struct SearchState: Codable, Equatable {
    var query = ""
    var sort = SearchSort()
    var scope = SearchScope()
}
struct TableLocation: Equatable {
    var topID: String? = nil
    var offset = 0.0
    var fallbackRow = 0
    var selectedIDs: Set<String> = []
    var loadedCount = 0
}
struct SearchHistoryEntry: Equatable {
    var state: SearchState
    var location = TableLocation()
}
struct TableRestoration: Equatable {
    var id = UUID()
    var location: TableLocation
}

package struct SearchHistory {
    private var entries: [SearchHistoryEntry]
    private var index = 0
    private var draft: SearchHistoryEntry?
    init(initial: SearchState = .init()) { entries = [.init(state: initial)] }
    var current: SearchHistoryEntry { draft ?? entries[index] }
    package var canGoBack: Bool { draft != nil || index > 0 }
    package var canGoForward: Bool { draft == nil && index + 1 < entries.count }
    mutating func edit(_ state: SearchState) {
        if state == entries[index].state { draft = nil }
        else { draft = .init(state: state) }
    }
    mutating func updateLocation(_ location: TableLocation) {
        if draft != nil { draft?.location = location }
        else { entries[index].location = location }
    }
    mutating func commit() {
        guard let draft else { return }
        self.draft = nil
        entries = Array(entries.prefix(index + 1))
        entries.append(draft); index += 1
        if entries.count > 100 { entries.removeFirst(); index -= 1 }
    }
    mutating func transition(to state: SearchState) {
        commit()
        guard current.state != state else { return }
        edit(state); commit()
    }
    mutating func back() -> SearchHistoryEntry? {
        commit()
        guard index > 0 else { return nil }
        index -= 1; return current
    }
    mutating func forward() -> SearchHistoryEntry? {
        guard canGoForward else { return nil }
        index += 1; return current
    }
}
