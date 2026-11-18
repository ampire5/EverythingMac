import Foundation
import EverythingCore

enum SearchPreferences {
    private static let fields = ["name", "path", "size", "date_modified"]
    static func initialSort(sceneField: String, sceneAscending: Bool, defaults: UserDefaults = .standard) -> SearchSort {
        if fields.contains(sceneField) { return .init(field: sceneField, ascending: sceneAscending) }
        let field = defaults.string(forKey: "Search.lastSortField") ?? "name"
        let ascending = defaults.object(forKey: "Search.lastSortAscending") as? Bool ?? true
        return .init(field: fields.contains(field) ? field : "name", ascending: ascending)
    }
    static func saveSort(_ sort: SearchSort, defaults: UserDefaults = .standard) {
        guard fields.contains(sort.field) else { return }
        defaults.set(sort.field, forKey: "Search.lastSortField")
        defaults.set(sort.ascending, forKey: "Search.lastSortAscending")
    }
}
enum PreviewSizing {
    static func width(preferred: Double, available: Double) -> Double {
        let maximum = max(240, min(720, available - 320))
        return min(maximum, max(240, preferred.isFinite ? preferred : 360))
    }
}
