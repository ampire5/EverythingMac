import Foundation
import EverythingCore

struct DeletionOutcome: Sendable {
    let removed: [URL]
    let failed: [URL]
    var error: String? = nil
}
struct DeletionTarget: Identifiable, Sendable {
    let result: SearchResult
    let url: URL
    var id: String { url.path }
}
struct DeletionConfirmation: Identifiable {
    enum Mode { case permanent }
    let id = UUID()
    let targets: [DeletionTarget]
    let mappings: [PathMapping]
    let mode: Mode
}
@MainActor enum DeletionBackend {
    static func erase(_ urls: [URL]) async -> DeletionOutcome {
        // A mutation is never put in a read-timeout race: late removal must remain tracked.
        await Task.detached(priority: .userInitiated) {
            var removed: [URL] = [], failed: [URL] = []
            var firstError: String?
            for url in urls {
                do { try FileManager.default.removeItem(at: url); removed.append(url) }
                catch { failed.append(url); if firstError == nil { firstError = error.localizedDescription } }
            }
            return DeletionOutcome(removed: removed, failed: failed, error: firstError)
        }.value
    }
}
@MainActor package final class FileDeletionController: ObservableObject {
    @Published var confirmation: DeletionConfirmation?
    @Published package private(set) var working = false
    @Published private(set) var message: String?
    var onRemoved: (([SearchResult]) -> Void)?
    private let resolve: @MainActor ([SearchResult], [PathMapping]) async throws -> [URL]
    private let erase: @MainActor ([URL]) async -> DeletionOutcome
    init(resolve: @escaping @MainActor ([SearchResult], [PathMapping]) async throws -> [URL] = { try await FileAccess.resolve($0, mappings: $1) },
         erase: @escaping @MainActor ([URL]) async -> DeletionOutcome = DeletionBackend.erase) {
        self.resolve = resolve; self.erase = erase
    }
    func prepare(_ results: [SearchResult], mappings: [PathMapping]) {
        guard !working, confirmation == nil, !results.isEmpty else { return }
        working = true; message = nil
        Task { [self] in
            defer { working = false }
            do {
                try Self.rejectRoots(results, mappings: mappings)
                let urls = try await resolve(results, mappings)
                guard urls.count == results.count else { throw CocoaError(.fileReadUnknown) }
                let targets = Self.coalesce(zip(results, urls).map { DeletionTarget(result: $0, url: $1) })
                confirmation = .init(targets: targets, mappings: mappings, mode: .permanent)
            } catch { message = error.localizedDescription }
        }
    }
    func confirm(mappings: [PathMapping]? = nil) {
        guard !working, let request = confirmation else { return }
        working = true; confirmation = nil; message = nil
        // Retain this job until all mutations report an outcome, even if its view disappears.
        Task { [self] in
            defer { working = false }
            do {
                let currentMappings = mappings ?? request.mappings
                let results = request.targets.map(\.result)
                try Self.rejectRoots(results, mappings: currentMappings)
                guard results.allSatisfy({ result in
                    let before = PathResolver.resolve(result.windowsPath, mappings: request.mappings)?.mapping
                    let after = PathResolver.resolve(result.windowsPath, mappings: currentMappings)?.mapping
                    return before?.windowsRoot == after?.windowsRoot && before?.shareURL == after?.shareURL
                }) else {
                    message = "Сопоставление сетевого ресурса изменилось после подтверждения. Ничего не удалено. Выберите файлы и повторите действие."
                    return
                }
                let urls = try await resolve(results, currentMappings)
                guard urls.map({ $0.standardizedFileURL.path }) == request.targets.map({ $0.url.standardizedFileURL.path }) else {
                    message = "Сетевые пути изменились после подтверждения. Ничего не удалено. Выберите файлы и повторите действие."
                    return
                }
                let outcome = await erase(urls)
                let removed = Set(outcome.removed.map { $0.standardizedFileURL.path })
                let succeeded = request.targets.filter { removed.contains($0.url.standardizedFileURL.path) }
                if !succeeded.isEmpty { onRemoved?(succeeded.map(\.result)) }
                let failed = request.targets.filter { !removed.contains($0.url.standardizedFileURL.path) }
                if !failed.isEmpty {
                    message = "Не удалось удалить объектов: \(failed.count). Остальные успешно удалены.\n\n" + (outcome.error ?? "Проверьте права доступа и соединение с сетевой папкой.")
                }
            } catch { message = error.localizedDescription }
        }
    }
    private static func rejectRoots(_ results: [SearchResult], mappings: [PathMapping]) throws {
        for result in results {
            if let resolved = PathResolver.resolve(result.windowsPath, mappings: mappings),
               resolved.localURL.standardizedFileURL.path == URL(fileURLWithPath: resolved.mapping.mountPath).standardizedFileURL.path {
                throw NSError(domain: "Deletion", code: 1, userInfo: [NSLocalizedDescriptionKey: "Корень сопоставленной сетевой папки удалять нельзя. Выберите объекты внутри неё."])
            }
        }
    }
    private static func coalesce(_ targets: [DeletionTarget]) -> [DeletionTarget] {
        var seen = Set<String>()
        return targets.filter { target in
            let path = target.url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return false }
            return !targets.contains { other in
                other.result.type == "folder" && path.hasPrefix(other.url.standardizedFileURL.path + "/")
            }
        }
    }
}
