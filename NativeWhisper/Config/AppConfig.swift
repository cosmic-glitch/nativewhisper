import Foundation

struct AppConfig {
    enum TranscriptionMode: Equatable {
        case hosted
        case personalKey
    }

    private let keyProvider: @Sendable () -> String
    let transcriptionMode: TranscriptionMode
    let backendBaseURL: URL?
    let allowLegacyPersonalKeyEntry: Bool
    let model: String
    let language: String

    init(
        openAIKey: String,
        model: String,
        language: String,
        transcriptionMode: TranscriptionMode = .personalKey,
        backendBaseURL: URL? = nil,
        allowLegacyPersonalKeyEntry: Bool = true
    ) {
        self.keyProvider = { openAIKey }
        self.transcriptionMode = transcriptionMode
        self.backendBaseURL = backendBaseURL
        self.allowLegacyPersonalKeyEntry = allowLegacyPersonalKeyEntry
        self.model = model
        self.language = language
    }

    init(
        keyProvider: @escaping @Sendable () -> String,
        model: String,
        language: String,
        transcriptionMode: TranscriptionMode,
        backendBaseURL: URL?,
        allowLegacyPersonalKeyEntry: Bool
    ) {
        self.keyProvider = keyProvider
        self.transcriptionMode = transcriptionMode
        self.backendBaseURL = backendBaseURL
        self.allowLegacyPersonalKeyEntry = allowLegacyPersonalKeyEntry
        self.model = model
        self.language = language
    }

    var openAIKey: String {
        keyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        if hostedModeEnabled {
            return backendBaseURL != nil
        }
        return !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hostedModeEnabled: Bool {
        transcriptionMode == .hosted
    }

    static func load(apiKeyStore: APIKeyProviding = APIKeyStore.shared) -> AppConfig {
        let environment = ProcessInfo.processInfo.environment
        let hostedModeValue = (environment["WHISPER_ANYWHERE_HOSTED_MODE"] ?? "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hostedModeEnabled = hostedModeValue != "false"

        let backendBaseURLString = (environment["BACKEND_BASE_URL"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backendBaseURL = URL(string: backendBaseURLString)

        let allowLegacyKeyValue = (environment["ALLOW_LEGACY_PERSONAL_KEY_ENTRY"] ?? "false")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowLegacyPersonalKeyEntry = allowLegacyKeyValue == "true"

        return AppConfig(
            keyProvider: {
                apiKeyStore.currentAPIKey()
            },
            model: "whisper-1",
            language: "en",
            transcriptionMode: hostedModeEnabled ? .hosted : .personalKey,
            backendBaseURL: backendBaseURL,
            allowLegacyPersonalKeyEntry: allowLegacyPersonalKeyEntry
        )
    }
}
