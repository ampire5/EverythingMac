import Foundation
import Darwin

/// Stage and protect the complete config before touching Keychain; compensate if final rename fails.
@MainActor enum SettingsCommit {
    static func write(_ data: Data, to destination: URL, password: String, previousPassword: String,
                      updatePassword: (String) throws -> Void) throws {
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staged = folder.appendingPathComponent(".settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        let changed = password != previousPassword
        if changed { try updatePassword(password) }
        if rename(staged.path, destination.path) != 0 {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            if changed {
                do { try updatePassword(previousPassword) }
                catch {
                    throw NSError(domain: "Settings", code: 3, userInfo: [NSLocalizedDescriptionKey: "Настройки не записаны, и предыдущий пароль не удалось восстановить в Keychain. Проверьте пароль перед повторным сохранением."])
                }
            }
            throw error
        }
    }
}
