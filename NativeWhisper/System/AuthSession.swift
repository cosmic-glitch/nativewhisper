import Foundation

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String
    let email: String

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(30)
    }
}

struct QuotaStatus: Equatable, Sendable {
    let remainingToday: Int
    let deviceCap: Int
    let globalBudgetState: String
    let resetAt: Date?

    var isServicePaused: Bool {
        globalBudgetState.lowercased() == "paused"
    }
}
