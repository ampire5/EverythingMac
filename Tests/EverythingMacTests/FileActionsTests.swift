import XCTest
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

@MainActor private final class OpenGate {
    var continuations: [String: CheckedContinuation<Void, Error>] = [:]
    var batches: [[URL]] = []
    func open(_ urls: [URL], _ application: ApplicationChoice) async throws {
        batches.append(urls)
        try await withCheckedThrowingContinuation { continuations[application.name] = $0 }
    }
}
final class FileActionsTests: XCTestCase {
    @MainActor func testEmbeddedOpenHandsOffTheResolvedFolder() async {
        let resolved = URL(fileURLWithPath: "/Volumes/Share/Examples")
        let actions = FileActions(resolveFiles: { _, _ in [resolved] })
        let handedOff = expectation(description: "Host receives resolved folder")
        actions.openResult = { url, isFolder in
            XCTAssertEqual(url, resolved)
            XCTAssertTrue(isFolder)
            handedOff.fulfill()
        }
        actions.perform([.init(type: "folder", name: "Examples", path: "C:")], operation: .open,
                        mappings: [], library: LibraryStore(fileURL: nil))
        for _ in 0..<100 where actions.working { await Task.yield() }
        await fulfillment(of: [handedOff], timeout: 1)
    }

    @MainActor func testCancelledCompletionCannotClearReplacementOrRecordFailedApp() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        let gate = OpenGate()
        let actions = FileActions(resolveFiles: { _, _ in [URL(fileURLWithPath: "/tmp/cat"), URL(fileURLWithPath: "/tmp/dog")] }, openApplication: { try await gate.open($0, $1) })
        let selected: [SearchResult] = [.init(name: "cat", path: "C:"), .init(name: "dog", path: "C:")]
        actions.perform(selected, operation: .application(.init(name: "First", path: "/Applications/First.app")), mappings: [], library: library)
        while gate.continuations["First"] == nil { await Task.yield() }
        actions.cancel()
        actions.perform(selected, operation: .application(.init(name: "Second", path: "/Applications/Second.app")), mappings: [], library: library)
        while gate.continuations["Second"] == nil { await Task.yield() }
        gate.continuations["First"]?.resume(throwing: CancellationError())
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(actions.working, "Late completion must not clear the replacement action")
        XCTAssertTrue(library.state.applications.isEmpty, "No app was successfully handed files yet")
        gate.continuations["Second"]?.resume()
        for _ in 0..<100 where library.state.applications.isEmpty { await Task.yield() }
        XCTAssertEqual(library.state.applications.map(\.name), ["Second"])
        XCTAssertEqual(gate.batches.map(\.count), [2, 2])
    }
    @MainActor func testDisconnectedBatchRetainsAllFilesAndApplicationForRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        let mapping = PathMapping(windowsRoot: "C:", shareURL: "smb://server/Share", mountPath: "/Volumes/Share")
        let application = ApplicationChoice(name: "Player", path: "/Applications/Player.app")
        let selected: [SearchResult] = [.init(name: "cat", path: "C:"), .init(name: "dog", path: "C:")]
        let actions = FileActions(resolveFiles: { _, _ in throw FileAccessFailure.disconnected(mapping) }, openApplication: { _, _ in XCTFail("Disconnected files must not be handed off") })
        actions.perform(selected, operation: .application(application), mappings: [mapping], library: library)
        for _ in 0..<100 where actions.working { await Task.yield() }
        XCTAssertEqual(actions.pending?.results, selected)
        XCTAssertEqual(actions.pending?.operation, .application(application))
        XCTAssertTrue(library.state.applications.isEmpty)
    }
    @MainActor func testFolderBatchIsRejectedBeforeAnyResolutionOrHandoff() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        let actions = FileActions(resolveFiles: { _, _ in XCTFail("Folder batch must not start resolving"); return [] }, openApplication: { _, _ in XCTFail("Folder batch must not be handed off") })
        actions.perform([.init(type: "folder", name: "Media", path: "C:")], operation: .application(.init(name: "Player", path: "/Applications/Player.app")), mappings: [], library: library)
        XCTAssertFalse(actions.working)
        XCTAssertNotNil(actions.message)
        XCTAssertTrue(library.state.applications.isEmpty)
    }
    @MainActor func testFailedApplicationHandoffDoesNotChangeHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        let actions = FileActions(resolveFiles: { _, _ in [URL(fileURLWithPath: "/tmp/cat")] }, openApplication: { _, _ in throw CocoaError(.fileReadNoSuchFile) })
        actions.perform([.init(name: "cat", path: "C:")], operation: .application(.init(name: "Player", path: "/Applications/Player.app")), mappings: [], library: library)
        for _ in 0..<100 where actions.working { await Task.yield() }
        XCTAssertFalse(actions.working)
        XCTAssertNotNil(actions.message)
        XCTAssertTrue(library.state.applications.isEmpty)
    }

}
