import XCTest
@testable import EverythingCore

final class SearchScopeTests: XCTestCase {
    func testUnfilteredSyntaxPassesThroughAndORCannotEscapeConstraints() {
        XCTAssertEqual(SearchScope().expression(for: "cat | dog"), "cat | dog")
        XCTAssertEqual(SearchScope(kind: .video, folder: "C:\\Clips").expression(for: "cat | dog"), "\"C:\\Clips\\\" video: <cat | dog>")
        XCTAssertEqual(SearchScope(folder: "\\\\server\\Share\\Folder\\").expression(for: ""), "\"\\\\server\\Share\\Folder\\\"")
    }
    @MainActor func testAtomicSearchUsesNewScopeAndSortInOneRequest() async throws {
        var requests: [(String, SearchSort)] = []
        let model = SearchModel(delay: 0) { query, sort, _ in
            requests.append((query, sort)); return SearchPage(totalResults: 0, results: [])
        }
        model.setSearch(query: "cat | dog", sort: .init(field: "size", ascending: false), scope: .init(kind: .images))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.0, "pic: <cat | dog>")
        XCTAssertEqual(requests.first?.1, .init(field: "size", ascending: false))
        XCTAssertEqual(model.query, "cat | dog")
    }
}
