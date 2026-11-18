import XCTest
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class LibraryTests: XCTestCase {
    @MainActor func testScopedEmptyQueryIsRecordedAndClearKeepsBookmarks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        try store.saveQuery(name: "Images", query: "", sort: .init(), scope: .init(kind: .images))
        try store.recordQuery("", sort: .init(), scope: .init(kind: .images))
        XCTAssertEqual(store.state.recentQueries.first?.scope.kind, .images)
        let revision = store.historyRevision
        try store.clearRecentQueries()
        XCTAssertNotEqual(store.historyRevision, revision)
        XCTAssertTrue(store.state.recentQueries.isEmpty)
        XCTAssertEqual(store.state.savedQueries.count, 1)
    }
    @MainActor func testAppHistoryDeduplicatesMovesToFrontAndKeepsFive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        for i in 0..<7 { try store.recordApplication(.init(name: "App \(i)", path: "/Applications/App\(i).app")) }
        try store.recordApplication(.init(name: "App 3", path: "/Applications/App3.app"))
        XCTAssertEqual(store.state.applications.map(\.name), ["App 3", "App 6", "App 5", "App 4", "App 2"])
        let loaded = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        XCTAssertEqual(loaded.state.applications, store.state.applications)
    }
    @MainActor func testSavedQueryKeepsSyntaxAndSortAcrossReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let store = LibraryStore(fileURL: url)
        try store.saveQuery(name: "Media", query: "ext:mp4 cats + dogs", sort: .init(field: "size", ascending: false))
        let loaded = LibraryStore(fileURL: url)
        XCTAssertEqual(loaded.state.savedQueries.first?.query, "ext:mp4 cats + dogs")
        XCTAssertEqual(loaded.state.savedQueries.first?.sort, .init(field: "size", ascending: false))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
    @MainActor func testCorruptLibraryIsNotOverwrittenByAutomaticHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let original = Data("broken".utf8)
        try original.write(to: url)
        let store = LibraryStore(fileURL: url)
        XCTAssertNotNil(store.error)
        XCTAssertThrowsError(try store.recordQuery("cat", sort: .init()))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    @MainActor func testQueryRecentsAreBoundedAndExactDuplicatesMoveToFront() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        for i in 0..<25 { try store.recordQuery("cat \(i)", sort: .init()) }
        try store.recordQuery("cat 20", sort: .init())
        XCTAssertEqual(store.state.recentQueries.count, 20)
        XCTAssertEqual(store.state.recentQueries.first?.query, "cat 20")
        XCTAssertEqual(store.state.recentQueries.filter { $0.query == "cat 20" }.count, 1)
    }
}
