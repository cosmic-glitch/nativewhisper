import Foundation
import XCTest
@testable import NativeWhisper

final class BackendAuthClientTests: XCTestCase {
    func testStartOTPBuildsExpectedRequest() async throws {
        let session = MockHTTPSessionForBackendAuth()
        session.responses = [
            MockHTTPSessionForBackendAuth.Response(statusCode: 200, body: Data("{\"ok\":true}".utf8))
        ]

        let client = BackendAuthClient(baseURL: URL(string: "https://example.com")!, session: session)

        try await client.startOTP(
            email: "friend@example.com",
            turnstileToken: "turnstile-token",
            deviceID: "device-1",
            appVersion: "1.2.3"
        )

        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/auth/start")
        XCTAssertEqual(request.httpMethod, "POST")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["email"] as? String, "friend@example.com")
        XCTAssertEqual(object["turnstileToken"] as? String, "turnstile-token")
        XCTAssertEqual(object["deviceId"] as? String, "device-1")
        XCTAssertEqual(object["appVersion"] as? String, "1.2.3")
    }

    func testVerifyOTPDecodesSession() async throws {
        let session = MockHTTPSessionForBackendAuth()
        session.responses = [
            MockHTTPSessionForBackendAuth.Response(
                statusCode: 200,
                body: Data("{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":1735700000,\"user\":{\"id\":\"u1\",\"email\":\"friend@example.com\"}}".utf8)
            )
        ]

        let client = BackendAuthClient(baseURL: URL(string: "https://example.com")!, session: session)

        let authSession = try await client.verifyOTP(email: "friend@example.com", otp: "123456", deviceID: "device-1")

        XCTAssertEqual(authSession.accessToken, "a")
        XCTAssertEqual(authSession.refreshToken, "r")
        XCTAssertEqual(authSession.userId, "u1")
        XCTAssertEqual(authSession.email, "friend@example.com")
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
