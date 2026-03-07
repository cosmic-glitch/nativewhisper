import Foundation
import Security

protocol SessionStoring: Sendable {
    func loadSession() -> AuthSession?
    func saveSession(_ session: AuthSession) throws
    func clearSession() throws
}

enum SessionStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode auth session."
        case .decodingFailed:
            return "Failed to decode auth session."
        case .unhandledStatus(let status):
            return "Keychain operation failed with status: \(status)."
        }
    }
}

final class KeychainSessionStore: SessionStoring, @unchecked Sendable {
    static let shared = KeychainSessionStore()

    private let service: String
    private let account: String
    private let lock = NSLock()

    init(
        service: String = "ai.whisperanywhere.app.auth",
        account: String = "session"
    ) {
        self.service = service
        self.account = account
    }

    func loadSession() -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let session = try? decoder.decode(AuthSession.self, from: data) else {
            return nil
        }

        return session
    }

    func saveSession(_ session: AuthSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(session) else {
            throw SessionStoreError.encodingFailed
        }

        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw SessionStoreError.unhandledStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SessionStoreError.unhandledStatus(addStatus)
        }
    }

    func clearSession() throws {
        lock.lock()
        defer { lock.unlock() }

        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw SessionStoreError.unhandledStatus(status)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
