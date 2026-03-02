import Foundation

protocol DeviceIdentifying: Sendable {
    func deviceID() -> String
}

final class DeviceIdentityStore: DeviceIdentifying, @unchecked Sendable {
    static let shared = DeviceIdentityStore()

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        key: String = "WhisperAnywhere.DeviceIdentifier"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func deviceID() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}
