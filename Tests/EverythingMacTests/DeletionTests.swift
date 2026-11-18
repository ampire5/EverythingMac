import XCTest
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

@MainActor private final class DeletionPathState { var changed = false }

final class DeletionTests: XCTestCase {
    @MainActor func testPreparingNeverDeletesAndCancelLeavesFilesUntouched() async {
        let controller = FileDeletionController(resolve: { _, _ in [URL(fileURLWithPath: "/Volumes/Share/cat")] }, erase: { _ in XCTFail("No permanent mutation before confirmation"); return .init(removed: [], failed: []) })
        controller.prepare([.init(name: "cat", path: "C:")], mappings: [])
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertNotNil(controller.confirmation)
        controller.confirmation = nil
        XCTAssertFalse(controller.working)
    }
    @MainActor func testConfirmedPartialDeletionReportsSuccessAndDoesNotRetryFailures() async {
        let urls = [URL(fileURLWithPath: "/Volumes/Share/cat"), URL(fileURLWithPath: "/Volumes/Share/dog")]
        var calls = 0
        var reported: [String] = []
        let controller = FileDeletionController(resolve: { _, _ in urls }, erase: { _ in calls += 1; return .init(removed: [urls[0]], failed: [urls[1]]) })
        controller.onRemoved = { reported += $0.map(\.name) }
        controller.prepare([.init(name: "cat", path: "C:"), .init(name: "dog", path: "C:")], mappings: [])
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertEqual(controller.confirmation?.mode, .permanent)
        XCTAssertEqual(calls, 0)
        controller.confirm()
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertEqual(reported, ["cat"])
        XCTAssertEqual(calls, 1)
        XCTAssertNil(controller.confirmation)
        XCTAssertNotNil(controller.message)
        controller.confirm()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(calls, 1, "Failures must never be retried without a new user request")
    }
    @MainActor func testMountPathChangeAfterConfirmationDoesNotDeleteNewTarget() async {
        let state = DeletionPathState()
        let controller = FileDeletionController(resolve: { _, _ in [URL(fileURLWithPath: state.changed ? "/Volumes/Other/cat" : "/Volumes/Share/cat")] }, erase: { _ in XCTFail("No permanent fallback"); return .init(removed: [], failed: []) })
        controller.prepare([.init(name: "cat", path: "C:")], mappings: [])
        for _ in 0..<100 where controller.working { await Task.yield() }
        state.changed = true
        controller.confirm()
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertNotNil(controller.message)
        XCTAssertNil(controller.confirmation)
    }
    @MainActor func testMappingRootCannotBeDeleted() async {
        let controller = FileDeletionController(resolve: { _, _ in XCTFail("Mapping root must be rejected first"); return [] }, erase: { _ in XCTFail("No mutation"); return .init(removed: [], failed: []) })
        controller.prepare([.init(type: "folder", name: "Media", path: "C:")], mappings: [.init(windowsRoot: "C:\\Media", shareURL: "smb://server/Media", mountPath: "/Volumes/Media")])
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertNil(controller.confirmation)
        XCTAssertNotNil(controller.message)
    }
    @MainActor func testFolderAndChildAreConfirmedAsOneRecursiveTarget() async {
        let controller = FileDeletionController(resolve: { _, _ in [URL(fileURLWithPath: "/Volumes/Share/Media"), URL(fileURLWithPath: "/Volumes/Share/Media/cat")] }, erase: { _ in XCTFail("Only preparing"); return .init(removed: [], failed: []) })
        controller.prepare([.init(type: "folder", name: "Media", path: "C:"), .init(name: "cat", path: "C:\\Media")], mappings: [])
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertEqual(controller.confirmation?.targets.map(\.result.name), ["Media"])
    }
    @MainActor func testPermanentBackendRemovesOnlyDisposableTargetsAndReportsFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cat = folder.appendingPathComponent("cat.txt")
        let dog = folder.appendingPathComponent("dog.txt")
        let missing = folder.appendingPathComponent("missing.txt")
        try Data("cat".utf8).write(to: cat)
        try Data("dog".utf8).write(to: dog)
        let outcome = await DeletionBackend.erase([cat, missing])
        XCTAssertEqual(outcome.removed, [cat])
        XCTAssertEqual(outcome.failed, [missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cat.path))
        XCTAssertEqual(try String(contentsOf: dog, encoding: .utf8), "dog")
    }

    @MainActor func testChangedRemoteShareWithSameLocalPathDoesNotDelete() async {
        let controller = FileDeletionController(resolve: { _, _ in [URL(fileURLWithPath: "/Volumes/Share/cat")] }, erase: { _ in XCTFail("No mutation"); return .init(removed: [], failed: []) })
        let before = PathMapping(windowsRoot: "C:", shareURL: "smb://server-one/Share", mountPath: "/Volumes/Share")
        let after = PathMapping(windowsRoot: "C:", shareURL: "smb://server-two/Share", mountPath: "/Volumes/Share")
        controller.prepare([.init(name: "cat", path: "C:")], mappings: [before])
        for _ in 0..<100 where controller.working { await Task.yield() }
        controller.confirm(mappings: [after])
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertNotNil(controller.message)
        XCTAssertNil(controller.confirmation)
    }

    @MainActor func testNetworkSelectionWarnsOfIrreversibleDeletionBeforeAnyBackendRuns() async {
        var erased = false
        let controller = FileDeletionController(resolve: { _, _ in [URL(fileURLWithPath: "/Volumes/Share/cat")] }, erase: { values in erased = true; return .init(removed: values, failed: []) })
        controller.prepare([.init(name: "cat", path: "C:")], mappings: [])
        for _ in 0..<100 where controller.working { await Task.yield() }
        XCTAssertEqual(controller.confirmation?.mode, .permanent, "The first confirmation must disclose irreversible deletion")
        XCTAssertFalse(erased)
        controller.confirmation = nil
        controller.confirm()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(erased, "Cancelling must leave all files untouched")
    }

    @MainActor func testRealDisposableFileIsUnchangedWhileConfirmationIsShownAndAfterCancel() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("confirmation-check.txt")
        let contents = Data("must survive preparation and cancellation".utf8)
        try contents.write(to: url)
        // Use the actual mutation backend; only path resolution is supplied for this local fixture.
        let controller = FileDeletionController(resolve: { _, _ in [url] })
        controller.prepare([.init(name: "confirmation-check.txt", path: "C:")], mappings: [])
        while controller.working { await Task.yield() }
        XCTAssertEqual(controller.confirmation?.mode, .permanent)
        XCTAssertEqual(try Data(contentsOf: url), contents)
        controller.confirmation = nil
        controller.confirm()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(try Data(contentsOf: url), contents)
    }

}
