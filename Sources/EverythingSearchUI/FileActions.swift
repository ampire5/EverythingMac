import AppKit
import Darwin
import EverythingCore

package struct MountedShare: Identifiable, Sendable {
    package var id: String { mountPath }
    package let mountPath: String
    package let shareURL: String
    package var driveRoot: String? {
        guard let url = URL(string: shareURL) else { return nil }
        let share = url.lastPathComponent
        guard share.count == 2, share.last == "$", let letter = share.first, letter.isLetter else { return nil }
        return String(letter).uppercased() + ":\\"
    }
    package static func snapshot() -> [MountedShare] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var entries: [statfs] = .init(repeating: .init(), count: Int(count) + 8)
        let written = entries.withUnsafeMutableBufferPointer { buffer in
            getfsstat(buffer.baseAddress, Int32(buffer.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        guard written > 0 else { return [] }
        func string<T>(_ value: T) -> String {
            var value = value
            return withUnsafeBytes(of: &value) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
        }
        return entries.prefix(Int(written)).compactMap { entry in
            guard string(entry.f_fstypename) == "smbfs" else { return nil }
            let remote = string(entry.f_mntfromname)
            guard var components = URLComponents(string: "smb:" + remote) else { return nil }
            components.user = nil; components.password = nil
            guard let url = components.url else { return nil }
            return MountedShare(mountPath: string(entry.f_mntonname), shareURL: url.absoluteString)
        }
    }
    package static func sameShare(_ a: String, _ b: String) -> Bool {
        guard let a = URL(string: a), let b = URL(string: b) else { return false }
        return a.host?.lowercased() == b.host?.lowercased() && a.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == b.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}

enum FileOperation: Equatable {
    case open, reveal, application(ApplicationChoice)
}
@MainActor final class FileActions: ObservableObject {
    struct Pending: Identifiable {
        let id = UUID()
        let results: [SearchResult]
        let operation: FileOperation
        let mapping: PathMapping
    }
    @Published var pending: Pending?
    @Published var message: String?
    @Published private(set) var working = false
    private var actionTask: Task<Void, Never>?
    private var generation = UUID()
    var openResult: (@MainActor (URL, Bool) -> Void)?
    private let resolveFiles: @MainActor ([SearchResult], [PathMapping]) async throws -> [URL]
    private let openApplication: @MainActor ([URL], ApplicationChoice) async throws -> Void
    init(resolveFiles: @escaping @MainActor ([SearchResult], [PathMapping]) async throws -> [URL] = { try await FileAccess.resolve($0, mappings: $1) },
         openApplication: @escaping @MainActor ([URL], ApplicationChoice) async throws -> Void = { urls, app in
             let config = NSWorkspace.OpenConfiguration(); config.activates = true
             _ = try await NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: config)
         }) {
        self.resolveFiles = resolveFiles; self.openApplication = openApplication
    }
    func perform(_ results: [SearchResult], operation: FileOperation, mappings: [PathMapping], library: LibraryStore) {
        guard !working, !results.isEmpty else { return }
        if case .application = operation, results.contains(where: { $0.type == "folder" }) {
            message = "Для «Открыть в…» выберите только файлы. Папки можно открыть или показать в Finder."
            return
        }
        working = true
        let token = UUID()
        generation = token
        actionTask = Task { [weak self] in
            do {
                let urls = try await self?.resolveFiles(results, mappings) ?? []
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                switch operation {
                case .reveal: NSWorkspace.shared.activateFileViewerSelecting(urls)
                case .open:
                    if let first = urls.first {
                        if let openResult = self.openResult {
                            openResult(first, results.first?.type == "folder")
                        } else if !NSWorkspace.shared.open(first) {
                            throw CocoaError(.fileReadUnknown)
                        }
                    }
                case .application(let app):
                    try await self.openApplication(urls, app)
                    guard self.generation == token, !Task.isCancelled else { return }
                    do { try library.recordApplication(app) }
                    catch { self.message = "Файлы переданы приложению, но историю сохранить не удалось. " + error.localizedDescription }
                }
                self.working = false; self.actionTask = nil
            } catch is CancellationError {
                guard self?.generation == token else { return }
                self?.working = false; self?.actionTask = nil
            } catch FileAccessFailure.disconnected(let mapping) {
                guard self?.generation == token else { return }
                self?.working = false; self?.actionTask = nil
                self?.pending = Pending(results: results, operation: operation, mapping: mapping)
            } catch {
                guard self?.generation == token else { return }
                self?.working = false; self?.actionTask = nil
                self?.message = error.localizedDescription
            }
        }
    }
    func connect() {
        guard let pending, let url = URL(string: pending.mapping.shareURL), url.scheme == "smb" else { return }
        NSWorkspace.shared.open(url)
    }
    func retry(mappings: [PathMapping], library: LibraryStore) {
        guard let value = pending else { return }
        pending = nil
        perform(value.results, operation: value.operation, mappings: mappings, library: library)
    }
    func copy(_ results: [SearchResult], mac: Bool, mappings: [PathMapping]) {
        let shares = mac ? MountedShare.snapshot() : []
        let paths = results.compactMap { result -> String? in
            if !mac { return result.windowsPath }
            guard let resolved = PathResolver.resolve(result.windowsPath, mappings: mappings) else { return nil }
            let mapping = shares.compactMap { resolved.mapping.mounted(at: $0.mountPath, remoteURL: $0.shareURL) }.first ?? resolved.mapping
            return PathResolver.resolve(result.windowsPath, mappings: [mapping])?.localURL.path
        }
        guard paths.count == results.count else { message = "Сначала добавьте сопоставление для всех выбранных файлов в настройках."; return }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }
    func cancel() { generation = UUID(); actionTask?.cancel(); actionTask = nil; working = false }
    isolated deinit { actionTask?.cancel() }
}
