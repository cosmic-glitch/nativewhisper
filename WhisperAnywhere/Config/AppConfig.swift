import Foundation

struct AppConfig {
    private let keyProvider: @Sendable () -> String
    let model: String
    let language: String
    let backendBaseURL: URL?

    init(
        openAIKey: String,
        model: String,
        language: String,
        backendBaseURL: URL? = URL(string: "https://whisperanywhere.app")
    ) {
        self.keyProvider = { openAIKey }
        self.model = model
        self.language = language
        self.backendBaseURL = backendBaseURL
    }

    init(
        keyProvider: @escaping @Sendable () -> String,
        model: String,
        language: String,
        backendBaseURL: URL? = URL(string: "https://whisperanywhere.app")
    ) {
        self.keyProvider = keyProvider
        self.model = model
        self.language = language
        self.backendBaseURL = backendBaseURL
    }

    var openAIKey: String {
        keyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        return !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(apiKeyStore: APIKeyProviding = InMemoryAPIKeyProvider.shared) -> AppConfig {
        return AppConfig(
            keyProvider: {
                apiKeyStore.currentAPIKey()
            },
            model: "gpt-4o-mini-transcribe",
            language: "en"
        )
    }
}
