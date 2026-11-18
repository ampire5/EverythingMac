import XCTest
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class SearchHistoryTests: XCTestCase {
    func testTypingCoalescesAndBackRestoresPreviousSearchLocation() {
        var history = SearchHistory(initial: .init(query: "first"))
        history.updateLocation(.init(topID: "row", offset: 7, fallbackRow: 12, selectedIDs: ["selected"], loadedCount: 400))
        history.edit(.init(query: "s")); history.edit(.init(query: "second"))
        let back = history.back()
        XCTAssertEqual(back?.state.query, "first")
        XCTAssertEqual(back?.location.topID, "row")
        XCTAssertEqual(back?.location.selectedIDs, ["selected"])
        XCTAssertEqual(history.forward()?.state.query, "second")
        XCTAssertFalse(history.canGoForward)
    }
    func testEditingAfterBackDropsForwardBranchAndScopeRestores() {
        var history = SearchHistory(initial: .init(query: "first"))
        history.transition(to: .init(query: "second", scope: .init(kind: .audio, folder: "C:\\Audio")))
        _ = history.back()
        history.edit(.init(query: "third"))
        history.commit()
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back()?.state.query, "first")
        XCTAssertEqual(history.forward()?.state.query, "third")
    }
    func testOldSavedQueriesDecodeWithoutScopeAndNewOnesKeepIt() throws {
        let old = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Example\",\"query\":\"cat\",\"sort\":{\"field\":\"name\",\"ascending\":true}}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(SavedQuery.self, from: old).scope, SearchScope())
        let saved = SavedQuery(name: "Example", query: "cat", sort: .init(), scope: .init(kind: .images, folder: "C:\\Pictures"))
        XCTAssertEqual(try JSONDecoder().decode(SavedQuery.self, from: JSONEncoder().encode(saved)).scope, saved.scope)
    }
}
