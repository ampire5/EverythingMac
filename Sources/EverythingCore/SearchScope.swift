import Foundation

public enum SearchKind: String, Codable, CaseIterable, Sendable {
    case all, video, audio, images, documents, folders
    public var title: String {
        switch self {
        case .all: "Все"
        case .video: "Видео"
        case .audio: "Аудио"
        case .images: "Изображения"
        case .documents: "Документы"
        case .folders: "Папки"
        }
    }
    public var expression: String {
        switch self {
        case .all: ""
        case .video: "video:"
        case .audio: "audio:"
        case .images: "pic:"
        case .documents: "doc:"
        case .folders: "folder:"
        }
    }
}

public struct SearchScope: Codable, Equatable, Sendable {
    public var kind: SearchKind
    public var folder: String?
    public init(kind: SearchKind = .all, folder: String? = nil) {
        self.kind = kind; self.folder = folder
    }
    public static func folder(containing result: SearchResult) -> String {
        result.type == "folder" ? result.windowsPath : result.path
    }
    public func expression(for query: String) -> String {
        var terms: [String] = []
        if var folder, !folder.isEmpty {
            // Windows folder names cannot contain quotes. Keep UNC prefixes intact.
            folder = folder.replacingOccurrences(of: "/", with: "\\")
            while folder.hasSuffix("\\") { folder.removeLast() }
            terms.append("\"" + folder + "\\\"")
        }
        if kind != .all { terms.append(kind.expression) }
        guard !terms.isEmpty else { return query }
        if !query.isEmpty { terms.append("<" + query + ">") }
        return terms.joined(separator: " ")
    }
}
