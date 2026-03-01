import Foundation
import XCTest
@testable import NativeWhisper

final class DictationCoordinatorTests: XCTestCase {
    func testHoldAndReleaseTranscribesAndInserts() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "hello world")
        let inserter = MockTextInserter()
        let focus = MockFocusResolver(isEditable: true)
        let clipboard = MockClipboardService()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            focusResolver: focus,
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

    func testNoEditableFocusFallsBackToClipboard() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "clipboard text")
        let inserter = MockTextInserter()
        let focus = MockFocusResolver(isEditable: false)
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
            focusResolver: focus,
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
        XCTAssertTrue(events.contains(.clipboardFallbackNotice("No cursor found. Copied to clipboard.")))
    }

    func testShortPressSkipsTranscription() async {
        let audio = MockAudioCapture()
        let transcriber = MockTranscriber(transcript: "should not be used")
        let inserter = MockTextInserter()
        let focus = MockFocusResolver(isEditable: true)
        let clipboard = MockClipboardService()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            focusResolver: focus,
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
        let focus = MockFocusResolver(isEditable: true)
        let clipboard = MockClipboardService()
        let permissions = MockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let notifier = MockNotifier()

        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionClient: transcriber,
            textInserter: inserter,
            focusResolver: focus,
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

private final class MockFocusResolver: FocusResolving, @unchecked Sendable {
    let isEditable: Bool

    init(isEditable: Bool) {
        self.isEditable = isEditable
    }

    func isEditableElementFocused() -> Bool {
        isEditable
    }
}

private final class MockClipboardService: ClipboardWriting, @unchecked Sendable {
    private(set) var copiedTexts: [String] = []

    func copy(_ text: String) {
        copiedTexts.append(text)
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
