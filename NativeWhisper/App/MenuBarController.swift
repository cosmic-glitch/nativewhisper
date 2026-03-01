import AppKit
import Foundation
import SwiftUI

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

    @Published private(set) var dictationState: DictationState = .idle
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var monitorErrorMessage: String?

    private let permissionService: PermissionProviding
    private let notifier: Notifying
    private let fnMonitor: FnKeyMonitoring
    private let chimeService: Chiming
    private let hudController: RecordingHUDControlling
    private let audioCapture: AudioCapturing
    private let stateSink: DictationStateSink
    private let coordinator: DictationCoordinator

    private var meterTask: Task<Void, Never>?
    private var smoothedLevel: Float = 0.08
    private var started = false

    let config: AppConfig

    init(
        config: AppConfig = .load(),
        permissionService: PermissionProviding = PermissionService(),
        notifier: Notifying = NotificationService(),
        fnMonitor: FnKeyMonitoring = FnKeyMonitor(),
        audioCapture: AudioCapturing = AudioCaptureService(),
        textInserter: TextInserting = TextInsertionService(),
        focusResolver: FocusResolving = FocusResolver(),
        clipboard: ClipboardWriting = ClipboardService(),
        chimeService: Chiming = SystemChimeService(),
        hudController: RecordingHUDControlling = RecordingHUDWindowController(),
        autoStart: Bool = true
    ) {
        self.config = config
        self.permissionService = permissionService
        self.notifier = notifier
        self.fnMonitor = fnMonitor
        self.audioCapture = audioCapture
        self.chimeService = chimeService
        self.hudController = hudController
        self.stateSink = DictationStateSink()
        self.permissionSnapshot = permissionService.snapshot()

        let transcriptionClient = OpenAITranscriptionClient(config: config)
        self.coordinator = DictationCoordinator(
            audioCapture: audioCapture,
            transcriptionClient: transcriptionClient,
            textInserter: textInserter,
            focusResolver: focusResolver,
            clipboard: clipboard,
            permissionService: permissionService,
            notifier: notifier,
            config: config,
            stateDidChange: { [weak stateSink] newState in
                stateSink?.publish(newState)
            }
        )

        stateSink.controller = self

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

    var statusText: String {
        switch dictationState {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording (hold Fn)"
        case .transcribing:
            return "Transcribing"
        case .inserting:
            return "Inserting"
        case .error(let message):
            return "Error: \(message)"
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

        do {
            try fnMonitor.start()
            monitorErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            monitorErrorMessage = message
            applyStateUpdate(.error(message))
            notifier.notify(title: "NativeWhisper Error", body: message)
        }
    }

    func refreshPermissions() {
        permissionSnapshot = permissionService.snapshot()
    }

    func testPermissions() {
        Task { @MainActor in
            _ = await permissionService.requestMicrophoneAccess()
            _ = permissionService.requestAccessibilityAccess()
            _ = permissionService.requestInputMonitoringAccess()
            refreshPermissions()
        }
    }

    func quitApp() {
        meterTask?.cancel()
        meterTask = nil
        hudController.hide()
        fnMonitor.stop()
        NSApplication.shared.terminate(nil)
    }

    func applyStateUpdate(_ newState: DictationState) {
        let oldState = dictationState
        dictationState = newState
        handleStateTransition(from: oldState, to: newState)
    }

    private func handleFnEvent(_ event: FnKeyEvent) {
        Task {
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

    private func handleStateTransition(from oldState: DictationState, to newState: DictationState) {
        let wasRecording = isRecordingState(oldState)
        let isRecording = isRecordingState(newState)

        if !wasRecording && isRecording {
            chimeService.playStartChime()
            hudController.update(level: 0.08)
            hudController.show()
            startMeterPolling()
            return
        }

        if wasRecording && !isRecording {
            stopMeterPolling()
            hudController.hide()
        }
    }

    private func startMeterPolling() {
        stopMeterPolling()
        smoothedLevel = 0.08

        meterTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                let rawLevel = audioCapture.currentNormalizedInputLevel() ?? 0
                smoothedLevel = (0.35 * rawLevel) + (0.65 * smoothedLevel)
                hudController.update(level: smoothedLevel)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func stopMeterPolling() {
        meterTask?.cancel()
        meterTask = nil
        smoothedLevel = 0.08
    }

    private func isRecordingState(_ state: DictationState) -> Bool {
        if case .recording = state {
            return true
        }
        return false
    }
}
