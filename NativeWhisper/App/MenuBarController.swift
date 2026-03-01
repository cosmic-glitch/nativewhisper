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

    private let permissionService: PermissionProviding
    private let notifier: Notifying
    private let fnMonitor: FnKeyMonitoring
    private let chimeService: Chiming
    private let hudController: RecordingHUDControlling
    private let audioCapture: AudioCapturing
    private let stateSink: DictationStateSink
    private let eventSink: DictationEventSink
    private let coordinator: DictationCoordinator

    private var meterTask: Task<Void, Never>?
    private var hudMessageTask: Task<Void, Never>?
    private var smoothedLevel: Float = 0.08
    private var smoothedBands: [Float] = Array(repeating: 0.08, count: 5)
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
        self.eventSink = DictationEventSink()
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
        smoothedBands = Array(repeating: 0.08, count: 5)

        meterTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                if let rawBands = audioCapture.currentEqualizerBands() {
                    let normalizedBands: [Float]
                    if rawBands.count >= 5 {
                        normalizedBands = Array(rawBands.prefix(5))
                    } else {
                        normalizedBands = rawBands + Array(repeating: 0.04, count: 5 - rawBands.count)
                    }

                    for index in 0 ..< 5 {
                        let clamped = min(max(normalizedBands[index], 0), 1)
                        smoothedBands[index] = (0.32 * clamped) + (0.68 * smoothedBands[index])
                    }
                    hudController.update(bands: smoothedBands)
                } else {
                    let rawLevel = audioCapture.currentNormalizedInputLevel() ?? 0
                    smoothedLevel = (0.55 * rawLevel) + (0.45 * smoothedLevel)
                    hudController.update(level: smoothedLevel)
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func stopMeterPolling() {
        meterTask?.cancel()
        meterTask = nil
        smoothedLevel = 0.08
        smoothedBands = Array(repeating: 0.08, count: 5)
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
