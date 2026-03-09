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
    private static let requestLogURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WhisperAnywhere/edit-request.log")

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
        Self.persistRequestLog(for: request)
        Self.logger.info(
            "Submitting edit request model=gpt-5-mini selectedChars=\(selectedText.count, privacy: .public) instructionChars=\(instructions.count, privacy: .public)"
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
            model: "gpt-5-mini",
            reasoningEffort: "minimal",
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    You are a precise voice-text editor.
                    The selected text and the spoken edit instructions both come from speech transcription, so either may contain recognition errors, false starts, filler words, self-corrections, or imprecise wording.
                    Infer the user's intended final text from both inputs. Treat the edit instructions as the main signal, but do not follow obvious transcription mistakes literally.
                    If the user spells a word letter-by-letter (for example: "replace with S T A C K"), infer the intended word and apply that replacement.
                    Do not force all-uppercase just because letters were spoken individually; use normal casing that fits the instruction and surrounding text.
                    Make the smallest edit that best matches the likely intent, and return only the final edited text.
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

    private static func persistRequestLog(for request: URLRequest) {
        guard let url = request.url?.absoluteString,
              let method = request.httpMethod,
              let body = request.httpBody,
              let formattedBody = formattedJSONString(from: body) else {
            logger.error("Edit request logging skipped: request body unavailable")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = """
        === \(timestamp) ===
        \(method) \(url)
        \(formattedBody)

        """

        do {
            let logURL = requestLogURL
            let directoryURL = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            } else {
                try Data(entry.utf8).write(to: logURL, options: .atomic)
            }

            logger.info(
                "Persisted edit request payload bytes=\(body.count, privacy: .public) path=\(logURL.path, privacy: .public)"
            )
        } catch {
            logger.error("Failed to persist edit request payload error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func formattedJSONString(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: prettyData, encoding: .utf8) else {
            return String(data: data, encoding: .utf8)
        }

        return string
    }
}
