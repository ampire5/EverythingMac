import XCTest
@testable import EverythingMac

final class SettingsCommitTests: XCTestCase {
    @MainActor func testUnwritableConfigurationDoesNotChangePassword() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocker".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var password = "old"
        XCTAssertThrowsError(try SettingsCommit.write(Data("new configuration".utf8), to: folder.appendingPathComponent("settings.json"), password: "new", previousPassword: "old", updatePassword: { password = $0 }))
        XCTAssertEqual(password, "old")
    }
    @MainActor func testFinalCommitFailureRestoresPreviousPassword() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = folder.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var password = "old"
        XCTAssertThrowsError(try SettingsCommit.write(Data("new configuration".utf8), to: destination, password: "new", previousPassword: "old", updatePassword: { password = $0 }))
        XCTAssertEqual(password, "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
    @MainActor func testKeychainFailurePreservesOldConfiguration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("settings.json")
        try Data("old configuration".utf8).write(to: destination)
        XCTAssertThrowsError(try SettingsCommit.write(Data("new configuration".utf8), to: destination, password: "new", previousPassword: "old", updatePassword: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old configuration")
    }
}
