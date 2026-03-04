import AppKit
import Foundation
import SwiftUI

enum SettingsPane {
    case microphone
    case accessibility
    case inputMonitoring
    case privacySecurity
}

enum AppReadinessStatus {
    case ready
    case notEnoughPermissions
    case openAIKeyNotConfigured

    var label: String {
        switch self {
        case .ready:
            return "Ready"
        case .notEnoughPermissions:
            return "Not enough permissions"
        case .openAIKeyNotConfigured:
            return "OpenAI key not configured"
        }
    }
}

@MainActor
final class MenuBarController: ObservableObject {
    private final class DictationStateSink: @unchecked Sendable {
        weak var controller: MenuBarController?

        func publish(_ state: DictationState) {
            Task { @MainActor [weak controller] in
                controller?.applyStateUpdate(state)
            }
        }
    }

    private final class DictationEventSink: @unchecked Sendable {
        weak var controller: MenuBarController?

        func publish(_ event: DictationEvent) {
            Task { @MainActor [weak controller] in
                controller?.applyEventUpdate(event)
            }
        }
    }

    @Published private(set) var dictationState: DictationState = .idle
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var monitorErrorMessage: String?
    @Published private(set) var apiKeyConfigured: Bool
    @Published private(set) var authStatusMessage: String?
    @Published private(set) var isPreparingInitialMicrophonePrompt = false

    private let permissionService: PermissionProviding
    private let notifier: Notifying
    private let fnMonitor: FnKeyMonitoring
    private let chimeService: Chiming
    private let hudController: RecordingHUDControlling
    private let audioCapture: AudioCapturing
    private let apiKeyStore: APIKeyStoring
    private let configurationPresenter: ConfigurationPresenting
    private let appDefaults: UserDefaults
    private let firstLaunchConfigurationKey: String
    private let initialMicrophonePromptAttemptKey: String
    private let legacyFirstLaunchConfigurationKey: String
    private let legacyBundleIdentifier: String
    private let stateSink: DictationStateSink
    private let eventSink: DictationEventSink
    private let coordinator: DictationCoordinator

    private var meterTask: Task<Void, Never>?
    private var hudMessageTask: Task<Void, Never>?
    private var smoothedLevel: Float = 0.08
    private var smoothedBands: [Float] = Array(
        repeating: RecordingHUDModel.waveformFloor,
        count: RecordingHUDModel.waveformSampleCount
    )
    private var started = false

    let config: AppConfig

    init(
        config: AppConfig? = nil,
        apiKeyStore: APIKeyStoring = APIKeyStore.shared,
        configurationPresenter: ConfigurationPresenting = ConfigurationWindowController(),
        appDefaults: UserDefaults = .standard,
        firstLaunchConfigurationKey: String = "WhisperAnywhere.DidShowConfigurationOnFirstLaunch",
        initialMicrophonePromptAttemptKey: String = "WhisperAnywhere.DidAttemptInitialMicrophonePrompt",
        legacyFirstLaunchConfigurationKey: String = "NativeWhisper.DidShowConfigurationOnFirstLaunch",
        legacyBundleIdentifier: String = "ai.nativewhisper.app",
        permissionService: PermissionProviding = PermissionService(),
        notifier: Notifying = NotificationService(),
        fnMonitor: FnKeyMonitoring = FnKeyMonitor(),
        audioCapture: AudioCapturing = AudioCaptureService(),
        textInserter: TextInserting = TextInsertionService(),
        clipboard: ClipboardWriting = ClipboardService(),
        chimeService: Chiming = SystemChimeService(),
        hudController: RecordingHUDControlling = RecordingHUDWindowController(),
        autoStart: Bool = true
    ) {
        let resolvedConfig = config ?? AppConfig.load(apiKeyStore: apiKeyStore)

        self.config = resolvedConfig
        self.apiKeyStore = apiKeyStore
        self.configurationPresenter = configurationPresenter
        self.appDefaults = appDefaults
        self.firstLaunchConfigurationKey = firstLaunchConfigurationKey
        self.initialMicrophonePromptAttemptKey = initialMicrophonePromptAttemptKey
        self.legacyFirstLaunchConfigurationKey = legacyFirstLaunchConfigurationKey
        self.legacyBundleIdentifier = legacyBundleIdentifier
        self.permissionService = permissionService
        self.notifier = notifier
        self.fnMonitor = fnMonitor
        self.audioCapture = audioCapture
        self.chimeService = chimeService
        self.hudController = hudController
        self.stateSink = DictationStateSink()
        self.eventSink = DictationEventSink()
        self.permissionSnapshot = permissionService.snapshot()
        self.apiKeyConfigured = !resolvedConfig.openAIKey.isEmpty

        self.coordinator = DictationCoordinator(
            audioCapture: audioCapture,
            transcriptionClient: OpenAITranscriptionClient(config: resolvedConfig),
            textInserter: textInserter,
            clipboard: clipboard,
            permissionService: permissionService,
            notifier: notifier,
            config: resolvedConfig,
            stateDidChange: { [weak stateSink] newState in
                stateSink?.publish(newState)
            },
            eventDidOccur: { [weak eventSink] event in
                eventSink?.publish(event)
            }
        )

        stateSink.controller = self
        eventSink.controller = self

        fnMonitor.onEvent = { [weak self] event in
            self?.handleFnEvent(event)
        }

        if autoStart {
            DispatchQueue.main.async { [weak self] in
                self?.startIfNeeded()
            }
        }
    }

