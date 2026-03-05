import Foundation
import XCTest
@testable import WhisperAnywhere

final class DictationCoordinatorTests: XCTestCase {
    func testHoldAndReleaseTranscribesAndInserts() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "hello world")
        let inserter = MockTextInserter()
        let clipboard = MockClipboardService()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            clipboard: clipboard,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "test-key", model: "whisper-1", language: "en"),
            minimumPressDuration: 0,
            errorDisplayDuration: 0,
            stateDidChange: { _ in }
        )

        await coordinator.handleFnPressed()
        await coordinator.handleFnReleased()

        XCTAssertTrue(audio.didStart)
        XCTAssertTrue(audio.didStop)
        XCTAssertEqual(transcriber.callCount, 1)
        XCTAssertEqual(inserter.insertedTexts, ["hello world"])
        XCTAssertEqual(clipboard.copiedTexts.count, 0)
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .idle)
    }

    func testNoEditableFocusStillAttemptsInsertion() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "clipboard text")
        let inserter = MockTextInserter()
        let clipboard = MockClipboardService()
        let events = MockEventCollector()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            clipboard: clipboard,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "test-key", model: "whisper-1", language: "en"),
            minimumPressDuration: 0,
            errorDisplayDuration: 0,
            stateDidChange: { _ in },
            eventDidOccur: { event in
                events.append(event)
            }
        )

        await coordinator.handleFnPressed()
        await coordinator.handleFnReleased()

        XCTAssertEqual(inserter.insertedTexts, ["clipboard text"])
        XCTAssertEqual(clipboard.copiedTexts.count, 0)
        XCTAssertFalse(notifier.messages.contains(where: { $0.body.contains("copied to clipboard") }))
        XCTAssertFalse(events.contains(.clipboardFallbackNotice("Could not insert text. Copied to clipboard.")))
    }

    func testInsertionFailureFallsBackToClipboard() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "clipboard text")
        let inserter = MockTextInserter()
        inserter.error = TextInsertionServiceError.eventCreationFailed
        let clipboard = MockClipboardService()
        let events = MockEventCollector()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            clipboard: clipboard,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "test-key", model: "whisper-1", language: "en"),
            minimumPressDuration: 0,
            errorDisplayDuration: 0,
            stateDidChange: { _ in },
            eventDidOccur: { event in
                events.append(event)
            }
        )

        await coordinator.handleFnPressed()
        await coordinator.handleFnReleased()

        XCTAssertEqual(inserter.insertedTexts.count, 0)
        XCTAssertEqual(clipboard.copiedTexts, ["clipboard text"])
        XCTAssertTrue(notifier.messages.contains(where: { $0.body.contains("copied to clipboard") }))
        XCTAssertTrue(events.contains(.clipboardFallbackNotice("Could not insert text. Copied to clipboard.")))
    }

    func testShortPressSkipsTranscription() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "should not be used")
        let inserter = MockTextInserter()
        let clipboard = MockClipboardService()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            clipboard: clipboard,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "test-key", model: "whisper-1", language: "en"),
            minimumPressDuration: 3,
            errorDisplayDuration: 0,
            stateDidChange: { _ in }
        )

        await coordinator.handleFnPressed()
        await coordinator.handleFnReleased()

        XCTAssertEqual(transcriber.callCount, 0)
        XCTAssertEqual(inserter.insertedTexts.count, 0)
        XCTAssertEqual(clipboard.copiedTexts.count, 0)
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .idle)
    }

    func testMissingAPIKeyNotifiesError() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "unused")
        let inserter = MockTextInserter()
        let clipboard = MockClipboardService()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            clipboard: clipboard,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "", model: "whisper-1", language: "en"),
            minimumPressDuration: 0,
            errorDisplayDuration: 0,
            stateDidChange: { _ in }
        )

        await coordinator.handleFnPressed()

        XCTAssertFalse(audio.didStart)
        XCTAssertTrue(notifier.messages.contains(where: { $0.body.contains("OPENAI_API_KEY") }))
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .idle)
    }

    func testSelectedTextStartsEditModeAndInsertsEditedResult() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "make this more concise")
        let textEditor = MockTextEditor(result: "Concise final text")
        let inserter = MockTextInserter()
        let clipboard = MockClipboardService()
        let selectionDetector = MockSelectionDetector(selectedText: "Verbose draft text")
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()
        let stateCollector = MockStateCollector()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textEditor: textEditor,
            textInserter: inserter,
            clipboard: clipboard,
            selectionDetector: selectionDetector,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "test-key", model: "whisper-1", language: "en"),
            minimumPressDuration: 0,
            errorDisplayDuration: 0,
            stateDidChange: { state in
                stateCollector.append(state)
            }
        )

        await coordinator.handleFnPressed()
        let recordingState = await coordinator.currentState()
        guard case .recording(_, let mode) = recordingState else {
            return XCTFail("Expected recording state after Fn press.")
        }
        XCTAssertEqual(mode, .editCommand)

        await coordinator.handleFnReleased()

        XCTAssertEqual(textEditor.callCount, 1)
        XCTAssertEqual(textEditor.lastSelectedText, "Verbose draft text")
        XCTAssertEqual(textEditor.lastInstructions, "make this more concise")
        XCTAssertEqual(inserter.insertedTexts, ["Concise final text"])
        XCTAssertEqual(clipboard.copiedTexts.count, 0)
        XCTAssertTrue(stateCollector.containsEditingState())
    }

    func testEditModelFailureReinsertsOriginalSelection() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "rewrite for clarity")
        let textEditor = MockTextEditor(result: "unused")
        textEditor.error = MockEditError.failed
        let inserter = MockTextInserter()
        let clipboard = MockClipboardService()
        let selectionDetector = MockSelectionDetector(selectedText: "Original selected sentence")
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textEditor: textEditor,
            textInserter: inserter,
            clipboard: clipboard,
            selectionDetector: selectionDetector,
            permissionService: permissions,
            notifier: notifier,
            config: AppConfig(openAIKey: "test-key", model: "whisper-1", language: "en"),
            minimumPressDuration: 0,
            errorDisplayDuration: 0,
            stateDidChange: { _ in }
        )

        await coordinator.handleFnPressed()
        await coordinator.handleFnReleased()

        XCTAssertEqual(textEditor.callCount, 1)
        XCTAssertEqual(inserter.insertedTexts, ["Original selected sentence"])
        XCTAssertEqual(clipboard.copiedTexts.count, 0)
    }
}

