import Foundation
import XCTest
@testable import WhisperAnywhere

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testRecordingMeterUsesInputLevel() async {
        let mocks = makeMocks(audioLevel: 0.72)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date(), .dictation))
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertGreaterThan(mocks.hud.lastLevel ?? 0, 0.35)
    }

    func testRecordingStartPlaysChimeAndShowsHUD() async {
        let mocks = makeMocks(audioLevel: 0.52)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date(), .dictation))
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(mocks.chime.playCount, 1)
        XCTAssertEqual(mocks.hud.showCount, 1)
        XCTAssertGreaterThan(mocks.hud.updateCount, 0)
        XCTAssertEqual(mocks.hud.lastMode, .recording)
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

        controller.applyStateUpdate(.recording(Date(), .dictation))
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

    func testEditRecordingStartUsesEditHUDMode() async {
        let mocks = makeMocks(audioLevel: 0.44)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.recording(Date(), .editCommand))
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(mocks.chime.playCount, 1)
        XCTAssertEqual(mocks.hud.showCount, 1)
        XCTAssertEqual(mocks.hud.lastMode, .recordingEditCommand)
    }

    func testProcessingTransitionFromTranscribingToEditingUpdatesHUDMode() {
        let mocks = makeMocks(audioLevel: 0.2)
        let controller = makeController(mocks: mocks)

        controller.applyStateUpdate(.transcribing)
        let showsAfterTranscribing = mocks.hud.showCount
        controller.applyStateUpdate(.editing)

        XCTAssertEqual(mocks.hud.lastMode, .editing)
        XCTAssertEqual(mocks.hud.hideCount, 0)
        XCTAssertGreaterThanOrEqual(mocks.hud.showCount, showsAfterTranscribing)
    }

    func testReadyWhenAPIKeyConfiguredAndPermissionsGranted() {
        let mocks = makeMocks(audioLevel: 0.2)
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(openAIKey: "sk-test", model: "gpt-4o-mini-transcribe", language: "en")
        )

        XCTAssertEqual(controller.readinessStatus, .ready)
        XCTAssertEqual(controller.statusText, "Ready")
    }

    func testNotReadyWhenAPIKeyMissing() {
        let mocks = makeMocks(audioLevel: 0.2)
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(openAIKey: "", model: "gpt-4o-mini-transcribe", language: "en")
        )

        XCTAssertEqual(controller.readinessStatus, .signInRequired)
    }

    func testSignOutClearsReadiness() {
        let mocks = makeMocks(audioLevel: 0.2)
        let inMemoryProvider = InMemoryAPIKeyProvider()
        inMemoryProvider.setAPIKey("sk-test")
        let controller = makeController(
            mocks: mocks,
            config: AppConfig(
                keyProvider: { inMemoryProvider.currentAPIKey() },
                model: "gpt-4o-mini-transcribe",
                language: "en"
            ),
            inMemoryKeyProvider: inMemoryProvider
        )

        XCTAssertEqual(controller.readinessStatus, .ready)

        controller.signOut()
        XCTAssertEqual(controller.readinessStatus, .signInRequired)
        XCTAssertFalse(controller.isSignedIn)
    }

    func testRestoreSessionOnLaunchSetsAPIKey() async {
        let mocks = makeMocks(audioLevel: 0.2)
        let sessionStore = MenuMockSessionStore()
        let session = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            userId: "u1",
            email: "test@example.com"
        )
        try! sessionStore.saveSession(session)

        let backendAuth = MenuMockBackendAuthClient()
        backendAuth.apiKeyToReturn = "sk-from-backend"
        let inMemoryProvider = InMemoryAPIKeyProvider()

        let controller = makeController(
            mocks: mocks,
            config: AppConfig(
                keyProvider: { inMemoryProvider.currentAPIKey() },
                model: "gpt-4o-mini-transcribe",
                language: "en"
            ),
            inMemoryKeyProvider: inMemoryProvider,
            sessionStore: sessionStore,
            backendAuthClient: backendAuth
        )

        await controller.restoreSessionOnLaunch()

        XCTAssertTrue(controller.isSignedIn)
        XCTAssertEqual(controller.signedInEmail, "test@example.com")
        XCTAssertEqual(inMemoryProvider.currentAPIKey(), "sk-from-backend")
        XCTAssertEqual(controller.readinessStatus, .ready)
    }

    func testDismissConfigurationCallsPresenterDismiss() {
        let mocks = makeMocks(audioLevel: 0.2)
        let presenter = MenuMockConfigurationPresenter()
        let controller = makeController(
            mocks: mocks,
            configurationPresenter: presenter
        )

        controller.dismissConfiguration()
        XCTAssertEqual(presenter.dismissCalls, 1)
    }

    func testPrepareMicrophonePermissionOnSetupOpenRequestsWhenNotDetermined() async {
        let permissionService = MenuMockPermissionService(
            snapshot: PermissionSnapshot(microphone: .notDetermined, accessibility: .granted, inputMonitoring: .granted)
        )
        let mocks = makeMocks(audioLevel: 0.2, permissionService: permissionService)
        let defaults = makeIsolatedDefaults()
        let promptKey = "MenuBarControllerTests.DidAttemptInitialMicrophonePrompt"
        let controller = makeController(
            mocks: mocks,
            appDefaults: defaults,
            initialMicrophonePromptAttemptKey: promptKey
        )

        await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()

        XCTAssertEqual(permissionService.microphoneRequestCount, 1)
        XCTAssertEqual(controller.permissionSnapshot.microphone, .granted)
        XCTAssertTrue(defaults.bool(forKey: promptKey))
        XCTAssertFalse(controller.isPreparingInitialMicrophonePrompt)
    }

    func testPrepareMicrophonePermissionOnSetupOpenSkipsWhenMicrophoneAlreadyGranted() async {
        let permissionService = MenuMockPermissionService(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        )
        let mocks = makeMocks(audioLevel: 0.2, permissionService: permissionService)
        let defaults = makeIsolatedDefaults()
        let promptKey = "MenuBarControllerTests.DidAttemptInitialMicrophonePrompt"
        let controller = makeController(
            mocks: mocks,
            appDefaults: defaults,
            initialMicrophonePromptAttemptKey: promptKey
        )

        await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()

        XCTAssertEqual(permissionService.microphoneRequestCount, 0)
        XCTAssertFalse(defaults.bool(forKey: promptKey))
    }

    func testPrepareMicrophonePermissionOnSetupOpenSkipsWhenMicrophoneDenied() async {
        let permissionService = MenuMockPermissionService(
            snapshot: PermissionSnapshot(microphone: .denied, accessibility: .granted, inputMonitoring: .granted)
        )
        let mocks = makeMocks(audioLevel: 0.2, permissionService: permissionService)
        let defaults = makeIsolatedDefaults()
        let promptKey = "MenuBarControllerTests.DidAttemptInitialMicrophonePrompt"
        let controller = makeController(
            mocks: mocks,
            appDefaults: defaults,
            initialMicrophonePromptAttemptKey: promptKey
        )

        await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()

        XCTAssertEqual(permissionService.microphoneRequestCount, 0)
        XCTAssertFalse(defaults.bool(forKey: promptKey))
    }

    func testPrepareMicrophonePermissionOnSetupOpenSkipsWhenInitialAttemptAlreadyRecorded() async {
        let permissionService = MenuMockPermissionService(
            snapshot: PermissionSnapshot(microphone: .notDetermined, accessibility: .granted, inputMonitoring: .granted)
        )
        let mocks = makeMocks(audioLevel: 0.2, permissionService: permissionService)
        let defaults = makeIsolatedDefaults()
        let promptKey = "MenuBarControllerTests.DidAttemptInitialMicrophonePrompt"
        defaults.set(true, forKey: promptKey)
        let controller = makeController(
            mocks: mocks,
            appDefaults: defaults,
            initialMicrophonePromptAttemptKey: promptKey
        )

        await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()

        XCTAssertEqual(permissionService.microphoneRequestCount, 0)
        XCTAssertEqual(controller.permissionSnapshot.microphone, .notDetermined)
    }

    func testPrepareMicrophonePermissionOnSetupOpenTracksDeniedResultAndDoesNotRePrompt() async {
        let permissionService = MenuMockPermissionService(
            snapshot: PermissionSnapshot(microphone: .notDetermined, accessibility: .granted, inputMonitoring: .granted)
        )
        permissionService.microphoneRequestResult = false
        let mocks = makeMocks(audioLevel: 0.2, permissionService: permissionService)
        let defaults = makeIsolatedDefaults()
        let promptKey = "MenuBarControllerTests.DidAttemptInitialMicrophonePrompt"
        let controller = makeController(
            mocks: mocks,
            appDefaults: defaults,
            initialMicrophonePromptAttemptKey: promptKey
        )

        await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()
        await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()

        XCTAssertEqual(permissionService.microphoneRequestCount, 1)
        XCTAssertEqual(controller.permissionSnapshot.microphone, .denied)
        XCTAssertTrue(defaults.bool(forKey: promptKey))
    }

    func testPrepareMicrophonePermissionOnSetupOpenInFlightGuardPreventsDuplicateRequests() async {
        let permissionService = MenuMockPermissionService(
            snapshot: PermissionSnapshot(microphone: .notDetermined, accessibility: .granted, inputMonitoring: .granted)
        )
        permissionService.microphoneRequestDelayNanoseconds = 150_000_000
        let mocks = makeMocks(audioLevel: 0.2, permissionService: permissionService)
        let defaults = makeIsolatedDefaults()
        let promptKey = "MenuBarControllerTests.DidAttemptInitialMicrophonePrompt"
        let controller = makeController(
            mocks: mocks,
            appDefaults: defaults,
            initialMicrophonePromptAttemptKey: promptKey
        )

        async let first: Void = controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()
        async let second: Void = controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()
        _ = await (first, second)

        XCTAssertEqual(permissionService.microphoneRequestCount, 1)
        XCTAssertFalse(controller.isPreparingInitialMicrophonePrompt)
    }

    private func makeController(
        mocks: ControllerMocks,
        config: AppConfig = AppConfig(openAIKey: "test", model: "gpt-4o-mini-transcribe", language: "en"),
        inMemoryKeyProvider: InMemoryAPIKeyProvider? = nil,
        sessionStore: SessionStoring = MenuMockSessionStore(),
        backendAuthClient: BackendAuthenticating = MenuMockBackendAuthClient(),
        configurationPresenter: ConfigurationPresenting = MenuMockConfigurationPresenter(),
        appDefaults: UserDefaults = .standard,
        initialMicrophonePromptAttemptKey: String = "WhisperAnywhere.DidAttemptInitialMicrophonePrompt"
    ) -> MenuBarController {
        let provider = inMemoryKeyProvider ?? {
            let p = InMemoryAPIKeyProvider()
            if !config.openAIKey.isEmpty {
                p.setAPIKey(config.openAIKey)
            }
            return p
        }()

        return MenuBarController(
            config: config,
            inMemoryKeyProvider: provider,
            sessionStore: sessionStore,
            backendAuthClient: backendAuthClient,
            configurationPresenter: configurationPresenter,
            appDefaults: appDefaults,
            initialMicrophonePromptAttemptKey: initialMicrophonePromptAttemptKey,
            permissionService: mocks.permissionService,
            notifier: mocks.notifier,
            fnMonitor: mocks.fnMonitor,
            audioCapture: mocks.audioCapture,
            textInserter: MenuMockTextInserter(),
            clipboard: MenuMockClipboard(),
            chimeService: mocks.chime,
            hudController: mocks.hud,
            autoStart: false
        )
    }

    private func makeMocks(
        audioLevel: Float,
        permissionService: MenuMockPermissionService = MenuMockPermissionService()
    ) -> ControllerMocks {
        ControllerMocks(
            permissionService: permissionService,
            notifier: MenuMockNotifier(),
            fnMonitor: MenuMockFnMonitor(),
            audioCapture: MenuMockAudioCapture(level: audioLevel),
            chime: MenuMockChimeService(),
            hud: MenuMockHUDController()
        )
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "MenuBarControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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
    private var snapshotValue: PermissionSnapshot
    private(set) var microphoneRequestCount = 0
    var microphoneRequestResult = true
    var microphoneRequestDelayNanoseconds: UInt64 = 0

    init(snapshot: PermissionSnapshot = PermissionSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)) {
        snapshotValue = snapshot
    }

    func snapshot() -> PermissionSnapshot {
        return snapshotValue
    }

    func requestMicrophoneAccess() async -> Bool {
        microphoneRequestCount += 1
        let result = microphoneRequestResult
        let delay = microphoneRequestDelayNanoseconds

        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }

        snapshotValue = PermissionSnapshot(
            microphone: result ? .granted : .denied,
            accessibility: snapshotValue.accessibility,
            inputMonitoring: snapshotValue.inputMonitoring
        )

        return result
    }

    func requestAccessibilityAccess() -> Bool {
        snapshotValue = PermissionSnapshot(
            microphone: snapshotValue.microphone,
            accessibility: .granted,
            inputMonitoring: snapshotValue.inputMonitoring
        )
        return true
    }

    func requestInputMonitoringAccess() -> Bool {
        snapshotValue = PermissionSnapshot(
            microphone: snapshotValue.microphone,
            accessibility: snapshotValue.accessibility,
            inputMonitoring: .granted
        )
        return true
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

private final class MenuMockClipboard: ClipboardWriting, @unchecked Sendable {
    func copy(_ text: String) {}
}

private final class MenuMockSessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    func loadSession() -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func saveSession(_ session: AuthSession) throws {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func clearSession() throws {
        lock.lock()
        session = nil
        lock.unlock()
    }
}

private final class MenuMockBackendAuthClient: BackendAuthenticating, @unchecked Sendable {
    var apiKeyToReturn = "sk-mock-key"
    var sessionToReturn: AuthSession?

    func beginGoogleSignIn(deviceID: String, appVersion: String) async throws -> URL {
        URL(string: "https://example.com/oauth")!
    }

    func completeGoogleSignIn(oauthTokens: GoogleOAuthTokens, deviceID: String) async throws -> AuthSession {
        sessionToReturn ?? AuthSession(
            accessToken: oauthTokens.accessToken,
            refreshToken: oauthTokens.refreshToken,
            expiresAt: Date().addingTimeInterval(3600),
            userId: "u1",
            email: "test@example.com"
        )
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        sessionToReturn ?? AuthSession(
            accessToken: "refreshed-access",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600),
            userId: "u1",
            email: "test@example.com"
        )
    }

    func fetchAPIKey(accessToken: String) async throws -> String {
        apiKeyToReturn
    }
}

@MainActor
private final class MenuMockConfigurationPresenter: ConfigurationPresenting {
    private(set) var showCalls = 0
    private(set) var dismissCalls = 0

    func show(controller: MenuBarController) {
        showCalls += 1
    }

    func dismiss() {
        dismissCalls += 1
    }
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
    private(set) var lastMode: RecordingHUDMode?
    private(set) var lastLevel: Float?

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
        lastLevel = level
    }
}
