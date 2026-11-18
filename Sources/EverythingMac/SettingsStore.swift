import EverythingSearchUI
import Foundation
import Combine
import EverythingCore

@MainActor final class SettingsStore: ObservableObject {
    @Published var config: Configuration
    @Published var password = ""
    @Published var storageError: String?
    private var keychainError: String?
    private let configurationURL: URL
    static var fileURL: URL { SavedEverythingConnection.fileURL }
    init(fileURL: URL = SettingsStore.fileURL, passwordReader: () throws -> String = PasswordStore.read) {
        configurationURL = fileURL
        config = Configuration()
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: fileURL))
            }
        } catch { storageError = error.localizedDescription }
        // A corrupt config must never prevent loading or preserving the saved password.
        do { password = try passwordReader() }
        catch { keychainError = error.localizedDescription; storageError = error.localizedDescription }
    }
    func save(_ value: Configuration, password: String) throws {
        if password.isEmpty, let keychainError {
            throw NSError(domain: "Keychain", code: 1, userInfo: [NSLocalizedDescriptionKey: keychainError])
        }
        _ = try EverythingAPI.request(server: value.server, login: value.login, password: password, query: "", sort: .init(), offset: 0)
        let shares = MountedShare.snapshot()
        for mapping in value.mappings {
            guard let url = URL(string: mapping.shareURL), url.scheme == "smb", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty,
                  !url.path.split(separator: "/").contains(".."), !url.path.split(separator: "/").contains("."),
                  mapping.mountPath.hasPrefix("/"), !mapping.windowsRoot.isEmpty else {
                throw NSError(domain: "Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Для каждого правила нужны Windows-папка, SMB-адрес без пароля и полный путь точки подключения."])
            }
            if let share = shares.sorted(by: { $0.mountPath.count > $1.mountPath.count }).first(where: { mapping.mountPath == $0.mountPath || mapping.mountPath.hasPrefix($0.mountPath + "/") }) {
                guard let expected = mapping.mounted(at: share.mountPath, remoteURL: share.shareURL),
                      URL(fileURLWithPath: expected.mountPath).standardizedFileURL.path == URL(fileURLWithPath: mapping.mountPath).standardizedFileURL.path else {
                    throw NSError(domain: "Settings", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mac-папка не соответствует SMB-адресу. Нажмите «Выбрать…»: адрес подпапки будет заполнен автоматически."])
                }
            }
        }
        // A previous Keychain failure must not turn compensation into an empty-password overwrite.
        let previousPassword = keychainError == nil ? self.password : try PasswordStore.read()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SettingsCommit.write(encoder.encode(value), to: configurationURL, password: password, previousPassword: previousPassword, updatePassword: PasswordStore.save)
        config = value; self.password = password; storageError = nil; keychainError = nil
    }
}
