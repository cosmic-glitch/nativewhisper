import Foundation

protocol BackendAuthenticating: Sendable {
    func startOTP(email: String, turnstileToken: String, deviceID: String, appVersion: String) async throws
    func verifyOTP(email: String, otp: String, deviceID: String) async throws -> AuthSession
    func refreshSession(refreshToken: String) async throws -> AuthSession
    func fetchQuota(accessToken: String, deviceID: String) async throws -> QuotaStatus
}

enum BackendAuthError: LocalizedError, Equatable {
    case backendNotConfigured
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed
    case missingSessionData

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "BACKEND_BASE_URL is not configured."
        case .invalidRequest:
            return "The request is invalid."
        case .invalidResponse:
            return "Received an invalid response from the backend."
        case .httpError(let statusCode, let message):
            return "Backend auth failed (\(statusCode)): \(message)"
        case .decodingFailed:
            return "Failed to decode backend auth response."
        case .missingSessionData:
            return "Backend auth response is missing session data."
        }
    }
}

struct BackendAuthClient: BackendAuthenticating {
    private struct StartRequest: Encodable {
        let email: String
        let turnstileToken: String
        let deviceId: String
        let appVersion: String
    }

    private struct VerifyRequest: Encodable {
        let email: String
        let otp: String
        let deviceId: String
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct SessionResponse: Decodable {
        struct UserPayload: Decodable {
            let id: String
            let email: String
        }

        let accessToken: String
        let refreshToken: String
        let expiresAt: Double
        let user: UserPayload

        var authSession: AuthSession {
            let seconds: TimeInterval = expiresAt > 10_000_000_000 ? expiresAt / 1_000 : expiresAt
            return AuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date(timeIntervalSince1970: seconds),
                userId: user.id,
                email: user.email
            )
        }
    }

    private struct QuotaResponse: Decodable {
        let remainingToday: Int
        let deviceCap: Int
        let globalBudgetState: String
        let resetAt: String?

        var quotaStatus: QuotaStatus {
            let resetDate: Date?
            if let resetAt {
                resetDate = ISO8601DateFormatter().date(from: resetAt)
            } else {
                resetDate = nil
            }

            return QuotaStatus(
                remainingToday: remainingToday,
                deviceCap: deviceCap,
                globalBudgetState: globalBudgetState,
                resetAt: resetDate
            )
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let code: String?
            let message: String?
            let details: Details?

            struct Details: Decodable {
                let message: String?
            }
        }

        let error: Payload?
    }

    private let baseURL: URL
    private let session: HTTPSession

    init(config: AppConfig, session: HTTPSession = URLSession.shared) throws {
        guard let backendBaseURL = config.backendBaseURL else {
            throw BackendAuthError.backendNotConfigured
        }

        self.baseURL = backendBaseURL
        self.session = session
    }

    init(baseURL: URL, session: HTTPSession = URLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func startOTP(email: String, turnstileToken: String, deviceID: String, appVersion: String) async throws {
        let payload = StartRequest(
            email: email,
            turnstileToken: turnstileToken,
            deviceId: deviceID,
            appVersion: appVersion
        )

        _ = try await performJSONRequest(path: "/api/auth/start", method: "POST", body: payload)
    }

    func verifyOTP(email: String, otp: String, deviceID: String) async throws -> AuthSession {
        let payload = VerifyRequest(email: email, otp: otp, deviceId: deviceID)
        let data = try await performJSONRequest(path: "/api/auth/verify", method: "POST", body: payload)

        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data) else {
            throw BackendAuthError.decodingFailed
        }

        guard !decoded.accessToken.isEmpty, !decoded.refreshToken.isEmpty else {
            throw BackendAuthError.missingSessionData
        }

        return decoded.authSession
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        let payload = RefreshRequest(refreshToken: refreshToken)
        let data = try await performJSONRequest(path: "/api/auth/refresh", method: "POST", body: payload)

        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data) else {
            throw BackendAuthError.decodingFailed
        }

        guard !decoded.accessToken.isEmpty, !decoded.refreshToken.isEmpty else {
            throw BackendAuthError.missingSessionData
        }

        return decoded.authSession
    }

    func fetchQuota(accessToken: String, deviceID: String) async throws -> QuotaStatus {
        let data = try await performAuthorizedGet(
            path: "/api/quota",
            query: ["deviceId": deviceID],
            accessToken: accessToken
        )

        guard let decoded = try? JSONDecoder().decode(QuotaResponse.self, from: data) else {
            throw BackendAuthError.decodingFailed
        }

        return decoded.quotaStatus
    }

    private func performJSONRequest<T: Encodable>(path: String, method: String, body: T) async throws -> Data {
        guard let url = buildURL(path: path) else {
            throw BackendAuthError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        return try unwrapHTTPData(data: data, response: response)
    }

    private func performAuthorizedGet(path: String, query: [String: String], accessToken: String) async throws -> Data {
        guard let url = buildURL(path: path, query: query) else {
            throw BackendAuthError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        return try unwrapHTTPData(data: data, response: response)
    }

    private func unwrapHTTPData(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw BackendAuthError.httpError(statusCode: http.statusCode, message: parseErrorMessage(from: data))
        }

        return data
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            if let message = envelope.error?.message, !message.isEmpty {
                return message
            }
            if let detailsMessage = envelope.error?.details?.message, !detailsMessage.isEmpty {
                return detailsMessage
            }
        }

        let fallback = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallback, !fallback.isEmpty {
            return fallback
        }

        return "Unknown backend error"
    }

    private func buildURL(path: String, query: [String: String] = [:]) -> URL? {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var url = baseURL
        url.append(path: trimmedPath)

        guard !query.isEmpty else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.queryItems = query.map { key, value in
            URLQueryItem(name: key, value: value)
        }

        return components.url
    }
}
