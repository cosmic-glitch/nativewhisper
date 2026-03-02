import AVFoundation
import Foundation

enum BackendTranscriptionError: LocalizedError, Equatable {
    case backendNotConfigured
    case notSignedIn
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "BACKEND_BASE_URL is not configured."
        case .notSignedIn:
            return "Sign in is required before dictation."
        case .invalidResponse:
            return "Received an invalid response from Whisper Anywhere backend."
        case .httpError(let statusCode, let message):
            return "Backend transcription failed (\(statusCode)): \(message)"
        case .decodingFailed:
            return "Failed to decode backend transcription response."
        case .emptyTranscript:
            return "Backend returned an empty transcript."
        }
    }
}

struct BackendTranscriptionClient: Transcribing {
    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let message: String?
        }

        let error: Payload?
    }

    private let baseURL: URL
    private let session: HTTPSession
    private let sessionStore: SessionStoring
    private let authClient: BackendAuthenticating
    private let deviceIDProvider: DeviceIdentifying
    private let language: String
    private let appVersion: String

    init(
        config: AppConfig,
        sessionStore: SessionStoring,
        authClient: BackendAuthenticating,
        deviceIDProvider: DeviceIdentifying = DeviceIdentityStore.shared,
        session: HTTPSession = URLSession.shared,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    ) throws {
        guard let backendBaseURL = config.backendBaseURL else {
            throw BackendTranscriptionError.backendNotConfigured
        }

        self.baseURL = backendBaseURL
        self.session = session
        self.sessionStore = sessionStore
        self.authClient = authClient
        self.deviceIDProvider = deviceIDProvider
        self.language = config.language
        self.appVersion = appVersion
    }

    init(
        baseURL: URL,
        sessionStore: SessionStoring,
        authClient: BackendAuthenticating,
        deviceIDProvider: DeviceIdentifying = DeviceIdentityStore.shared,
        session: HTTPSession = URLSession.shared,
        language: String = "en",
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    ) {
        self.baseURL = baseURL
        self.session = session
        self.sessionStore = sessionStore
        self.authClient = authClient
        self.deviceIDProvider = deviceIDProvider
        self.language = language
        self.appVersion = appVersion
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard var authSession = sessionStore.loadSession() else {
            throw BackendTranscriptionError.notSignedIn
        }

        let audioData = try Data(contentsOf: audioURL)
        let durationMs = Self.audioDurationMs(for: audioURL)
        let deviceID = deviceIDProvider.deviceID()

        do {
            return try await performTranscription(
                accessToken: authSession.accessToken,
                audioData: audioData,
                filename: audioURL.lastPathComponent,
                durationMs: durationMs,
                deviceID: deviceID
            )
        } catch let error as BackendTranscriptionError {
            guard case .httpError(let statusCode, _) = error, statusCode == 401 else {
                throw error
            }

            let refreshed = try await authClient.refreshSession(refreshToken: authSession.refreshToken)
            try sessionStore.saveSession(refreshed)
            authSession = refreshed

            return try await performTranscription(
                accessToken: authSession.accessToken,
                audioData: audioData,
                filename: audioURL.lastPathComponent,
                durationMs: durationMs,
                deviceID: deviceID
            )
        }
    }

    private func performTranscription(
        accessToken: String,
        audioData: Data,
        filename: String,
        durationMs: Int,
        deviceID: String
    ) async throws -> String {
        let request = makeRequest(
            accessToken: accessToken,
            audioData: audioData,
            filename: filename,
            durationMs: durationMs,
            deviceID: deviceID
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw BackendTranscriptionError.invalidResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw BackendTranscriptionError.httpError(statusCode: http.statusCode, message: parseErrorMessage(data))
        }

        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw BackendTranscriptionError.decodingFailed
        }

        let transcript = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw BackendTranscriptionError.emptyTranscript
        }

        return transcript
    }

    private func makeRequest(
        accessToken: String,
        audioData: Data,
        filename: String,
        durationMs: Int,
        deviceID: String
    ) -> URLRequest {
        var endpoint = baseURL
        endpoint.append(path: "api/transcribe")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField("language", value: language, boundary: boundary, to: &body)
        appendField("deviceId", value: deviceID, boundary: boundary, to: &body)
        appendField("durationMs", value: String(durationMs), boundary: boundary, to: &body)
        appendField("clientVersion", value: appVersion, boundary: boundary, to: &body)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return request
    }

    private func appendField(_ name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func parseErrorMessage(_ data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }

        if let fallback = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback
        }

        return "Unknown backend error"
    }

    private static func audioDurationMs(for url: URL) -> Int {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return 0
        }

        let sampleRate = audioFile.fileFormat.sampleRate
        guard sampleRate > 0 else {
            return 0
        }

        let seconds = Double(audioFile.length) / sampleRate
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }

        return Int(seconds * 1000)
    }
}
