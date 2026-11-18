import Foundation
import EverythingCore

enum FileAccessFailure: Error, LocalizedError, Equatable {
    case unmapped(String), disconnected(PathMapping), missing(String), timedOut
    var errorDescription: String? {
        switch self {
        case .unmapped(let path): return "Нет сопоставления для Windows-пути. Добавьте правило в настройках.\n\n" + path
        case .disconnected: return "Сетевая папка не подключена. Подключите её через Finder и повторите действие."
        case .missing(let path): return "Файл не найден. Возможно, индекс устарел или правило указывает на другую папку.\n\n" + path
        case .timedOut: return "Сетевая папка не отвечает. Проверьте её в Finder и повторите действие."
        }
    }
}
@MainActor enum FileAccess {
    static func resolve(_ results: [SearchResult], mappings: [PathMapping], timeout: Duration = .seconds(8),
                        mounts: @escaping @Sendable () -> [MountedShare] = { MountedShare.snapshot() },
                        exists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) async throws -> [URL] {
        try Task.checkCancellation()
        let operation = FileAccessOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.continuation = continuation
                operation.worker = Task.detached(priority: .userInitiated) {
                    do {
                        let shares = mounts()
                        // Resolve the entire batch before any filesystem access.
                        let urls = try results.map { result in
                            guard let configured = PathResolver.resolve(result.windowsPath, mappings: mappings) else { throw FileAccessFailure.unmapped(result.windowsPath) }
                            guard let mapping = shares.compactMap({ configured.mapping.mounted(at: $0.mountPath, remoteURL: $0.shareURL) }).first else { throw FileAccessFailure.disconnected(configured.mapping) }
                            guard let resolved = PathResolver.resolve(result.windowsPath, mappings: [mapping]) else { throw FileAccessFailure.unmapped(result.windowsPath) }
                            return resolved.localURL
                        }
                        for url in urls {
                            try Task.checkCancellation()
                            guard exists(url) else { throw FileAccessFailure.missing(url.path) }
                        }
                        try Task.checkCancellation()
                        await operation.finish(.success(urls))
                    } catch { await operation.finish(.failure(error)) }
                }
                operation.timer = Task {
                    do { try await Task.sleep(for: timeout); operation.finish(.failure(FileAccessFailure.timedOut)) }
                    catch { /* The worker or caller already completed this operation. */ }
                }
            }
        } onCancel: {
            Task { @MainActor in operation.finish(.failure(CancellationError())) }
        }
    }
}
@MainActor private final class FileAccessOperation {
    var continuation: CheckedContinuation<[URL], Error>?
    var worker: Task<Void, Never>?
    var timer: Task<Void, Never>?
    func finish(_ result: Result<[URL], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        worker?.cancel(); timer?.cancel()
        worker = nil; timer = nil
        continuation.resume(with: result)
    }
}
