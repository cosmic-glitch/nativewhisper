import Foundation

final class InMemoryAPIKeyProvider: APIKeyProviding, @unchecked Sendable {
    static let shared = InMemoryAPIKeyProvider()

    private let lock = NSLock()
    private var key: String = ""

    func currentAPIKey() -> String {
        lock.lock()
        defer { lock.unlock() }
        return key
    }

    func setAPIKey(_ value: String) {
        lock.lock()
        key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
    }

    func clearAPIKey() {
        lock.lock()
        key = ""
        lock.unlock()
    }
}
