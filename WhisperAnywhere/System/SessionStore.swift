import Foundation

protocol SessionStoring: Sendable {
    func loadSession() -> AuthSession?
    func saveSession(_ session: AuthSession) throws
    func clearSession() throws
}

enum SessionStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode auth session."
        case .decodingFailed:
            return "Failed to decode auth session."
        case .writeFailed(let detail):
            return "Failed to write session file: \(detail)"
        }
    }
}

final class FileSessionStore: SessionStoring, @unchecked Sendable {
    static let shared = FileSessionStore()

    private let fileURL: URL
    private let lock = NSLock()

    init(directory: URL? = nil, filename: String = "session.json") {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperAnywhere", isDirectory: true)
        self.fileURL = dir.appendingPathComponent(filename)
    }

    func loadSession() -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AuthSession.self, from: data)
    }

    func saveSession(_ session: AuthSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(session) else {
            throw SessionStoreError.encodingFailed
        }

        lock.lock()
        defer { lock.unlock() }

        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw SessionStoreError.writeFailed(error.localizedDescription)
        }

        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw SessionStoreError.writeFailed(error.localizedDescription)
        }
    }

    func clearSession() throws {
        lock.lock()
        defer { lock.unlock() }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
