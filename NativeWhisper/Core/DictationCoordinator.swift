import Foundation

enum DictationState: Equatable {
    case idle
    case recording(Date)
    case transcribing
    case inserting
    case error(String)
}

enum DictationError: LocalizedError {
    case missingAPIKey
    case permissionDenied(String)
    case audioFailure(String)
    case apiFailure(String)
    case insertionFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is missing."
        case .permissionDenied(let details):
            return "Permission denied: \(details)"
        case .audioFailure(let details):
            return "Audio error: \(details)"
        case .apiFailure(let details):
            return "Transcription error: \(details)"
        case .insertionFailure(let details):
            return "Insertion error: \(details)"
        }
    }
}

actor DictationCoordinator {
    private let audioCapture: AudioCapturing
    private let transcriptionClient: Transcribing
    private let textInserter: TextInserting
    private let focusResolver: FocusResolving
    private let clipboard: ClipboardWriting
    private let permissionService: PermissionProviding
    private let notifier: Notifying
    private let config: AppConfig
    private let minimumPressDuration: TimeInterval
    private let errorDisplayDuration: UInt64
    private let stateDidChange: @Sendable (DictationState) -> Void

    private var state: DictationState = .idle
    private var recordingURL: URL?

    init(
        audioCapture: AudioCapturing,
        transcriptionClient: Transcribing,
        textInserter: TextInserting,
        focusResolver: FocusResolving,
        clipboard: ClipboardWriting,
        permissionService: PermissionProviding,
        notifier: Notifying,
        config: AppConfig,
        minimumPressDuration: TimeInterval = 0.15,
        errorDisplayDuration: UInt64 = 1_200_000_000,
        stateDidChange: @escaping @Sendable (DictationState) -> Void
    ) {
        self.audioCapture = audioCapture
        self.transcriptionClient = transcriptionClient
        self.textInserter = textInserter
        self.focusResolver = focusResolver
        self.clipboard = clipboard
        self.permissionService = permissionService
        self.notifier = notifier
        self.config = config
        self.minimumPressDuration = minimumPressDuration
        self.errorDisplayDuration = errorDisplayDuration
        self.stateDidChange = stateDidChange
    }

    func currentState() -> DictationState {
        state
    }

    func handleFnPressed() async {
        guard case .idle = state else {
            return
        }

        do {
            try await ensureReadyToRecord()
            try audioCapture.start()
            setState(.recording(Date()))
        } catch let error as DictationError {
            await transitionToError(error)
        } catch {
            await transitionToError(.audioFailure(error.localizedDescription))
        }
    }

    func handleFnReleased() async {
        guard case .recording(let startedAt) = state else {
            return
        }

        do {
            let audioURL = try audioCapture.stop()
            recordingURL = audioURL

            let pressDuration = Date().timeIntervalSince(startedAt)
            guard pressDuration >= minimumPressDuration else {
                try? FileManager.default.removeItem(at: audioURL)
                recordingURL = nil
                setState(.idle)
                return
            }

            setState(.transcribing)
            let transcript = try await transcriptionClient.transcribe(audioURL: audioURL)

            setState(.inserting)
            if focusResolver.isEditableElementFocused() {
                try textInserter.insert(transcript)
            } else {
                clipboard.copy(transcript)
                notifier.notify(
                    title: "NativeWhisper",
                    body: "No editable field focused. Transcript copied to clipboard."
                )
            }

            try? FileManager.default.removeItem(at: audioURL)
            recordingURL = nil
            setState(.idle)
        } catch let error as DictationError {
            await cleanupRecordingURL()
            await transitionToError(error)
        } catch {
            await cleanupRecordingURL()
            let mapped = mapError(error)
            await transitionToError(mapped)
        }
    }

    private func ensureReadyToRecord() async throws {
        guard config.hasAPIKey else {
            throw DictationError.missingAPIKey
        }

        let snapshot = permissionService.snapshot()

        if snapshot.microphone != .granted {
            let granted = await permissionService.requestMicrophoneAccess()
            guard granted else {
                throw DictationError.permissionDenied("Microphone access is required.")
            }
        }

        if snapshot.accessibility != .granted {
            let granted = permissionService.requestAccessibilityAccess()
            guard granted else {
                throw DictationError.permissionDenied("Accessibility access is required for text insertion.")
            }
        }

        if snapshot.inputMonitoring != .granted {
            let granted = permissionService.requestInputMonitoringAccess()
            guard granted else {
                throw DictationError.permissionDenied("Input Monitoring access is required for Fn detection.")
            }
        }
    }

    private func mapError(_ error: Error) -> DictationError {
        if let audioError = error as? AudioCaptureError {
            return .audioFailure(audioError.localizedDescription)
        }

        if let insertionError = error as? TextInsertionServiceError {
            return .insertionFailure(insertionError.localizedDescription)
        }

        if let apiError = error as? OpenAITranscriptionError {
            return .apiFailure(apiError.localizedDescription)
        }

        return .apiFailure(error.localizedDescription)
    }

    private func cleanupRecordingURL() async {
        guard let recordingURL else {
            return
        }
        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
    }

    private func transitionToError(_ error: DictationError) async {
        let message = error.localizedDescription
        setState(.error(message))

        switch error {
        case .missingAPIKey:
            notifier.notify(title: "NativeWhisper Error", body: "OPENAI_API_KEY is not configured.")
        default:
            notifier.notify(title: "NativeWhisper Error", body: message)
        }

        if errorDisplayDuration > 0 {
            try? await Task.sleep(nanoseconds: errorDisplayDuration)
        }

        setState(.idle)
    }

    private func setState(_ newState: DictationState) {
        state = newState
        stateDidChange(newState)
    }
}
