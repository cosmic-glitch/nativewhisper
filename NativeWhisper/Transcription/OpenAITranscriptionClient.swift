import Foundation

protocol Transcribing: Sendable {
    func transcribe(audioURL: URL) async throws -> String
}

protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

enum OpenAITranscriptionError: LocalizedError, Equatable {
    case invalidAPIKey
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "OPENAI_API_KEY is not configured."
        case .invalidResponse:
            return "Received an invalid response from OpenAI."
        case .httpError(let statusCode, let message):
            return "OpenAI transcription failed (\(statusCode)): \(message)"
        case .decodingFailed:
            return "Failed to decode OpenAI transcription response."
        case .emptyTranscript:
            return "OpenAI returned an empty transcript."
        }
    }
}

struct OpenAITranscriptionClient: Transcribing {
    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private let config: AppConfig
    private let session: HTTPSession

    init(config: AppConfig, session: HTTPSession = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func transcribe(audioURL: URL) async throws -> String {
        let request = try makeRequest(audioURL: audioURL)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw OpenAITranscriptionError.httpError(statusCode: httpResponse.statusCode, message: serverMessage)
        }

        guard let transcription = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw OpenAITranscriptionError.decodingFailed
        }

        let trimmed = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAITranscriptionError.emptyTranscript
        }

        return trimmed
    }

    func makeRequest(audioURL: URL) throws -> URLRequest {
        guard config.hasAPIKey else {
            throw OpenAITranscriptionError.invalidAPIKey
        }

        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.openAIKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeMultipartBody(audioURL: audioURL, boundary: boundary)

        return request
    }

    private func makeMultipartBody(audioURL: URL, boundary: String) throws -> Data {
        let audioData = try Data(contentsOf: audioURL)

        var body = Data()
        appendField("model", value: config.model, boundary: boundary, to: &body)
        appendField("language", value: config.language, boundary: boundary, to: &body)
        appendField("response_format", value: "json", boundary: boundary, to: &body)
        appendField("temperature", value: "0", boundary: boundary, to: &body)

        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func appendField(_ name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
}
