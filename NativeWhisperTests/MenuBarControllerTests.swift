import Foundation
import XCTest
@testable import NativeWhisper

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testRecordingStartPlaysChimeAndShowsHUD() async {
        let mocks = makeMocks(audioLevel: 0.52, bands: [0.12, 0.28, 0.74, 0.33, 0.14])
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date()))
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(mocks.chime.playCount, 1)
        XCTAssertEqual(mocks.hud.showCount, 1)
        XCTAssertGreaterThan(mocks.hud.updateCount, 0)
        XCTAssertTrue(mocks.hud.didReceiveBandUpdate)
        XCTAssertEqual(mocks.hud.lastMode, .recording)
    }

    func testNonRecordingStateDoesNotPlayChimeOrShowHUD() {
        let mocks = makeMocks(audioLevel: 0.15, bands: nil)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.error("failed"))

        XCTAssertEqual(mocks.chime.playCount, 0)
        XCTAssertEqual(mocks.hud.showCount, 0)
    }

    func testRecordingExitHidesHUDAndStopsMeterUpdates() async {
        let mocks = makeMocks(audioLevel: 0.9, bands: [0.18, 0.42, 0.88, 0.4, 0.22])
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date()))
        try? await Task.sleep(nanoseconds: 150_000_000)
        let beforeStopUpdates = mocks.hud.updateCount

        controller.applyStateUpdate(.transcribing)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let afterStopUpdates = mocks.hud.updateCount

        XCTAssertEqual(mocks.hud.hideCount, 0)
        XCTAssertEqual(mocks.hud.lastMode, .transcribing)
        XCTAssertLessThanOrEqual(afterStopUpdates, beforeStopUpdates + 1)

        controller.applyStateUpdate(.idle)
        XCTAssertEqual(mocks.hud.hideCount, 1)
    }

    func testDirectRouteReadyWithoutSignInWhenAPIKeyConfigured() {
        let mocks = makeMocks(audioLevel: 0.2, bands: nil)
        let routeStore = MenuMockRouteStore(initialRoute: .direct)
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(
                openAIKey: "sk-test",
                model: "whisper-1",
                language: "en",
                transcriptionMode: .hosted,
                backendBaseURL: URL(string: "https://whisperanywhere.app"),
                allowLegacyPersonalKeyEntry: true
            ),
            routeStore: routeStore
        )

        XCTAssertEqual(controller.selectedTranscriptionRoute, .direct)
        XCTAssertEqual(controller.readinessStatus, .ready)
    }

    func testHostedRouteRequiresSignInWhenSessionMissing() {
        let mocks = makeMocks(audioLevel: 0.2, bands: nil)
        let routeStore = MenuMockRouteStore(initialRoute: .hosted)
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(
                openAIKey: "",
                model: "whisper-1",
                language: "en",
                transcriptionMode: .hosted,
                backendBaseURL: URL(string: "https://whisperanywhere.app"),
                allowLegacyPersonalKeyEntry: true
            ),
            routeStore: routeStore
        )

        XCTAssertEqual(controller.selectedTranscriptionRoute, .hosted)
        XCTAssertEqual(controller.readinessStatus, .signInRequired)
    }

    func testRouteSwitchBlockedWhileNotIdle() {
        let mocks = makeMocks(audioLevel: 0.4, bands: nil)
        let routeStore = MenuMockRouteStore(initialRoute: .direct)
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(openAIKey: "sk-test", model: "whisper-1", language: "en"),
            routeStore: routeStore
        )

        controller.applyStateUpdate(.recording(Date()))
        controller.setTranscriptionRoute(.hosted)

        XCTAssertEqual(controller.selectedTranscriptionRoute, .direct)
        XCTAssertEqual(routeStore.currentRoute(), .direct)
        XCTAssertEqual(controller.authStatusMessage, "Finish current dictation before switching modes.")
    }

    func testDirectRouteSkipsHostedQuotaRefreshCalls() async {
        let mocks = makeMocks(audioLevel: 0.4, bands: nil)
        let routeStore = MenuMockRouteStore(initialRoute: .direct)
        let authClient = MenuMockAuthClient()
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(
                openAIKey: "sk-test",
                model: "whisper-1",
                language: "en",
                transcriptionMode: .hosted,
                backendBaseURL: URL(string: "https://whisperanywhere.app"),
                allowLegacyPersonalKeyEntry: true
            ),
            routeStore: routeStore,
            authClient: authClient
        )

        await controller.refreshQuotaStatus()
        XCTAssertEqual(authClient.fetchQuotaCalls, 0)
    }

    private func makeController(
        mocks: ControllerMocks,
        config: AppConfig = AppConfig(openAIKey: "test", model: "whisper-1", language: "en"),
        routeStore: TranscriptionRouteStoring = MenuMockRouteStore(initialRoute: .direct),
        authClient: BackendAuthenticating? = nil,
        sessionStore: SessionStoring = MenuMockSessionStore()
    ) -> MenuBarController {
        MenuBarController(
            config: config,
            transcriptionRouteStore: routeStore,
            sessionStore: sessionStore,
            authClient: authClient,
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

    private func makeMocks(audioLevel: Float, bands: [Float]?) -> ControllerMocks {
        ControllerMocks(
            permissionService: MenuMockPermissionService(),
            notifier: MenuMockNotifier(),
            fnMonitor: MenuMockFnMonitor(),
            audioCapture: MenuMockAudioCapture(level: audioLevel, bands: bands),
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
    private let bands: [Float]?

    init(level: Float, bands: [Float]?) {
        self.level = level
        self.bands = bands
        self.outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("menu-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? Data("audio".utf8).write(to: outputURL)
    }

    func start() throws {}
    func stop() throws -> URL { outputURL }
    func currentNormalizedInputLevel() -> Float? { level }
    func currentEqualizerBands() -> [Float]? { bands }
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
    private(set) var didReceiveBandUpdate = false
    private(set) var lastMode: RecordingHUDMode?

    func show() {
        showCount += 1
    }

    func hide() {
        hideCount += 1
    }

    func setMode(_ mode: RecordingHUDMode) {
        lastMode = mode
    }

    func update(level: Float) {
        updateCount += 1
    }

    func update(bands: [Float]) {
        updateCount += 1
        didReceiveBandUpdate = true
    }
}

private final class MenuMockRouteStore: TranscriptionRouteStoring, @unchecked Sendable {
    private var route: TranscriptionRoute
    private let lock = NSLock()

    init(initialRoute: TranscriptionRoute) {
        self.route = initialRoute
    }

    func currentRoute() -> TranscriptionRoute {
        lock.lock()
        defer { lock.unlock() }
        return route
    }

    func saveRoute(_ route: TranscriptionRoute) {
        lock.lock()
        self.route = route
        lock.unlock()
    }
}

private final class MenuMockAuthClient: BackendAuthenticating, @unchecked Sendable {
    private(set) var fetchQuotaCalls = 0

    func beginGoogleSignIn(deviceID: String, appVersion: String) async throws -> URL {
        URL(string: "https://example.com")!
    }

    func completeGoogleSignIn(oauthTokens: GoogleOAuthTokens, deviceID: String) async throws -> AuthSession {
        AuthSession(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            userId: "user",
            email: "user@example.com"
        )
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        AuthSession(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            userId: "user",
            email: "user@example.com"
        )
    }

    func fetchQuota(accessToken: String, deviceID: String) async throws -> QuotaStatus {
        fetchQuotaCalls += 1
        return QuotaStatus(
            remainingToday: 100,
            deviceCap: 100,
            globalBudgetState: "ok",
            resetAt: nil
        )
    }
}

private final class MenuMockSessionStore: SessionStoring, @unchecked Sendable {
    private var session: AuthSession?

    init(initialSession: AuthSession? = nil) {
        self.session = initialSession
    }

    func loadSession() -> AuthSession? {
        session
    }

    func saveSession(_ session: AuthSession) throws {
        self.session = session
    }

    func clearSession() throws {
        session = nil
    }
}
