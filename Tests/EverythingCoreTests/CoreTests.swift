import XCTest
@testable import EverythingCore

final class CoreTests: XCTestCase {
    func testDriveRootRuleResolvesRootLevelAndNestedFiles() {
        let mapping = PathMapping(windowsRoot: "C:\\", shareURL: "smb://server/C$", mountPath: "/Volumes/C$")
        XCTAssertEqual(PathResolver.resolve("C:\\Windows", mappings: [mapping])?.localURL.path, "/Volumes/C$/Windows")
        XCTAssertEqual(PathResolver.resolve("c:\\Media\\cat.mp4", mappings: [mapping])?.localURL.path, "/Volumes/C$/Media/cat.mp4")
        XCTAssertNil(PathResolver.resolve("D:\\Windows", mappings: [mapping]))
    }
    func testSMBSubfolderSurvivesMountAtDifferentLocation() {
        let m = PathMapping(windowsRoot: "C:\\Media", shareURL: "smb://server/Share/Movies%20%231", mountPath: "/Volumes/Old/Movies #1")
        let rebased = m.mounted(at: "/Volumes/Share-1", remoteURL: "smb://SERVER/Share")
        XCTAssertEqual(rebased?.mountPath, "/Volumes/Share-1/Movies #1")
        XCTAssertEqual(rebased.flatMap { PathResolver.resolve("C:\\Media\\cat.mp4", mappings: [$0]) }?.localURL.path, "/Volumes/Share-1/Movies #1/cat.mp4")
        XCTAssertNil(m.mounted(at: "/Volumes/Share", remoteURL: "smb://other/Share"))
        XCTAssertNil(m.mounted(at: "/Volumes/Share", remoteURL: "smb://server/ShareOther"))
    }
    func testRealEverythingStringNumbersAndFiletime() throws {
        let data = Data(#"{"totalResults":1,"results":[{"type":"file","name":"cat.mp4","path":"C:\\Media","size":"27291460","date_modified":"116444736000000000"}]}"#.utf8)
        let page = try JSONDecoder().decode(SearchPage.self, from: data)
        XCTAssertEqual(page.results.first?.size, 27_291_460)
        XCTAssertEqual(page.results.first?.date_modified?.timeIntervalSince1970, 0)
        XCTAssertEqual(page.results.first?.windowsPath, "C:\\Media\\cat.mp4")
    }
    func testFoldersAndMissingMetadata() throws {
        let data = Data(#"{"totalResults":1,"results":[{"type":"folder","name":"Media","path":"C:\\"}]}"#.utf8)
        let page = try JSONDecoder().decode(SearchPage.self, from: data)
        XCTAssertNil(page.results[0].size)
        XCTAssertEqual(page.results[0].windowsPath, "C:\\Media")
    }
    func testLongestRootAndCaseInsensitiveBoundary() {
        let broad = PathMapping(windowsRoot: "C:\\", shareURL: "smb://server/C$", mountPath: "/Volumes/C$")
        let specific = PathMapping(windowsRoot: "c:\\Media", shareURL: "smb://server/Media", mountPath: "/Volumes/Media")
        let result = PathResolver.resolve("C:\\MEDIA\\cats #1.mp4", mappings: [broad, specific])
        XCTAssertEqual(result?.localURL.path, "/Volumes/Media/cats #1.mp4")
        XCTAssertNil(PathResolver.resolve("C:\\MediaOther\\cat.mp4", mappings: [specific]))
    }
    func testUNCAndTraversal() {
        let m = PathMapping(windowsRoot: "\\\\server\\Share", shareURL: "smb://server/Share", mountPath: "/Volumes/Share")
        XCTAssertEqual(PathResolver.resolve("\\\\SERVER\\Share\\папка\\cat.mp4", mappings: [m])?.localURL.path, "/Volumes/Share/папка/cat.mp4")
        XCTAssertNil(PathResolver.resolve("\\\\server\\Share\\..\\private", mappings: [m]))
        XCTAssertNil(PathResolver.resolve("D:\\cat.mp4", mappings: [m]))
    }
}
