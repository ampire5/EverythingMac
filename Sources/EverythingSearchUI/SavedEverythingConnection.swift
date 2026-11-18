import EverythingCore
import Foundation
import Security

package struct Configuration: Codable, Equatable {
    package var server = "http://server.local:1980"
    package var login = ""
    package var mappings: [PathMapping] = []
    package init() {}
}
package enum PasswordStore {
    static let service = "org.networkeverything.mac.http"
    static let account = "everything-http"
    package static func read() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { throw failure(status) }
        return value
    }
    package static func save(_ password: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attrs: [String: Any] = [kSecValueData as String: Data(password.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw failure(result) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Не удалось получить доступ к Keychain (\(status)). Разрешите доступ приложению в Связке ключей."])
    }
}
/// An optional host adapter for the standalone app’s local connection settings.
public enum SavedEverythingConnection {
    package static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("NetworkEverything/settings.json")
    }

    public static func isConfigured() async -> Bool {
        await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: fileURL.path)
        }.value
    }

    /// Load the settings and read the existing Keychain item. Hosts never write either one.
    public static func load() async throws -> EverythingConnection {
        try await Task.detached(priority: .userInitiated) {
            let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: fileURL))
            return EverythingConnection(server: config.server, login: config.login, password: try PasswordStore.read(),
                                        mappings: config.mappings)
        }.value
    }
}
