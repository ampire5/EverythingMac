import Foundation
import Combine
import EverythingCore

struct ApplicationChoice: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let path: String
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}
struct SavedQuery: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var query: String
    var sort: SearchSort
    var scope = SearchScope()
    init(id: UUID = UUID(), name: String, query: String, sort: SearchSort, scope: SearchScope = .init()) {
        self.id = id; self.name = name; self.query = query; self.sort = sort; self.scope = scope
    }
    private enum CodingKeys: String, CodingKey { case id, name, query, sort, scope }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        query = try c.decode(String.self, forKey: .query)
        sort = try c.decode(SearchSort.self, forKey: .sort)
        scope = try c.decodeIfPresent(SearchScope.self, forKey: .scope) ?? .init()
    }
}
struct LibraryState: Codable, Equatable {
    var savedQueries: [SavedQuery] = []
    var recentQueries: [SavedQuery] = []
    var applications: [ApplicationChoice] = []
}
@MainActor package final class LibraryStore: ObservableObject {
    @Published private(set) var state = LibraryState()
    @Published private(set) var error: String?
    private(set) var historyRevision = UUID()
    private static let embeddedLibraryKey = "Everything.embeddedLibrary"
    private let fileURL: URL?
    private let defaults: UserDefaults?
    private var readFailed = false

    package init(fileURL: URL?) {
        self.fileURL = fileURL
        defaults = nil
        load {
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return try Data(contentsOf: fileURL)
        }
    }

    init(defaults: UserDefaults) {
        fileURL = nil
        self.defaults = defaults
        load { defaults.data(forKey: Self.embeddedLibraryKey) }
    }

    private func load(_ read: () throws -> Data?) {
        do {
            if let data = try read() { state = try JSONDecoder().decode(LibraryState.self, from: data) }
        } catch {
            readFailed = true
            self.error = "Не удалось прочитать закладки и историю. Исходные данные сохранены: \(error.localizedDescription)"
        }
    }

    func recordApplication(_ application: ApplicationChoice) throws {
        var next = state
        next.applications.removeAll { $0.id == application.id }
        next.applications.insert(application, at: 0)
        next.applications = Array(next.applications.prefix(5))
        try persist(next)
    }
    func recordQuery(_ query: String, sort: SearchSort, scope: SearchScope = .init()) throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scope != SearchScope() else { return }
        if let first = state.recentQueries.first, first.query == query, first.sort == sort, first.scope == scope { return }
        var next = state
        next.recentQueries.removeAll { $0.query == query && $0.sort == sort && $0.scope == scope }
        next.recentQueries.insert(.init(name: query, query: query, sort: sort, scope: scope), at: 0)
        next.recentQueries = Array(next.recentQueries.prefix(20))
        try persist(next)
    }
    func clearRecentQueries() throws {
        var next = state; next.recentQueries = []; try persist(next)
        historyRevision = UUID()
    }
    func saveQuery(name: String, query: String, sort: SearchSort, scope: SearchScope = .init()) throws {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var next = state
        if let index = next.savedQueries.firstIndex(where: { $0.name == title }) {
            next.savedQueries[index].query = query; next.savedQueries[index].sort = sort; next.savedQueries[index].scope = scope
        } else { next.savedQueries.append(.init(name: title, query: query, sort: sort, scope: scope)) }
        try persist(next)
    }
    func removeQuery(_ id: UUID) throws {
        var next = state
        next.savedQueries.removeAll { $0.id == id }
        try persist(next)
    }
    private func persist(_ next: LibraryState) throws {
        guard !readFailed else { throw CocoaError(.fileReadCorruptFile) }
        do {
            if let defaults {
                defaults.set(try JSONEncoder().encode(next), forKey: Self.embeddedLibraryKey)
            } else if let fileURL {
                let folder = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let data = try JSONEncoder().encode(next)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            state = next
            error = nil
        } catch {
            self.error = "Не удалось сохранить закладки и историю: \(error.localizedDescription)"
            throw error
        }
    }
}