    deinit {
        meterTask?.cancel()
        hudMessageTask?.cancel()
    }

    var readinessStatus: AppReadinessStatus {
        if !apiKeyConfigured {
            return .openAIKeyNotConfigured
        }

        guard hasRequiredPermissions else {
            return .notEnoughPermissions
        }

        return .ready
    }

    var statusText: String {
        readinessStatus.label
    }

    var menuIconName: String {
        switch dictationState {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform.circle.fill"
        case .inserting:
            return "keyboard"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    func startIfNeeded() {
        guard !started else {
            return
        }
        started = true

        Task { @MainActor in
            await notifier.requestAuthorizationIfNeeded()
        }

        refreshPermissions()
        showConfigurationOnFirstLaunchIfNeeded()

        do {
            try fnMonitor.start()
            monitorErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            monitorErrorMessage = message
            applyStateUpdate(.error(message))
            notifier.notify(title: "Whisper Anywhere Error", body: message)
        }
    }

    func refreshPermissions() {
        permissionSnapshot = permissionService.snapshot()
        syncAPIKeyStatus()
    }

    func testPermissions() {
        Task { @MainActor in
            _ = await permissionService.requestMicrophoneAccess()
            _ = permissionService.requestAccessibilityAccess()
            _ = permissionService.requestInputMonitoringAccess()
            refreshPermissions()
        }
    }

    func requestMicrophoneAccessFromConfiguration() async {
        _ = await permissionService.requestMicrophoneAccess()
        refreshPermissions()
    }

    func prepareMicrophonePermissionOnSetupOpenIfNeeded() async {
        if isPreparingInitialMicrophonePrompt {
            return
        }

        isPreparingInitialMicrophonePrompt = true
        defer {
            isPreparingInitialMicrophonePrompt = false
        }

        refreshPermissions()

        guard permissionSnapshot.microphone == .notDetermined else {
            return
        }

        guard !appDefaults.bool(forKey: initialMicrophonePromptAttemptKey) else {
            return
        }

        appDefaults.set(true, forKey: initialMicrophonePromptAttemptKey)
        _ = await permissionService.requestMicrophoneAccess()
        refreshPermissions()
    }

    func openConfiguration() {
        configurationPresenter.show(controller: self)
    }

    func dismissConfiguration() {
        configurationPresenter.dismiss()
    }

    func currentAPIKey() -> String {
        config.openAIKey
    }

    func saveAPIKey(_ value: String) {
        apiKeyStore.saveAPIKey(value)
        syncAPIKeyStatus()
    }

    func permissionLabel(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        }
    }

    func openSystemSettings(_ pane: SettingsPane) {
        let candidates: [String]

        switch pane {
        case .microphone:
            candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            ]
        case .accessibility:
            candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ]
        case .inputMonitoring:
            candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            ]
        case .privacySecurity:
            candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                "x-apple.systempreferences:com.apple.preference.security"
            ]
        }

        for rawURL in candidates {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func quitApp() {
        meterTask?.cancel()
        meterTask = nil
        hudMessageTask?.cancel()
        hudMessageTask = nil
        hudController.hide()
        fnMonitor.stop()
        NSApplication.shared.terminate(nil)
    }

    func applyStateUpdate(_ newState: DictationState) {
        let oldState = dictationState
        dictationState = newState
        handleStateTransition(from: oldState, to: newState)
    }

    func applyEventUpdate(_ event: DictationEvent) {
        switch event {
        case .clipboardFallbackNotice(let message):
            showTransientHUDMessage(message)
        }
    }

    private var hasRequiredPermissions: Bool {
        permissionSnapshot.microphone == .granted &&
            permissionSnapshot.accessibility == .granted &&
            permissionSnapshot.inputMonitoring == .granted &&
            monitorErrorMessage == nil
    }

    private func showConfigurationOnFirstLaunchIfNeeded() {
        migrateFirstLaunchFlagIfNeeded()

        guard !appDefaults.bool(forKey: firstLaunchConfigurationKey) else {
            return
        }

        appDefaults.set(true, forKey: firstLaunchConfigurationKey)
        openConfiguration()
    }

    private func migrateFirstLaunchFlagIfNeeded() {
        if appDefaults.object(forKey: firstLaunchConfigurationKey) != nil {
            return
        }

        if appDefaults.object(forKey: legacyFirstLaunchConfigurationKey) != nil {
            appDefaults.set(appDefaults.bool(forKey: legacyFirstLaunchConfigurationKey), forKey: firstLaunchConfigurationKey)
            return
        }

        guard let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier),
              legacyDefaults.object(forKey: legacyFirstLaunchConfigurationKey) != nil else {
            return
        }

        appDefaults.set(legacyDefaults.bool(forKey: legacyFirstLaunchConfigurationKey), forKey: firstLaunchConfigurationKey)
    }

    private func syncAPIKeyStatus() {
        apiKeyConfigured = !config.openAIKey.isEmpty
    }

    private func handleFnEvent(_ event: FnKeyEvent) {
        Task {
            if event == .pressed {
                guard canStartDictationFromCurrentState() else {
                    await MainActor.run {
                        self.refreshPermissions()
                    }
                    return
                }
            }

            switch event {
            case .pressed:
                await coordinator.handleFnPressed()
            case .released:
                await coordinator.handleFnReleased()
            }
            await MainActor.run {
                self.refreshPermissions()
            }
        }
    }

    private func canStartDictationFromCurrentState() -> Bool {
        if config.openAIKey.isEmpty {
            notifier.notify(title: "Whisper Anywhere", body: "OpenAI key is not configured. Open Configure.")
            return false
        }
        return true
    }

    private func handleStateTransition(from oldState: DictationState, to newState: DictationState) {
        let wasRecording = isRecordingState(oldState)
        let isRecording = isRecordingState(newState)
        let wasTranscribing = isTranscribingState(oldState)
        let isTranscribing = isTranscribingState(newState)

        if !wasRecording && isRecording {
            cancelHUDMessageTask()
            chimeService.playStartChime()
            hudController.setMode(.recording)
            hudController.update(bands: Array(repeating: 0.08, count: 5))
            hudController.show()
            startMeterPolling()
            return
        }

        if wasRecording && !isRecording {
            stopMeterPolling()
            if isTranscribing {
                hudController.setMode(.transcribing)
                hudController.show()
            } else {
                hudController.hide()
            }
            return
        }

        if !wasTranscribing && isTranscribing {
            cancelHUDMessageTask()
            hudController.setMode(.transcribing)
            hudController.show()
            return
        }

        if wasTranscribing && !isTranscribing {
            hudController.hide()
        }
    }

    private func showTransientHUDMessage(_ message: String) {
        cancelHUDMessageTask()

        hudController.setMode(.message(message))
        hudController.show()

        hudMessageTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            if isRecordingState(dictationState) || isTranscribingState(dictationState) {
                return
            }

            hudController.hide()
        }
    }

    private func cancelHUDMessageTask() {
        hudMessageTask?.cancel()
        hudMessageTask = nil
    }

    private func startMeterPolling() {
        stopMeterPolling()
        smoothedLevel = 0.08
        smoothedBands = Array(
            repeating: RecordingHUDModel.waveformFloor,
            count: RecordingHUDModel.waveformSampleCount
        )

        meterTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                let instantaneousLevel = resolvedInstantaneousLevel()
                smoothedLevel = (0.4 * instantaneousLevel) + (0.6 * smoothedLevel)

                smoothedBands.append(max(smoothedLevel, RecordingHUDModel.waveformFloor))
                if smoothedBands.count > RecordingHUDModel.waveformSampleCount {
                    smoothedBands.removeFirst(smoothedBands.count - RecordingHUDModel.waveformSampleCount)
                }

                hudController.update(bands: smoothedBands)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
    }

    private func stopMeterPolling() {
        meterTask?.cancel()
        meterTask = nil
        smoothedLevel = 0.08
        smoothedBands = Array(
            repeating: RecordingHUDModel.waveformFloor,
            count: RecordingHUDModel.waveformSampleCount
        )
    }

    private func resolvedInstantaneousLevel() -> Float {
        if let rawBands = audioCapture.currentEqualizerBands(), !rawBands.isEmpty {
            let clamped = rawBands.map { min(max($0, 0), 1) }
            let average = clamped.reduce(0, +) / Float(clamped.count)
            let peak = clamped.max() ?? average
            return (0.65 * peak) + (0.35 * average)
        }

        return min(max(audioCapture.currentNormalizedInputLevel() ?? 0, 0), 1)
    }

    private func isRecordingState(_ state: DictationState) -> Bool {
        if case .recording = state {
            return true
        }
        return false
    }

    private func isTranscribingState(_ state: DictationState) -> Bool {
        if case .transcribing = state {
            return true
        }
        return false
    }
}
