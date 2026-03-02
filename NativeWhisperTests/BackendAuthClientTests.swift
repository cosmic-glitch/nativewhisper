import Foundation
import XCTest
@testable import NativeWhisper

final class BackendAuthClientTests: XCTestCase {
    func testBeginGoogleSignInBuildsExpectedRequest() async throws {
        let session = MockHTTPSessionForBackendAuth()
        session.responses = [
            MockHTTPSessionForBackendAuth.Response(statusCode: 200, body: Data("{\"authorizeURL\":\"https://example.com/oauth\"}".utf8))
        ]

        let client = BackendAuthClient(baseURL: URL(string: "https://example.com")!, session: session)

        let authorizeURL = try await client.beginGoogleSignIn(
            deviceID: "device-1",
            appVersion: "1.2.3"
        )
        XCTAssertEqual(authorizeURL.absoluteString, "https://example.com/oauth")

        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/auth/google/start")
        XCTAssertEqual(request.httpMethod, "POST")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["deviceId"] as? String, "device-1")
        XCTAssertEqual(object["appVersion"] as? String, "1.2.3")
    }

    func testCompleteGoogleSignInDecodesSession() async throws {
        let session = MockHTTPSessionForBackendAuth()
        session.responses = [
            MockHTTPSessionForBackendAuth.Response(
                statusCode: 200,
                body: Data("{\"user\":{\"id\":\"u1\",\"email\":\"friend@example.com\"}}".utf8)
            )
        ]

        let client = BackendAuthClient(baseURL: URL(string: "https://example.com")!, session: session)

        let start = Date()
        let authSession = try await client.completeGoogleSignIn(
            oauthTokens: GoogleOAuthTokens(accessToken: "a", refreshToken: "r", expiresIn: 1800),
            deviceID: "device-1"
        )

        XCTAssertEqual(authSession.accessToken, "a")
        XCTAssertEqual(authSession.refreshToken, "r")
        XCTAssertEqual(authSession.userId, "u1")
        XCTAssertEqual(authSession.email, "friend@example.com")
        XCTAssertGreaterThan(authSession.expiresAt.timeIntervalSince(start), 1700)

        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/auth/google/session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer a")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["deviceId"] as? String, "device-1")
    }
}

private final class MockHTTPSessionForBackendAuth: HTTPSession, @unchecked Sendable {
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
