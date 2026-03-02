import Foundation
import XCTest
@testable import NativeWhisper

final class BackendTranscriptionClientTests: XCTestCase {
    func testTranscribeUsesBackendBearerSessionToken() async throws {
        let audioURL = makeAudioFileURL(contents: "audio")
        let initialSession = AuthSession(
            accessToken: "session-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(600),
            userId: "user-1",
            email: "u@example.com"
        )

        let sessionStore = MockSessionStore(initial: initialSession)
        let authClient = MockBackendAuthClient(nextRefreshedSession: initialSession)
        let httpSession = MockHTTPSessionForBackendTranscription()
        httpSession.responses = [
            MockHTTPSessionForBackendTranscription.Response(
                statusCode: 200,
                body: Data("{\"text\":\"hello world\"}".utf8)
            )
        ]

        let client = BackendTranscriptionClient(
            baseURL: URL(string: "https://example.com")!,
            sessionStore: sessionStore,
            authClient: authClient,
            deviceIDProvider: StaticDeviceIDProvider(deviceID: "device-123"),
            session: httpSession,
            language: "en",
            appVersion: "1.0.0"
        )

        let transcript = try await client.transcribe(audioURL: audioURL)

        XCTAssertEqual(transcript, "hello world")
        XCTAssertEqual(httpSession.requests.count, 1)

        let request = try XCTUnwrap(httpSession.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/transcribe")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")

        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertNotNil(body)
        XCTAssertTrue(body?.contains("name=\"language\"\r\n\r\nen") == true)
        XCTAssertTrue(body?.contains("name=\"deviceId\"\r\n\r\ndevice-123") == true)
    }

    func testTranscribeRefreshesOnUnauthorizedAndRetries() async throws {
        let initialSession = AuthSession(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(-120),
            userId: "user-1",
            email: "u@example.com"
        )
        let refreshedSession = AuthSession(
            accessToken: "fresh-token",
            refreshToken: "fresh-refresh",
            expiresAt: Date().addingTimeInterval(1200),
            userId: "user-1",
            email: "u@example.com"
        )

        let audioURL = makeAudioFileURL(contents: "audio")
        let sessionStore = MockSessionStore(initial: initialSession)
        let authClient = MockBackendAuthClient(nextRefreshedSession: refreshedSession)
        let httpSession = MockHTTPSessionForBackendTranscription()
        httpSession.responses = [
            MockHTTPSessionForBackendTranscription.Response(
                statusCode: 401,
                body: Data("{\"error\":{\"message\":\"invalid token\"}}".utf8)
            ),
            MockHTTPSessionForBackendTranscription.Response(
                statusCode: 200,
                body: Data("{\"text\":\"retry ok\"}".utf8)
            )
        ]

        let client = BackendTranscriptionClient(
            baseURL: URL(string: "https://example.com")!,
            sessionStore: sessionStore,
            authClient: authClient,
            deviceIDProvider: StaticDeviceIDProvider(deviceID: "device-123"),
            session: httpSession,
            language: "en",
            appVersion: "1.0.0"
        )

        let transcript = try await client.transcribe(audioURL: audioURL)

        XCTAssertEqual(transcript, "retry ok")
        XCTAssertEqual(authClient.refreshCalls, ["refresh-token"])
        XCTAssertEqual(sessionStore.savedSessions.last?.accessToken, "fresh-token")
        XCTAssertEqual(httpSession.requests.count, 2)
        XCTAssertEqual(httpSession.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer expired-token")
        XCTAssertEqual(httpSession.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
    }

    private func makeAudioFileURL(contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backend-transcribe-test-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? Data(contents.utf8).write(to: url)
        return url
    }
}

private final class MockSessionStore: SessionStoring, @unchecked Sendable {
    private(set) var loadedSession: AuthSession?
    private(set) var savedSessions: [AuthSession] = []

    init(initial: AuthSession?) {
        loadedSession = initial
    }

    func loadSession() -> AuthSession? {
        loadedSession
    }

    func saveSession(_ session: AuthSession) throws {
        loadedSession = session
        savedSessions.append(session)
    }

    func clearSession() throws {
        loadedSession = nil
    }
}

private struct StaticDeviceIDProvider: DeviceIdentifying {
    let value: String

    init(deviceID: String) {
        value = deviceID
    }

    func deviceID() -> String {
        value
    }
}

private final class MockBackendAuthClient: BackendAuthenticating, @unchecked Sendable {
    private let refreshedSession: AuthSession
    private(set) var refreshCalls: [String] = []

    init(nextRefreshedSession: AuthSession) {
        refreshedSession = nextRefreshedSession
    }

    func beginGoogleSignIn(deviceID: String, appVersion: String) async throws -> URL {
        URL(string: "https://example.com/oauth")!
    }

    func completeGoogleSignIn(oauthTokens: GoogleOAuthTokens, deviceID: String) async throws -> AuthSession {
        refreshedSession
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        refreshCalls.append(refreshToken)
        return refreshedSession
    }

    func fetchQuota(accessToken: String, deviceID: String) async throws -> QuotaStatus {
        QuotaStatus(remainingToday: 10, deviceCap: 100, globalBudgetState: "active", resetAt: nil)
    }
}

private final class MockHTTPSessionForBackendTranscription: HTTPSession, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    var responses: [Response] = []
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            fatalError("No mock response queued")
        }

        let next = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (next.body, response)
    }
}
