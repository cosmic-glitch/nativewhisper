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
    case backendNotConfigured
    case signInRequired
    case servicePaused

    var label: String {
        switch self {
        case .ready:
            return "Ready"
        case .notEnoughPermissions:
            return "Not enough permissions"
        case .openAIKeyNotConfigured:
            return "OpenAI key not configured"
        case .backendNotConfigured:
            return "Backend not configured"
        case .signInRequired:
            return "Sign in required"
        case .servicePaused:
            return "Service paused"
        }
    }
}

private struct UnavailableTranscriptionClient: Transcribing {
    func transcribe(audioURL: URL) async throws -> String {
        throw BackendTranscriptionError.backendNotConfigured
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
    @Published private(set) var authSession: AuthSession?
    @Published private(set) var quotaStatus: QuotaStatus?
    @Published private(set) var authStatusMessage: String?
    @Published private(set) var selectedTranscriptionRoute: TranscriptionRoute

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
    private let legacyFirstLaunchConfigurationKey: String
    private let legacyBundleIdentifier: String
    private let transcriptionRouteStore: TranscriptionRouteStoring
    private let sessionStore: SessionStoring
    private let deviceIdentityStore: DeviceIdentifying
    private let authClient: BackendAuthenticating?
    private let googleSignInService: GoogleSignInProviding
    private let stateSink: DictationStateSink
    private let eventSink: DictationEventSink
    private let coordinator: DictationCoordinator

    private var meterTask: Task<Void, Never>?
    private var hudMessageTask: Task<Void, Never>?
    private var smoothedLevel: Float = 0.08
    private var smoothedBands: [Float] = Array(repeating: 0.08, count: 5)
    private var started = false

    let config: AppConfig

    var hostedModeEnabled: Bool {
        selectedTranscriptionRoute == .hosted
    }

    var availableTranscriptionRoutes: [TranscriptionRoute] {
        if config.hostedModeEnabled {
            return [.hosted, .direct]
        }
        return [.direct]
    }

    var canUseHostedRoute: Bool {
        config.hostedModeEnabled
    }

    var shouldShowLegacyAPIKeyEntry: Bool {
        config.allowLegacyPersonalKeyEntry
    }

    var backendConfigured: Bool {
        config.backendBaseURL != nil
    }

    var transcriptionRouteStatusText: String {
        switch selectedTranscriptionRoute {
        case .hosted:
            return "Hosted mode"
        case .direct:
            return "Direct OpenAI mode"
        }
    }

    var signedInEmail: String? {
        guard let email = authSession?.email.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return nil
        }
        return email
    }

    var isSignedIn: Bool {
        authSession != nil
    }

    var backendURLText: String {
        config.backendBaseURL?.absoluteString ?? "Not configured"
    }

    var quotaSummaryText: String {
        guard hostedModeEnabled else {
            return ""
        }

        guard let quotaStatus else {
            return "Daily usage: unavailable"
        }

        return "Daily remaining: \(quotaStatus.remainingToday) of \(quotaStatus.deviceCap)"
    }

    var authSummaryText: String {
        if hostedModeEnabled {
            if let signedInEmail {
                return "Signed in as \(signedInEmail)"
            }
            return "Not signed in"
        }

        return apiKeyConfigured ? "API key configured" : "API key not configured"
    }

