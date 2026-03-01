import Foundation
import XCTest
@testable import NativeWhisper

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testRecordingStartPlaysChimeAndShowsHUD() async {
        let mocks = makeMocks(audioLevel: 0.52)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date()))
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(mocks.chime.playCount, 1)
        XCTAssertEqual(mocks.hud.showCount, 1)
        XCTAssertGreaterThan(mocks.hud.updateCount, 0)
    }

    func testNonRecordingStateDoesNotPlayChimeOrShowHUD() {
        let mocks = makeMocks(audioLevel: 0.15)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.error("failed"))

        XCTAssertEqual(mocks.chime.playCount, 0)
        XCTAssertEqual(mocks.hud.showCount, 0)
    }

    func testRecordingExitHidesHUDAndStopsMeterUpdates() async {
        let mocks = makeMocks(audioLevel: 0.9)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date()))
        try? await Task.sleep(nanoseconds: 150_000_000)
        let beforeStopUpdates = mocks.hud.updateCount

        controller.applyStateUpdate(.transcribing)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let afterStopUpdates = mocks.hud.updateCount

        XCTAssertEqual(mocks.hud.hideCount, 1)
        XCTAssertLessThanOrEqual(afterStopUpdates, beforeStopUpdates + 1)
    }

    private func makeController(mocks: ControllerMocks) -> MenuBarController {
        MenuBarController(
            config: AppConfig(openAIKey: "test", model: "whisper-1", language: "en"),
            permissionService: mocks.permissionService,
            notifier: mocks.notifier,
            fnMonitor: mocks.fnMonitor,
            audioCapture: mocks.audioCapture,
            textInserter: MenuMockTextInserter(),
            focusResolver: MenuMockFocusResolver(),
            clipboard: MenuMockClipboard(),
            chimeService: mocks.chime,
            hudController: mocks.hud,
            autoStart: false
        )
    }

    private func makeMocks(audioLevel: Float) -> ControllerMocks {
        ControllerMocks(
            permissionService: MenuMockPermissionService(),
            notifier: MenuMockNotifier(),
            fnMonitor: MenuMockFnMonitor(),
            audioCapture: MenuMockAudioCapture(level: audioLevel),
            chime: MenuMockChimeService(),
            hud: MenuMockHUDController()
        )
    }
}

private struct ControllerMocks {
    let permissionService: MenuMockPermissionService
    let notifier: MenuMockNotifier
    let fnMonitor: MenuMockFnMonitor
    let audioCapture: MenuMockAudioCapture
    let chime: MenuMockChimeService
    let hud: MenuMockHUDController
}

private final class MenuMockPermissionService: PermissionProviding, @unchecked Sendable {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
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

private final class MenuMockNotifier: Notifying, @unchecked Sendable {
    func requestAuthorizationIfNeeded() async {}
    func notify(title: String, body: String) {}
}

private final class MenuMockFnMonitor: FnKeyMonitoring {
    var onEvent: ((FnKeyEvent) -> Void)?
    func start() throws {}
    func stop() {}
}

private final class MenuMockAudioCapture: AudioCapturing, @unchecked Sendable {
    private let outputURL: URL
    private let level: Float

    init(level: Float) {
        self.level = level
        self.outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("menu-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? Data("audio".utf8).write(to: outputURL)
    }

    func start() throws {}
    func stop() throws -> URL { outputURL }
    func currentNormalizedInputLevel() -> Float? { level }
}

private final class MenuMockTextInserter: TextInserting, @unchecked Sendable {
    func insert(_ text: String) throws {}
}

private final class MenuMockFocusResolver: FocusResolving, @unchecked Sendable {
    func isEditableElementFocused() -> Bool { true }
}

private final class MenuMockClipboard: ClipboardWriting, @unchecked Sendable {
    func copy(_ text: String) {}
}

@MainActor
private final class MenuMockChimeService: Chiming {
    private(set) var playCount = 0

    func playStartChime() {
        playCount += 1
    }
}

@MainActor
private final class MenuMockHUDController: RecordingHUDControlling {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var updateCount = 0

    func show() {
        showCount += 1
    }

    func hide() {
        hideCount += 1
    }

    func update(level: Float) {
        updateCount += 1
    }
}
