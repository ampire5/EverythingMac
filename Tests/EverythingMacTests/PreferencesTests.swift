import XCTest
import EverythingCore
@testable import EverythingMac
@testable import EverythingSearchUI

final class PreferencesTests: XCTestCase {
    func testNewWindowUsesLastSortAndRestoredWindowKeepsItsOwnSort() {
        let suite = "EverythingMacTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SearchPreferences.saveSort(.init(field: "size", ascending: false), defaults: defaults)
        XCTAssertEqual(SearchPreferences.initialSort(sceneField: "", sceneAscending: true, defaults: defaults), .init(field: "size", ascending: false))
        XCTAssertEqual(SearchPreferences.initialSort(sceneField: "path", sceneAscending: true, defaults: defaults), .init(field: "path", ascending: true))
        let reloaded = UserDefaults(suiteName: suite)!
        XCTAssertEqual(SearchPreferences.initialSort(sceneField: "", sceneAscending: true, defaults: reloaded), .init(field: "size", ascending: false))
    }
    func testPreviewWidthRespectsMinimumAndLeavesRoomForResults() {
        XCTAssertEqual(PreviewSizing.width(preferred: 100, available: 1060), 240)
        XCTAssertEqual(PreviewSizing.width(preferred: 600, available: 1060), 600)
        XCTAssertEqual(PreviewSizing.width(preferred: 900, available: 780), 460)
    }
    @MainActor func testPreviewWidthPersistsAfterResizeWithoutLosingPreferredWidthOnWindowShrink() {
        let suite = "EverythingMacTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = PreviewController(defaults: defaults)
        controller.preferredWidth = 580
        controller.saveWidth()
        let reloaded = PreviewController(defaults: defaults)
        XCTAssertEqual(reloaded.preferredWidth, 580)
        XCTAssertEqual(reloaded.width(available: 780), 460)
        XCTAssertEqual(reloaded.width(available: 1200), 580)
    }
    @MainActor func testSidebarRemembersExplicitVisibilityPinAndFavoritesDisclosure() {
        let suite = "EverythingMacTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PreviewController(defaults: defaults)
        first.show()
        first.pinned = true
        first.favoritesExpanded = false
        let reopened = PreviewController(defaults: defaults)
        XCTAssertTrue(reopened.visible)
        XCTAssertTrue(reopened.pinned)
        XCTAssertFalse(reopened.favoritesExpanded)
        reopened.hide()
        XCTAssertFalse(PreviewController(defaults: defaults).visible)
    }
    @MainActor func testTransientAutoHideDoesNotEraseRememberedOpenState() {
        let suite = "EverythingMacTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PreviewController(defaults: defaults)
        first.show()
        first.hide(remember: false)
        XCTAssertFalse(first.visible)
        XCTAssertTrue(PreviewController(defaults: defaults).visible)
    }

}
