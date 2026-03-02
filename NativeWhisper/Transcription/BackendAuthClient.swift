import Foundation

protocol BackendAuthenticating: Sendable {
    func beginGoogleSignIn(deviceID: String, appVersion: String) async throws -> URL
    func completeGoogleSignIn(oauthTokens: GoogleOAuthTokens, deviceID: String) async throws -> AuthSession
    func refreshSession(refreshToken: String) async throws -> AuthSession
    func fetchQuota(accessToken: String, deviceID: String) async throws -> QuotaStatus
}

enum BackendAuthError: LocalizedError, Equatable {
    case backendNotConfigured
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed
    case invalidAuthorizeURL
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
        case .invalidAuthorizeURL:
            return "Backend returned an invalid Google sign-in URL."
        case .missingSessionData:
            return "Backend auth response is missing session data."
        }
    }
}

struct BackendAuthClient: BackendAuthenticating {
    private struct GoogleStartRequest: Encodable {
        let deviceId: String
        let appVersion: String
    }

    private struct GoogleStartResponse: Decodable {
        let authorizeURL: String

        private enum CodingKeys: String, CodingKey {
            case authorizeURL
            case authorizeUrl
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try container.decodeIfPresent(String.self, forKey: .authorizeURL), !value.isEmpty {
                authorizeURL = value
                return
            }
            if let value = try container.decodeIfPresent(String.self, forKey: .authorizeUrl), !value.isEmpty {
                authorizeURL = value
                return
            }
            throw DecodingError.keyNotFound(
                CodingKeys.authorizeURL,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing authorize URL")
            )
        }
    }

    private struct GoogleSessionRequest: Encodable {
        let deviceId: String
    }

    private struct GoogleSessionResponse: Decodable {
        struct UserPayload: Decodable {
            let id: String
            let email: String
        }

        let user: UserPayload
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

    func beginGoogleSignIn(deviceID: String, appVersion: String) async throws -> URL {
        let payload = GoogleStartRequest(
            deviceId: deviceID,
            appVersion: appVersion
        )

        let data = try await performJSONRequest(path: "/api/auth/google/start", method: "POST", body: payload)

        guard let decoded = try? JSONDecoder().decode(GoogleStartResponse.self, from: data) else {
            throw BackendAuthError.decodingFailed
        }

        guard let authorizeURL = URL(string: decoded.authorizeURL) else {
            throw BackendAuthError.invalidAuthorizeURL
        }

        return authorizeURL
    }

    func completeGoogleSignIn(oauthTokens: GoogleOAuthTokens, deviceID: String) async throws -> AuthSession {
        guard !oauthTokens.accessToken.isEmpty, !oauthTokens.refreshToken.isEmpty else {
            throw BackendAuthError.missingSessionData
        }

        let payload = GoogleSessionRequest(deviceId: deviceID)
        let data = try await performAuthorizedJSONRequest(
            path: "/api/auth/google/session",
            method: "POST",
            body: payload,
            accessToken: oauthTokens.accessToken
        )

        guard let decoded = try? JSONDecoder().decode(GoogleSessionResponse.self, from: data) else {
            throw BackendAuthError.decodingFailed
        }

        let expiresIn = max(60, oauthTokens.expiresIn ?? 3600)

        return AuthSession(
            accessToken: oauthTokens.accessToken,
            refreshToken: oauthTokens.refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userId: decoded.user.id,
            email: decoded.user.email
        )
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

    private func performAuthorizedJSONRequest<T: Encodable>(
        path: String,
        method: String,
        body: T,
        accessToken: String
    ) async throws -> Data {
        guard let url = buildURL(path: path) else {
            throw BackendAuthError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
