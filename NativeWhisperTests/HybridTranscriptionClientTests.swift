import Foundation
import XCTest
@testable import NativeWhisper

final class HybridTranscriptionClientTests: XCTestCase {
    func testRoutesToDirectClientWhenRouteIsDirect() async throws {
        let hosted = MockTranscriber(result: .success("hosted"))
        let direct = MockTranscriber(result: .success("direct"))
        let client = HybridTranscriptionClient(
            routeProvider: { .direct },
            hostedClient: hosted,
            directClient: direct
        )

        let text = try await client.transcribe(audioURL: URL(fileURLWithPath: "/tmp/demo.m4a"))
        XCTAssertEqual(text, "direct")
        XCTAssertEqual(hosted.calls, 0)
        XCTAssertEqual(direct.calls, 1)
    }

    func testRoutesToHostedClientWhenRouteIsHosted() async throws {
        let hosted = MockTranscriber(result: .success("hosted"))
        let direct = MockTranscriber(result: .success("direct"))
        let client = HybridTranscriptionClient(
            routeProvider: { .hosted },
            hostedClient: hosted,
            directClient: direct
        )

        let text = try await client.transcribe(audioURL: URL(fileURLWithPath: "/tmp/demo.m4a"))
        XCTAssertEqual(text, "hosted")
        XCTAssertEqual(hosted.calls, 1)
        XCTAssertEqual(direct.calls, 0)
    }

    func testDoesNotFallbackWhenDirectFails() async {
        let hosted = MockTranscriber(result: .success("hosted"))
        let direct = MockTranscriber(result: .failure(OpenAITranscriptionError.invalidAPIKey))
        let client = HybridTranscriptionClient(
            routeProvider: { .direct },
            hostedClient: hosted,
            directClient: direct
        )

        do {
            _ = try await client.transcribe(audioURL: URL(fileURLWithPath: "/tmp/demo.m4a"))
            XCTFail("Expected direct failure to be thrown.")
        } catch let error as OpenAITranscriptionError {
            XCTAssertEqual(error, .invalidAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(hosted.calls, 0)
        XCTAssertEqual(direct.calls, 1)
    }
}

private final class MockTranscriber: Transcribing, @unchecked Sendable {
    private let result: Result<String, Error>
    private(set) var calls = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func transcribe(audioURL: URL) async throws -> String {
        calls += 1
        return try result.get()
    }
}
