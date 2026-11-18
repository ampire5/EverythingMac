import Foundation

public struct SearchPage: Decodable, Sendable {
    public var totalResults: Int
    public var results: [SearchResult]
}
public struct SearchResult: Decodable, Identifiable, Equatable, Sendable {
    public var type: String
    public var name: String
    public var path: String
    public var size: UInt64?
    public var date_modified: Date?
    public var id: String { path.replacingOccurrences(of: "[\\\\/]+$", with: "", options: .regularExpression) + "\\" + name }
    public var windowsPath: String { id }
    public init(type: String = "file", name: String, path: String, size: UInt64? = nil, modified: Date? = nil) {
        self.type = type; self.name = name; self.path = path; self.size = size; self.date_modified = modified
    }
    private enum CodingKeys: String, CodingKey { case type, name, path, size, date_modified }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        func integer(_ key: CodingKeys) -> UInt64? {
            if let n = try? c.decode(UInt64.self, forKey: key) { return n }
            if let s = try? c.decode(String.self, forKey: key) { return UInt64(s) }
            return nil
        }
        size = integer(.size)
        if let ticks = integer(.date_modified), ticks > 0 {
            date_modified = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
        } else { date_modified = nil }
    }
}
public struct PathMapping: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var windowsRoot: String
    public var shareURL: String
    public var mountPath: String
    public init(windowsRoot: String, shareURL: String, mountPath: String) {
        self.windowsRoot = windowsRoot; self.shareURL = shareURL; self.mountPath = mountPath
    }
    public func mounted(at localRoot: String, remoteURL: String) -> PathMapping? {
        guard let desired = URL(string: shareURL), let remote = URL(string: remoteURL),
              desired.scheme == "smb", remote.scheme == "smb", desired.host?.lowercased() == remote.host?.lowercased(), localRoot.hasPrefix("/") else { return nil }
        let target = desired.path.split(separator: "/").map(String.init)
        let base = remote.path.split(separator: "/").map(String.init)
        guard !base.isEmpty, target.count >= base.count,
              zip(target, base).allSatisfy({ $0.lowercased() == $1.lowercased() }),
              !target.contains(".."), !target.contains(".") else { return nil }
        var copy = self
        copy.mountPath = target.dropFirst(base.count).reduce(URL(fileURLWithPath: localRoot, isDirectory: true)) { $0.appendingPathComponent($1, isDirectory: true) }.path
        return copy
    }
}
public struct ResolvedPath {
    public var mapping: PathMapping
    public var localURL: URL
}
public enum PathResolver {
    public static func resolve(_ path: String, mappings: [PathMapping]) -> ResolvedPath? {
        let normalized = path.replacingOccurrences(of: "/", with: "\\")
        for m in mappings.sorted(by: { $0.windowsRoot.count > $1.windowsRoot.count }) {
            // Keep the leading UNC prefix; only remove trailing separators.
            var actualRoot = m.windowsRoot.replacingOccurrences(of: "/", with: "\\")
            while actualRoot.hasSuffix("\\") { actualRoot.removeLast() }
            guard !actualRoot.isEmpty, !m.mountPath.isEmpty, m.mountPath.hasPrefix("/") else { continue }
            let lower = normalized.lowercased(), base = actualRoot.lowercased()
            guard lower == base || lower.hasPrefix(base + "\\") else { continue }
            let suffix = String(normalized.dropFirst(actualRoot.count)).split(separator: "\\").map(String.init)
            guard !suffix.contains(".."), !suffix.contains("."), !suffix.contains(where: { $0.contains(":") || $0.contains("\0") }) else { return nil }
            let mount = URL(fileURLWithPath: m.mountPath, isDirectory: true)
            let local = suffix.reduce(mount) { $0.appendingPathComponent($1) }
            return ResolvedPath(mapping: m, localURL: local)
        }
        return nil
    }
}
