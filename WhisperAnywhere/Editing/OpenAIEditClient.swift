import Foundation
import OSLog

protocol TextEditing: Sendable {
    func edit(selectedText: String, instructions: String) async throws -> String
}

struct NoopTextEditor: TextEditing {
    func edit(selectedText: String, instructions: String) async throws -> String {
        selectedText
    }
}

enum OpenAIEditError: LocalizedError, Equatable {
    case invalidAPIKey
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed
    case emptyEdit

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "OPENAI_API_KEY is not configured."
        case .invalidResponse:
            return "Received an invalid response from OpenAI."
        case .httpError(let statusCode, let message):
            return "OpenAI edit request failed (\(statusCode)): \(message)"
        case .decodingFailed:
            return "Failed to decode OpenAI edit response."
        case .emptyEdit:
            return "OpenAI returned an empty edit."
        }
    }
}

struct OpenAIEditClient: TextEditing {
    private static let logger = Logger(subsystem: "ai.whisperanywhere.app", category: "OpenAIEditClient")

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let reasoningEffort: String
        let messages: [ChatMessage]

        enum CodingKeys: String, CodingKey {
            case model
            case reasoningEffort = "reasoning_effort"
            case messages
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private let config: AppConfig
    private let session: HTTPSession

    init(config: AppConfig, session: HTTPSession = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func edit(selectedText: String, instructions: String) async throws -> String {
        let request = try makeRequest(selectedText: selectedText, instructions: instructions)
        Self.logger.info(
            "Submitting edit request model=gpt-5-nano selectedChars=\(selectedText.count, privacy: .public) instructionChars=\(instructions.count, privacy: .public)"
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Edit request returned non-HTTP response")
            throw OpenAIEditError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            Self.logger.error("Edit request failed status=\(httpResponse.statusCode, privacy: .public) body=\(serverMessage, privacy: .private(mask: .hash))")
            throw OpenAIEditError.httpError(statusCode: httpResponse.statusCode, message: serverMessage)
        }

        guard let completion = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            let diagnostic = decodeFailureDiagnostic(from: data)
            Self.logger.error("Edit response decode failed diagnostic=\(diagnostic, privacy: .public)")
            throw OpenAIEditError.decodingFailed
        }

        guard let editedText = completion.choices.first?.message.content,
              !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.error("Edit response was empty")
            throw OpenAIEditError.emptyEdit
        }

        Self.logger.info("Edit response received editedChars=\(editedText.count, privacy: .public)")
        return editedText
    }

    func makeRequest(selectedText: String, instructions: String) throws -> URLRequest {
        guard config.hasAPIKey else {
            throw OpenAIEditError.invalidAPIKey
        }

        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ChatRequest(
            model: "gpt-5-nano",
            reasoningEffort: "minimal",
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    You are a precise text editor.
                    Apply the spoken edit instructions to the selected text and return only the final edited text.
                    If the user spells a word letter-by-letter (for example: "replace with S T A C K"), infer the intended word and apply that replacement.
                    Do not force all-uppercase just because letters were spoken individually; use normal casing that fits the instruction and surrounding text.
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    Selected text:
                    \(selectedText)

                    Spoken edit instructions:
                    \(instructions)
                    """
                )
            ]
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    private func decodeFailureDiagnostic(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return "non-json payload (\(data.count) bytes)"
        }

        let topLevelKeys = dictionary.keys.sorted().joined(separator: ",")
        if let choices = dictionary["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] {
            return "keys=[\(topLevelKeys)] contentType=\(String(describing: type(of: content)))"
        }

        return "keys=[\(topLevelKeys)]"
    }
}