    init(
        config: AppConfig? = nil,
        apiKeyStore: APIKeyStoring = APIKeyStore.shared,
        transcriptionRouteStore: TranscriptionRouteStoring = TranscriptionRouteStore.shared,
        sessionStore: SessionStoring = KeychainSessionStore.shared,
        deviceIdentityStore: DeviceIdentifying = DeviceIdentityStore.shared,
        authClient: BackendAuthenticating? = nil,
        googleSignInService: GoogleSignInProviding? = nil,
        configurationPresenter: ConfigurationPresenting = ConfigurationWindowController(),
        appDefaults: UserDefaults = .standard,
        firstLaunchConfigurationKey: String = "WhisperAnywhere.DidShowConfigurationOnFirstLaunch",
        legacyFirstLaunchConfigurationKey: String = "NativeWhisper.DidShowConfigurationOnFirstLaunch",
        legacyBundleIdentifier: String = "ai.nativewhisper.app",
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
        let resolvedConfig = config ?? AppConfig.load(apiKeyStore: apiKeyStore)

        self.config = resolvedConfig
        self.apiKeyStore = apiKeyStore
        self.sessionStore = sessionStore
        self.deviceIdentityStore = deviceIdentityStore
        self.configurationPresenter = configurationPresenter
        self.appDefaults = appDefaults
        self.firstLaunchConfigurationKey = firstLaunchConfigurationKey
        self.legacyFirstLaunchConfigurationKey = legacyFirstLaunchConfigurationKey
        self.legacyBundleIdentifier = legacyBundleIdentifier
        self.transcriptionRouteStore = transcriptionRouteStore
        self.permissionService = permissionService
        self.notifier = notifier
        self.fnMonitor = fnMonitor
        self.audioCapture = audioCapture
        self.chimeService = chimeService
        self.hudController = hudController
        self.stateSink = DictationStateSink()
        self.eventSink = DictationEventSink()
        self.permissionSnapshot = permissionService.snapshot()

        let persistedRoute = transcriptionRouteStore.currentRoute()
        let initialRoute: TranscriptionRoute
        if resolvedConfig.hostedModeEnabled {
            initialRoute = persistedRoute
        } else {
            initialRoute = .direct
            transcriptionRouteStore.saveRoute(.direct)
        }
        self.selectedTranscriptionRoute = initialRoute

        let resolvedAuthClient: BackendAuthenticating?
        if let authClient {
            resolvedAuthClient = authClient
        } else if resolvedConfig.hostedModeEnabled,
                  let backendBaseURL = resolvedConfig.backendBaseURL {
            resolvedAuthClient = BackendAuthClient(baseURL: backendBaseURL)
        } else {
            resolvedAuthClient = nil
        }
        self.authClient = resolvedAuthClient

        if let googleSignInService {
            self.googleSignInService = googleSignInService
        } else {
            self.googleSignInService = GoogleSignInService(callbackURL: resolvedConfig.googleAuthCallbackURL)
        }

        let initialSession = initialRoute == .hosted ? sessionStore.loadSession() : nil
        self.authSession = initialSession
        self.apiKeyConfigured = initialRoute == .hosted ? (initialSession != nil) : !resolvedConfig.openAIKey.isEmpty

        let hostedTranscriptionClient: Transcribing
        if let resolvedAuthClient,
           let backendBaseURL = resolvedConfig.backendBaseURL {
            hostedTranscriptionClient = BackendTranscriptionClient(
                baseURL: backendBaseURL,
                sessionStore: sessionStore,
                authClient: resolvedAuthClient,
                deviceIDProvider: deviceIdentityStore,
                language: resolvedConfig.language
            )
        } else {
            hostedTranscriptionClient = UnavailableTranscriptionClient()
        }

        let directTranscriptionClient = OpenAITranscriptionClient(config: resolvedConfig)
        let transcriptionClient = HybridTranscriptionClient(
            routeProvider: { transcriptionRouteStore.currentRoute() },
            hostedClient: hostedTranscriptionClient,
            directClient: directTranscriptionClient
        )

        self.coordinator = DictationCoordinator(
            audioCapture: audioCapture,
            transcriptionClient: transcriptionClient,
            textInserter: textInserter,
            focusResolver: focusResolver,
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
        if hostedModeEnabled {
            guard canUseHostedRoute else {
                return .backendNotConfigured
            }

            guard backendConfigured else {
                return .backendNotConfigured
            }

            guard isSignedIn else {
                return .signInRequired
            }

            if quotaStatus?.isServicePaused == true {
                return .servicePaused
            }

            guard hasRequiredPermissions else {
                return .notEnoughPermissions
            }

            return .ready
        }

        if !apiKeyConfigured {
            return .openAIKeyNotConfigured
        }

        guard hasRequiredPermissions else {
            return .notEnoughPermissions
        }

        return .ready
    }

    var statusText: String {
        "\(transcriptionRouteStatusText) • \(readinessStatus.label)"
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
        restoreHostedSessionIfNeeded()
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

    func openConfiguration() {
        configurationPresenter.show(controller: self)
    }

    func currentAPIKey() -> String {
        guard selectedTranscriptionRoute == .direct || shouldShowLegacyAPIKeyEntry else {
            return ""
        }
        return config.openAIKey
    }

    func saveAPIKey(_ value: String) {
        guard selectedTranscriptionRoute == .direct || shouldShowLegacyAPIKeyEntry else {
            return
        }

        apiKeyStore.saveAPIKey(value)
        syncAPIKeyStatus()
    }

    func setTranscriptionRoute(_ route: TranscriptionRoute) {
        guard route != selectedTranscriptionRoute else {
            return
        }

        guard case .idle = dictationState else {
            let message = "Finish current dictation before switching modes."
            authStatusMessage = message
            showTransientHUDMessage(message)
            return
        }

        guard availableTranscriptionRoutes.contains(route) else {
            authStatusMessage = "Hosted mode is disabled by configuration."
            return
        }

        selectedTranscriptionRoute = route
        transcriptionRouteStore.saveRoute(route)

        if route == .hosted {
            restoreHostedSessionIfNeeded()
            Task {
                await refreshQuotaStatus()
            }
        } else {
            quotaStatus = nil
            authStatusMessage = nil
        }

        syncAPIKeyStatus()
    }

    func signInWithGoogle() async {
        guard hostedModeEnabled else {
            authStatusMessage = "Switch to Hosted mode to sign in."
            return
        }

        guard canUseHostedRoute else {
            authStatusMessage = "Hosted mode is disabled by configuration."
            return
        }

        guard let authClient else {
            authStatusMessage = "Backend auth is not configured."
            return
        }

        do {
            authStatusMessage = "Opening Google sign-in..."
            let deviceID = deviceIdentityStore.deviceID()
            let startURL = try await authClient.beginGoogleSignIn(
                deviceID: deviceID,
                appVersion: appVersionString()
            )
            let oauthTokens = try await googleSignInService.authenticate(startURL: startURL)
            let session = try await authClient.completeGoogleSignIn(
                oauthTokens: oauthTokens,
                deviceID: deviceID
            )
            try sessionStore.saveSession(session)
            authSession = session
            syncAPIKeyStatus()
            authStatusMessage = "Signed in as \(session.email)."
            await refreshQuotaStatus()
        } catch let error as GoogleSignInError {
            authStatusMessage = error.localizedDescription
            if error != .cancelled {
                notifier.notify(title: "Whisper Anywhere", body: error.localizedDescription)
            }
        } catch {
            let message = error.localizedDescription
            authStatusMessage = message
            notifier.notify(title: "Whisper Anywhere", body: message)
        }
    }

    func signOutHostedSession() {
        do {
            try sessionStore.clearSession()
        } catch {
            notifier.notify(title: "Whisper Anywhere", body: error.localizedDescription)
        }

        authSession = nil
        quotaStatus = nil
        authStatusMessage = "Signed out."
        syncAPIKeyStatus()
    }

    func refreshQuotaStatus() async {
        guard hostedModeEnabled, canUseHostedRoute else {
            quotaStatus = nil
            return
        }

        await refreshHostedSessionIfNeeded(force: false)

        guard let authClient,
              let authSession else {
            quotaStatus = nil
            return
        }

        do {
            let quota = try await authClient.fetchQuota(
                accessToken: authSession.accessToken,
                deviceID: deviceIdentityStore.deviceID()
            )
            quotaStatus = quota
        } catch {
            quotaStatus = nil
            authStatusMessage = error.localizedDescription
        }
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

    private func restoreHostedSessionIfNeeded() {
        guard hostedModeEnabled, canUseHostedRoute else {
            return
        }

        authSession = sessionStore.loadSession()
        syncAPIKeyStatus()

        guard authSession != nil else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            await refreshHostedSessionIfNeeded(force: false)
            await refreshQuotaStatus()
        }
    }

    private func refreshHostedSessionIfNeeded(force: Bool) async {
        guard hostedModeEnabled,
              canUseHostedRoute,
              let authClient,
              let currentSession = authSession else {
            return
        }

        guard force || currentSession.isExpired else {
            return
        }

        do {
            let refreshed = try await authClient.refreshSession(refreshToken: currentSession.refreshToken)
            try sessionStore.saveSession(refreshed)
            authSession = refreshed
            syncAPIKeyStatus()
        } catch {
            authSession = nil
            quotaStatus = nil
            syncAPIKeyStatus()
            try? sessionStore.clearSession()
            authStatusMessage = "Session expired. Sign in again."
        }
    }

    private func syncAPIKeyStatus() {
        if hostedModeEnabled {
            apiKeyConfigured = authSession != nil
        } else {
            apiKeyConfigured = !config.openAIKey.isEmpty
        }
    }

    private func handleFnEvent(_ event: FnKeyEvent) {
        Task {
            if event == .pressed {
                if hostedModeEnabled {
                    await refreshHostedSessionIfNeeded(force: false)
                }

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

            if hostedModeEnabled, event == .released {
                await refreshQuotaStatus()
            }
        }
    }

    private func canStartDictationFromCurrentState() -> Bool {
        switch selectedTranscriptionRoute {
        case .hosted:
            guard canUseHostedRoute else {
                notifier.notify(title: "Whisper Anywhere", body: "Hosted mode is disabled by configuration.")
                return false
            }

            guard backendConfigured else {
                notifier.notify(title: "Whisper Anywhere", body: "Backend base URL is not configured.")
                return false
            }

            guard authSession != nil else {
                notifier.notify(title: "Whisper Anywhere", body: "Sign in required. Open Configure.")
                return false
            }

            if quotaStatus?.isServicePaused == true {
                notifier.notify(title: "Whisper Anywhere", body: "Service paused (daily budget reached).")
                return false
            }

            return true

        case .direct:
            if config.openAIKey.isEmpty {
                notifier.notify(title: "Whisper Anywhere", body: "OpenAI key not configured for Direct mode.")
                return false
            }
            return true
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

    private func appVersionString() -> String {
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !short.isEmpty {
            return short
        }

        return "dev"
    }
}
