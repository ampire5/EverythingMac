import XCTest
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class FileAccessTests: XCTestCase {
    @MainActor func testBatchRebasesEveryFileUsingLiveMountAndPreservesOrder() async throws {
        let urls = try await FileAccess.resolve([
            .init(name: "cat.mp4", path: "C:\\Media"), .init(name: "dog.mp4", path: "C:\\Media")
        ], mappings: [.init(windowsRoot: "C:\\Media", shareURL: "smb://server/Share/Media", mountPath: "/Volumes/Old/Media")],
        mounts: { [.init(mountPath: "/Volumes/Share-1", shareURL: "smb://server/Share")] }, exists: { _ in true })
        XCTAssertEqual(urls.map(\.path), ["/Volumes/Share-1/Media/cat.mp4", "/Volumes/Share-1/Media/dog.mp4"])
    }
    @MainActor func testDisconnectedBatchDoesNotProbeFilesystem() async {
        do {
            _ = try await FileAccess.resolve([.init(name: "cat", path: "C:")], mappings: [.init(windowsRoot: "C:", shareURL: "smb://server/Share", mountPath: "/Volumes/Share")], mounts: { [] }, exists: { _ in XCTFail("Disconnected resource must not be probed"); return true })
            XCTFail("Expected disconnected resource")
        } catch { XCTAssertTrue(error is FileAccessFailure) }
    }
    @MainActor func testTimeoutReturnsWithoutWaitingForBlockedCheck() async {
        let began = ContinuousClock.now
        do {
            _ = try await FileAccess.resolve([.init(name: "cat", path: "C:")], mappings: [.init(windowsRoot: "C:", shareURL: "smb://server/Share", mountPath: "/Volumes/Share")], timeout: .milliseconds(15), mounts: { [.init(mountPath: "/Volumes/Share", shareURL: "smb://server/Share")] }, exists: { _ in Thread.sleep(forTimeInterval: 0.25); return true })
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? FileAccessFailure, .timedOut) }
        XCTAssertLessThan(began.duration(to: .now), .milliseconds(180))
    }
    @MainActor func testCancellationWinsOverLateFileCheck() async {
        let task = Task { try await FileAccess.resolve([.init(name: "cat", path: "C:")], mappings: [.init(windowsRoot: "C:", shareURL: "smb://server/Share", mountPath: "/Volumes/Share")], mounts: { [.init(mountPath: "/Volumes/Share", shareURL: "smb://server/Share")] }, exists: { _ in Thread.sleep(forTimeInterval: 0.2); return true }) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
