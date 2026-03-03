import Foundation

enum TranscriptionRoute: String, CaseIterable, Sendable {
    case hosted
    case direct

    var label: String {
        switch self {
        case .hosted:
            return "Hosted"
        case .direct:
            return "Direct OpenAI"
        }
    }
}

protocol TranscriptionRouteStoring: Sendable {
    func currentRoute() -> TranscriptionRoute
    func saveRoute(_ route: TranscriptionRoute)
}

final class TranscriptionRouteStore: TranscriptionRouteStoring, @unchecked Sendable {
    static let shared = TranscriptionRouteStore()

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "WhisperAnywhere.TranscriptionRoute"
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
    }

    func currentRoute() -> TranscriptionRoute {
        lock.lock()
        defer { lock.unlock() }

        if let rawValue = defaults.string(forKey: defaultsKey),
           let route = TranscriptionRoute(rawValue: rawValue) {
            return route
        }

        defaults.set(TranscriptionRoute.hosted.rawValue, forKey: defaultsKey)
        return .hosted
    }

    func saveRoute(_ route: TranscriptionRoute) {
        lock.lock()
        defaults.set(route.rawValue, forKey: defaultsKey)
        lock.unlock()
    }
}
