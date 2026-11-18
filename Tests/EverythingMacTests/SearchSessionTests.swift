import XCTest
@testable import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class SearchSessionTests: XCTestCase {
    @MainActor func testLateBackResponseCannotRestoreSelectionIntoNewQuery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"), passwordReader: { "" })
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        var firstRequests = 0
        var held: CheckedContinuation<SearchPage, Never>?
        let model = SearchModel(delay: 0) { query, _, _ in
            if query == "first" {
                firstRequests += 1
                if firstRequests > 1 { return await withCheckedContinuation { held = $0 } }
            }
            return .init(totalResults: 1, results: [.init(name: query, path: "C:")])
        }
        let session = SearchSession(id: UUID(), store: store, library: library, model: model)
        session.start(.init(query: "first"))
        try await waitUntil { !model.busy }
        session.selected = model.rows
        session.editQuery("second")
        try await waitUntil { !model.busy }
        session.goBack()
        try await waitUntil { held != nil }
        session.editQuery("third")
        try await waitUntil { !model.busy }
        held?.resume(returning: .init(totalResults: 1, results: [.init(name: "first", path: "C:")]))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.query, "third")
        XCTAssertEqual(model.rows.map(\.name), ["third"])
        XCTAssertTrue(session.selected.isEmpty)
        XCTAssertNil(session.tableRestoration)
    }
    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Search did not reach expected state")
    }
    @MainActor func testBackReloadsPagesAndRestoresSelectionAndViewport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"), passwordReader: { "" })
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        var requests: [(String, Int)] = []
        let model = SearchModel(delay: 0) { query, _, offset in
            requests.append((query, offset))
            return SearchPage(totalResults: 4, results: (offset..<offset+2).map { .init(name: "\(query)\($0)", path: "C:\\Examples") })
        }
        let session = SearchSession(id: UUID(), store: store, library: library, model: model)
        session.start(.init(query: "first"))
        try await waitUntil { !model.busy && model.rows.count == 2 }
        model.loadMore()
        try await waitUntil { !model.busy && model.rows.count == 4 }
        let target = model.rows[3]
        session.selected = [target]
        session.updateLocation(.init(topID: target.id, offset: 3, fallbackRow: 3, loadedCount: 4), for: session.state)
        session.editQuery("second")
        try await waitUntil { !model.busy && model.rows.count == 2 }
        session.goBack()
        try await waitUntil { session.tableRestoration != nil }
        XCTAssertEqual(model.query, "first")
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(session.selected.map(\.id), [target.id])
        XCTAssertEqual(session.tableRestoration?.location.topID, target.id)
        XCTAssertEqual(session.tableRestoration?.location.offset, 3)
        XCTAssertEqual(requests.suffix(2).map(\.1), [0, 2])
    }
    @MainActor func testServiceQuerySurvivesSceneStartAndClearsScope() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"), passwordReader: { "" })
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        let model = SearchModel(delay: 0) { _, _, _ in .init(totalResults: 0, results: []) }
        let session = SearchSession(id: UUID(), store: store, library: library, model: model)
        session.receiveSelectedText("Example")
        session.start(.init(query: "restored", scope: .init(kind: .video, folder: "C:\\Clips")))
        try await waitUntil { !model.busy }
        XCTAssertEqual(model.query, "Example")
        XCTAssertEqual(model.scope, .init())
        try await Task.sleep(for: .milliseconds(30))
        try library.clearRecentQueries()
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(library.state.recentQueries.isEmpty, "Pending completion must not undo Clear History")
    }
}
