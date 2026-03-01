import Foundation

struct AppConfig {
    let openAIKey: String
    let model: String
    let language: String

    var hasAPIKey: Bool {
        !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppConfig {
        AppConfig(
            openAIKey: environment["OPENAI_API_KEY"] ?? "",
            model: "whisper-1",
            language: "en"
        )
    }
}