private final class MockAudioCapture: AudioCapturing, @unchecked Sendable {
    var didStart = false
    var didStop = false
    var startError: Error?
    var stopError: Error?
    private let outputURL: URL

    init() {
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? Data("audio".utf8).write(to: outputURL)
    }

    func start() throws {
        if let startError {
            throw startError
        }
        didStart = true
    }

    func stop() throws -> URL {
        if let stopError {
            throw stopError
        }
        didStop = true
        return outputURL
    }

    func currentNormalizedInputLevel() -> Float? {
        nil
    }

    func currentEqualizerBands() -> [Float]? {
        nil
    }
}

private final class MockTranscriber: Transcribing, @unchecked Sendable {
    let transcript: String
    var error: Error?
    private(set) var callCount = 0

    init(transcript: String) {
        self.transcript = transcript
    }

    func transcribe(audioURL: URL) async throws -> String {
        callCount += 1
        if let error {
            throw error
        }
        return transcript
    }
}

private enum MockEditError: Error {
    case failed
}

private final class MockTextEditor: TextEditing, @unchecked Sendable {
    let result: String
    var error: Error?
    private(set) var callCount = 0
    private(set) var lastSelectedText: String?
    private(set) var lastInstructions: String?

    init(result: String) {
        self.result = result
    }

    func edit(selectedText: String, instructions: String) async throws -> String {
        callCount += 1
        lastSelectedText = selectedText
        lastInstructions = instructions

        if let error {
            throw error
        }

        return result
    }
}

private final class MockTextInserter: TextInserting, @unchecked Sendable {
    var error: Error?
    private(set) var insertedTexts: [String] = []

    func insert(_ text: String) throws {
        if let error {
            throw error
        }
        insertedTexts.append(text)
    }
}

private final class MockClipboardService: ClipboardWriting, @unchecked Sendable {
    private(set) var copiedTexts: [String] = []

    func copy(_ text: String) {
        copiedTexts.append(text)
    }
}

private final class MockSelectionDetector: SelectionDetecting, @unchecked Sendable {
    let selectedText: String?

    init(selectedText: String?) {
        self.selectedText = selectedText
    }

    func detectSelectedText() async -> String? {
        selectedText
    }
}

private final class MockPermissionService: PermissionProviding, @unchecked Sendable {
    let snapshotValue: PermissionSnapshot

    init(snapshot: PermissionSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> PermissionSnapshot {
        snapshotValue
    }

    func requestMicrophoneAccess() async -> Bool {
        true
    }

    func requestAccessibilityAccess() -> Bool {
        true
    }

    func requestInputMonitoringAccess() -> Bool {
        true
    }
}

private final class MockNotifier: Notifying, @unchecked Sendable {
    private(set) var messages: [(title: String, body: String)] = []

    func requestAuthorizationIfNeeded() async {}

    func notify(title: String, body: String) {
        messages.append((title, body))
    }
}

private final class MockEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DictationEvent] = []

    func append(_ event: DictationEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func contains(_ event: DictationEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return events.contains(event)
    }
}

private final class MockStateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [DictationState] = []

    func append(_ state: DictationState) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    func containsEditingState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return states.contains { state in
            if case .editing = state {
                return true
            }
            return false
        }
    }
}
