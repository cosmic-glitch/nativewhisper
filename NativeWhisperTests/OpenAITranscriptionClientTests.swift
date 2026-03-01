import Foundation
import XCTest
@testable import NativeWhisper

final class OpenAITranscriptionClientTests: XCTestCase {
    func testMakeRequestIncludesRequiredFields() throws {
        let audioURL = makeAudioFileURL(contents: "abc123")
        let session = MockHTTPSession()
        let client = OpenAITranscriptionClient(
            config: AppConfig(openAIKey: "secret", model: "whisper-1", language: "en"),
            session: session
        )

        let request = try client.makeRequest(audioURL: audioURL)

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")

        let contentType = request.value(forHTTPHeaderField: "Content-Type")
        XCTAssertNotNil(contentType)
        XCTAssertTrue(contentType?.contains("multipart/form-data") == true)

        let bodyString = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertNotNil(bodyString)
        XCTAssertTrue(bodyString?.contains("name=\"model\"\r\n\r\nwhisper-1") == true)
        XCTAssertTrue(bodyString?.contains("name=\"language\"\r\n\r\nen") == true)
        XCTAssertTrue(bodyString?.contains("name=\"response_format\"\r\n\r\njson") == true)
        XCTAssertTrue(bodyString?.contains("name=\"temperature\"\r\n\r\n0") == true)
        XCTAssertTrue(bodyString?.contains("name=\"file\"; filename=\"") == true)
    }

    func testTranscribeThrowsForHTTPError() async throws {
        let audioURL = makeAudioFileURL(contents: "payload")

        let session = MockHTTPSession()
        session.response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        session.data = Data("unauthorized".utf8)

        let client = OpenAITranscriptionClient(
            config: AppConfig(openAIKey: "bad-key", model: "whisper-1", language: "en"),
            session: session
        )

        do {
            _ = try await client.transcribe(audioURL: audioURL)
            XCTFail("Expected error")
        } catch let error as OpenAITranscriptionError {
            switch error {
            case .httpError(let statusCode, _):
                XCTAssertEqual(statusCode, 401)
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testTranscribeThrowsForMalformedJSON() async throws {
        let audioURL = makeAudioFileURL(contents: "payload")

        let session = MockHTTPSession()
        session.response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        session.data = Data("not-json".utf8)

        let client = OpenAITranscriptionClient(
            config: AppConfig(openAIKey: "key", model: "whisper-1", language: "en"),
            session: session
        )

        do {
            _ = try await client.transcribe(audioURL: audioURL)
            XCTFail("Expected decoding error")
        } catch let error as OpenAITranscriptionError {
            XCTAssertEqual(error, .decodingFailed)
        }
    }

    private func makeAudioFileURL(contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-test-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? Data(contents.utf8).write(to: url)
        return url
    }
}

private final class MockHTTPSession: HTTPSession, @unchecked Sendable {
    var data = Data()
    var response: URLResponse = HTTPURLResponse(
        url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error {
            throw error
        }
        return (data, response)
    }
}
