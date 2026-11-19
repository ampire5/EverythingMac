import XCTest
@testable import EverythingCore

@MainActor private final class RetryState { var fail = true }

@MainActor private final class SortLoader {
    struct Request {
        let sort: SearchSort
        let offset: Int
        let continuation: CheckedContinuation<SearchPage, Error>
    }
    var completed = 0
    private var queued: [Request] = []
    private var waiter: CheckedContinuation<Request, Never>?
    func load(_ query: String, _ sort: SearchSort, _ offset: Int) async throws -> SearchPage {
        defer { completed += 1 }
        return try await withCheckedThrowingContinuation { continuation in
            let request = Request(sort: sort, offset: offset, continuation: continuation)
            if let waiter { self.waiter = nil; waiter.resume(returning: request) }
            else { queued.append(request) }
        }
    }
    func next() async -> Request {
        if !queued.isEmpty { return queued.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }
}

final class SearchTests: XCTestCase {
    @MainActor private func waitForCompletion(_ loader: SortLoader, count: Int) async {
        for _ in 0..<1000 {
            if loader.completed >= count { return }
            await Task.yield()
        }
        XCTFail("Search completion did not arrive")
    }
    @MainActor func testSortingKeepsCurrentPageUntilReplacementAndResetsPagination() async {
        let loader = SortLoader()
        let model = SearchModel(delay: 0, loader: loader.load)
        model.restart()
        let initial = await loader.next()
        initial.continuation.resume(returning: .init(totalResults: 4, results: [.init(name: "cat", path: "C:"), .init(name: "dog", path: "C:")]))
        await waitForCompletion(loader, count: 1)
        model.setSort(.init(field: "size", ascending: false))
        XCTAssertEqual(model.rows.map(\.name), ["cat", "dog"])
        XCTAssertEqual(model.total, 4)
        XCTAssertTrue(model.busy)
        model.loadMore() // Retained rows must not trigger old-order pagination while loading.
        let sorted = await loader.next()
        XCTAssertEqual(sorted.sort, .init(field: "size", ascending: false))
        XCTAssertEqual(sorted.offset, 0)
        sorted.continuation.resume(returning: .init(totalResults: 3, results: [.init(name: "dog", path: "C:"), .init(name: "cat", path: "C:")]))
        await waitForCompletion(loader, count: 2)
        XCTAssertEqual(model.rows.map(\.name), ["dog", "cat"])
        XCTAssertEqual(model.total, 3)
        model.loadMore()
        let next = await loader.next()
        XCTAssertEqual(next.offset, 2)
        XCTAssertEqual(next.sort, .init(field: "size", ascending: false))
        next.continuation.resume(throwing: SearchFailure.unavailable)
        await waitForCompletion(loader, count: 3)
        XCTAssertEqual(model.rows.map(\.name), ["dog", "cat"])
        XCTAssertNotNil(model.error)

        model.retry()
        let retry = await loader.next()
        XCTAssertEqual(retry.offset, 2)
        XCTAssertEqual(retry.sort, next.sort)
        retry.continuation.resume(returning: .init(totalResults: 3, results: [.init(name: "ball", path: "C:")]))
        await waitForCompletion(loader, count: 4)
        XCTAssertEqual(model.rows.map(\.name), ["dog", "cat", "ball"])
    }
    @MainActor func testLateSortResponseCannotReplaceRetainedOrNewerRows() async {
        let loader = SortLoader()
        let model = SearchModel(delay: 0, loader: loader.load)
        model.restart()
        let initial = await loader.next()
        initial.continuation.resume(returning: .init(totalResults: 1, results: [.init(name: "cat", path: "C:")]))
        await waitForCompletion(loader, count: 1)
        model.setSort(.init(field: "size", ascending: true))
        let old = await loader.next()
        model.setSort(.init(field: "size", ascending: false))
        let latest = await loader.next()
        XCTAssertEqual(model.rows.map(\.name), ["cat"])
        latest.continuation.resume(returning: .init(totalResults: 1, results: [.init(name: "dog", path: "C:")]))
        await waitForCompletion(loader, count: 2)
        old.continuation.resume(returning: .init(totalResults: 1, results: [.init(name: "ball", path: "C:")]))
        await waitForCompletion(loader, count: 3)
        XCTAssertEqual(model.rows.map(\.name), ["dog"])
        XCTAssertFalse(model.busy)
    }
    @MainActor func testSortFailureKeepsResultsWhileQueryChangeStillClearsThem() async {
        let loader = SortLoader()
        let model = SearchModel(delay: 0, loader: loader.load)
        model.restart()
        let initial = await loader.next()
        initial.continuation.resume(returning: .init(totalResults: 2, results: [.init(name: "cat", path: "C:")]))
        await waitForCompletion(loader, count: 1)
        model.setSort(.init(field: "size", ascending: false))
        let sorted = await loader.next()
        sorted.continuation.resume(throwing: SearchFailure.unauthorized)
        await waitForCompletion(loader, count: 2)
        XCTAssertEqual(model.rows.map(\.name), ["cat"])
        XCTAssertEqual(model.total, 2)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.busy)
        model.loadMore()
        XCTAssertFalse(model.busy, "Scrolling must leave a failed request available for explicit retry")
        XCTAssertNotNil(model.error)
        model.retry()
        XCTAssertEqual(model.rows.map(\.name), ["cat"])
        let retry = await loader.next()
        XCTAssertEqual(retry.sort, sorted.sort)
        XCTAssertEqual(retry.offset, 0)
        retry.continuation.resume(returning: .init(totalResults: 1, results: [.init(name: "dog", path: "C:")]))
        await waitForCompletion(loader, count: 3)
        XCTAssertEqual(model.rows.map(\.name), ["dog"])
        XCTAssertNil(model.error)
        model.query = "ball"
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.total, 0)
        let query = await loader.next()
        query.continuation.resume(returning: .init(totalResults: 0, results: []))
        await waitForCompletion(loader, count: 4)
    }
    @MainActor func testSuspendingPaginationPreservesRowsAndDiscardsLateResults() async {
        let loader = SortLoader()
        let model = SearchModel(delay: 0, loader: loader.load)
        model.restart()
        let first = await loader.next()
        first.continuation.resume(returning: .init(totalResults: 2, results: [.init(name: "cat", path: "C:")]))
        await waitForCompletion(loader, count: 1)

        model.loadMore()
        let interrupted = await loader.next()
        model.suspend()
        interrupted.continuation.resume(returning: .init(totalResults: 2, results: [.init(name: "old", path: "C:")]))
        await waitForCompletion(loader, count: 2)
        XCTAssertEqual(model.rows.map(\.name), ["cat"])
        XCTAssertFalse(model.busy)

        model.resume()
        let resumed = await loader.next()
        XCTAssertEqual(resumed.offset, 1)
        resumed.continuation.resume(returning: .init(totalResults: 2, results: [.init(name: "dog", path: "C:")]))
        await waitForCompletion(loader, count: 3)
        XCTAssertEqual(model.rows.map(\.name), ["cat", "dog"])
    }
    func testQueryIsNotInterpretedOrBrokenByURLCharacters() throws {
        let request = try EverythingAPI.request(server: "http://server.local:1980", login: "user", password: "test", query: "ext:mp4 cats & dogs #1 + 你好", sort: SearchSort(field: "size", ascending: false), offset: 200)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["search"], "ext:mp4 cats & dogs #1 + 你好")
        XCTAssertEqual(values["offset"], "200")
        XCTAssertEqual(values["sort"], "size")
        XCTAssertEqual(values["ascending"], "0")
        XCTAssertEqual(values["date_modified_column"], "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjp0ZXN0")
        XCTAssertLessThanOrEqual(request.timeoutInterval, 10)
    }
    func testRejectsCredentialsInServerURL() {
        XCTAssertThrowsError(try EverythingAPI.request(server: "http://user:pass@server/", login: "", password: "", query: "", sort: .init(), offset: 0))
        XCTAssertThrowsError(try EverythingAPI.request(server: "file:///tmp/file", login: "", password: "", query: "", sort: .init(), offset: 0))
    }
    func testHTTPFailuresAndMalformedResponses() {
        for status in [401, 403] {
            XCTAssertThrowsError(try EverythingAPI.decode(Data(), status: status)) { error in
                XCTAssertEqual(error as? SearchFailure, .unauthorized)
            }
        }
        XCTAssertThrowsError(try EverythingAPI.decode(Data("<html>login</html>".utf8), status: 200)) { error in
            XCTAssertEqual(error as? SearchFailure, .invalidResponse)
        }
        XCTAssertThrowsError(try EverythingAPI.decode(Data(), status: 503)) { error in
            XCTAssertEqual(error as? SearchFailure, .http(503))
        }
        XCTAssertThrowsError(try EverythingAPI.decode(Data(), status: 302)) { error in
            XCTAssertEqual(error as? SearchFailure, .redirected)
        }
    }
    @MainActor func testPaginationUsesServerOffsetsAndPreservesSelectionIdentity() async throws {
        var offsets: [Int] = []
        let model = SearchModel(delay: 0) { _, _, offset in
            offsets.append(offset)
            let names = offset == 0 ? ["cat", "dog"] : ["dog", "ball"]
            return SearchPage(totalResults: 4, results: names.map { .init(name: $0, path: "C:") })
        }
        model.restart()
        try await Task.sleep(nanoseconds: 20_000_000)
        model.loadMore()
        model.loadMore() // Only one page request may be in flight.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(offsets, [0, 2])
        XCTAssertEqual(model.rows.map(\.name), ["cat", "dog", "ball"])
        XCTAssertFalse(model.hasMore)
    }
    @MainActor func testLateResponseCannotReplaceNewResultsEvenIfTransportIgnoresCancellation() async throws {
        let model = SearchModel(delay: 0) { query, _, _ in
            // An external service is allowed to complete despite cancellation.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + (query == "old" ? 0.15 : 0.01)) {
                    continuation.resume(returning: SearchPage(totalResults: 1, results: [.init(name: query, path: "C:\\")]))
                }
            }
        }
        model.query = "old"
        try await Task.sleep(nanoseconds: 20_000_000)
        model.query = "new"
        try await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertEqual(model.rows.map(\.name), ["new"])
        XCTAssertFalse(model.busy)
    }
    @MainActor func testFailureClearsLoadingAndCanRetry() async throws {
        let state = RetryState()
        let model = SearchModel(delay: 0) { _, _, _ in
            if state.fail { throw SearchFailure.unauthorized }
            return SearchPage(totalResults: 0, results: [])
        }
        model.restart()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.busy)
        state.fail = false
        model.restart()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.busy)
    }
    @MainActor func testDeletedRowsStayRemovedDuringPaginationAndFolderRemovalIsBounded() async throws {
        let model = SearchModel(delay: 0) { _, _, offset in
            SearchPage(totalResults: 4, results: offset == 0 ? [.init(type: "folder", name: "Media", path: "C:"), .init(name: "cat", path: "C:\\Media")] : [.init(name: "dog", path: "C:\\Media"), .init(name: "ball", path: "C:\\MediaOther")])
        }
        model.restart()
        try await Task.sleep(for: .milliseconds(20))
        model.removeDeleted([.init(type: "folder", name: "Media", path: "C:")])
        XCTAssertTrue(model.rows.isEmpty)
        model.loadMore()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.rows.map(\.name), ["ball"])
        XCTAssertFalse(model.hasMore)
    }

}
