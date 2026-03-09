import Foundation
import XCTest
@testable import WhisperAnywhere

final class OpenAIEditClientTests: XCTestCase {
    func testMakeRequestUsesGPT5MiniAndIncludesEditPayload() throws {
        let session = MockEditHTTPSession()
        let client = OpenAIEditClient(
            config: AppConfig(openAIKey: "secret", model: "unused", language: "en"),
            session: session
        )

        let request = try client.makeRequest(selectedText: "Original text", instructions: "Shorten it")

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-5-mini")
        XCTAssertEqual(json["reasoning_effort"] as? String, "minimal")
        XCTAssertNil(json["temperature"])

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        let systemContent = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(systemContent.contains("both come from speech transcription"))
        XCTAssertTrue(systemContent.contains("Treat the edit instructions as the main signal"))
        XCTAssertTrue(systemContent.contains("spells a word letter-by-letter"))
        XCTAssertTrue(systemContent.contains("Do not force all-uppercase"))
        XCTAssertTrue(systemContent.contains("Make the smallest edit"))
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("Original text") == true)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("Shorten it") == true)
    }

    func testEditThrowsForHTTPError() async {
        let session = MockEditHTTPSession()
        session.response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        session.data = Data("server exploded".utf8)

        let client = OpenAIEditClient(
            config: AppConfig(openAIKey: "key", model: "unused", language: "en"),
            session: session
        )

        do {
            _ = try await client.edit(selectedText: "A", instructions: "B")
            XCTFail("Expected HTTP error")
        } catch let error as OpenAIEditError {
            switch error {
            case .httpError(let statusCode, _):
                XCTAssertEqual(statusCode, 500)
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEditPreservesModelOutputText() async throws {
        let session = MockEditHTTPSession()
        session.response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        session.data = Data("""
        {
          "choices": [
            { "message": { "content": "  Final edited text\\n" } }
          ]
        }
        """.utf8)

        let client = OpenAIEditClient(
            config: AppConfig(openAIKey: "key", model: "unused", language: "en"),
            session: session
        )

        let result = try await client.edit(selectedText: "draft", instructions: "cleanup")
        XCTAssertEqual(result, "  Final edited text\n")
    }
}

private final class MockEditHTTPSession: HTTPSession, @unchecked Sendable {
    var data = Data()
    var response: URLResponse = HTTPURLResponse(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        (data, response)
    }
}
