import Foundation

struct HybridTranscriptionClient: Transcribing {
    private let routeProvider: @Sendable () -> TranscriptionRoute
    private let hostedClient: Transcribing
    private let directClient: Transcribing

    init(
        routeProvider: @escaping @Sendable () -> TranscriptionRoute,
        hostedClient: Transcribing,
        directClient: Transcribing
    ) {
        self.routeProvider = routeProvider
        self.hostedClient = hostedClient
        self.directClient = directClient
    }

    func transcribe(audioURL: URL) async throws -> String {
        switch routeProvider() {
        case .hosted:
            return try await hostedClient.transcribe(audioURL: audioURL)
        case .direct:
            return try await directClient.transcribe(audioURL: audioURL)
        }
    }
}
