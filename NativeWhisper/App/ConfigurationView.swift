import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var controller: MenuBarController

    @State private var apiKeyDraft: String = ""
    @State private var saveMessage: String?
    @State private var isSigningInWithGoogle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                setupStep(
                    number: 1,
                    title: accountStepTitle,
                    state: accountStepDone ? .done : .actionNeeded,
                    detail: accountStepDetail,
                    content: {
                        accountStepContent
                    }
                )

                setupStep(
                    number: 2,
                    title: "Grant permissions",
                    state: permissionsStepDone ? .done : .actionNeeded,
                    detail: permissionsStepDetail,
                    content: {
                        permissionsStepContent
                    }
                )

                setupStep(
                    number: 3,
                    title: "Start dictating",
                    state: readyStepDone ? .done : .actionNeeded,
                    detail: readyStepDetail,
                    content: {
                        readyStepContent
                    }
                )

                if controller.shouldShowLegacyAPIKeyEntry && controller.selectedTranscriptionRoute != .direct {
                    advancedSection
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 660, minHeight: 620)
        .onAppear {
            controller.refreshPermissions()
            apiKeyDraft = controller.currentAPIKey()
            saveMessage = nil

            Task {
                await controller.refreshQuotaStatus()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup Whisper Anywhere")
                .font(.system(size: 22, weight: .semibold))

            Text("Follow these steps once. After setup, place your cursor in any text field, hold Fn, speak, then release Fn.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var accountStepContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            routeSelector

            if controller.hostedModeEnabled {
                Text("Step 1: Continue with Google")
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 8) {
                    Button(isSigningInWithGoogle ? "Opening..." : "Continue with Google") {
                        guard !isSigningInWithGoogle else {
                            return
                        }

                        isSigningInWithGoogle = true
                        Task {
                            await controller.signInWithGoogle()
                            isSigningInWithGoogle = false
                        }
                    }
                    .disabled(isSigningInWithGoogle)

                    if !controller.isSignedIn {
                        Text("A Google sign-in window will open.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button("Sign out") {
                        controller.signOutHostedSession()
                    }
                    .disabled(!controller.isSignedIn)

                    Button("Refresh usage") {
                        Task {
                            await controller.refreshQuotaStatus()
                        }
                    }
                }

                if let message = controller.authStatusMessage,
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                directModeContent
            }

            if let quota = controller.quotaStatus {
                let used = max(0, quota.deviceCap - quota.remainingToday)
                Text("Usage today: \(used)/\(quota.deviceCap) requests used")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Connection details") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription route: \(controller.transcriptionRouteStatusText)")
                    Text("Service URL: \(controller.backendURLText)")
                    Text("Account status: \(controller.authSummaryText)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .font(.system(size: 11))
        }
    }

    private var routeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step 0: Choose transcription mode")
                .font(.system(size: 12, weight: .medium))

            Picker("Transcription mode", selection: transcriptionRouteBinding) {
                ForEach(controller.availableTranscriptionRoutes, id: \.rawValue) { route in
                    Text(route.label).tag(route)
                }
            }
            .pickerStyle(.segmented)

            Text(controller.hostedModeEnabled
                 ? "Hosted mode uses Whisper Anywhere sign-in and backend limits."
                 : "Direct mode sends audio straight to OpenAI using your personal key.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var directModeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 1: Enter your OpenAI API key")
                .font(.system(size: 12, weight: .medium))

            SecureField("sk-...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button("Save API key") {
                    controller.saveAPIKey(apiKeyDraft)
                    saveMessage = "API key saved on this Mac."
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Key status: \(controller.apiKeyConfigured ? "Configured" : "Not configured")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let message = controller.authStatusMessage,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptionRouteBinding: Binding<TranscriptionRoute> {
        Binding(
            get: { controller.selectedTranscriptionRoute },
            set: { route in
                controller.setTranscriptionRoute(route)
                apiKeyDraft = controller.currentAPIKey()
            }
        )
    }

    private var permissionsStepContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Microphone",
                state: controller.permissionSnapshot.microphone,
                route: "System Settings -> Privacy & Security -> Microphone",
                actionTitle: "Open Microphone Settings",
                action: {
                    controller.openSystemSettings(.microphone)
                }
            )

            permissionRow(
                title: "Accessibility",
                state: controller.permissionSnapshot.accessibility,
                route: "System Settings -> Privacy & Security -> Accessibility",
                actionTitle: "Open Accessibility Settings",
                action: {
                    controller.openSystemSettings(.accessibility)
                }
            )

            permissionRow(
                title: "Input Monitoring",
                state: controller.permissionSnapshot.inputMonitoring,
                route: "System Settings -> Privacy & Security -> Input Monitoring",
                actionTitle: "Open Input Monitoring Settings",
                action: {
                    controller.openSystemSettings(.inputMonitoring)
                }
            )

            HStack(spacing: 8) {
                Button("Request permissions") {
                    controller.testPermissions()
                }

                Button("Refresh") {
                    controller.refreshPermissions()
                }
            }

            if let monitorError = controller.monitorErrorMessage,
               !monitorError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(monitorError)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readyStepContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(readyInstruction)
                .font(.system(size: 12))

            if controller.readinessStatus == .ready {
                Text("Try it now: click any text field, hold Fn, speak, and release Fn.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Current app status: \(controller.statusText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advanced")
                .font(.system(size: 13, weight: .semibold))

            if controller.shouldShowLegacyAPIKeyEntry {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal OpenAI API key (legacy mode)")
                        .font(.system(size: 12, weight: .medium))

                    SecureField("sk-...", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button("Save API key") {
                            controller.saveAPIKey(apiKeyDraft)
                            saveMessage = "API key saved on this Mac."
                        }

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Key status: \(controller.apiKeyConfigured ? "Configured" : "Not configured")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No advanced settings needed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.45))
        )
    }

    private var accountStepDone: Bool {
        if controller.hostedModeEnabled {
            return controller.isSignedIn
        }
        return controller.apiKeyConfigured
    }

    private var accountStepTitle: String {
        controller.hostedModeEnabled ? "Sign in" : "Set API key"
    }

    private var permissionsStepDone: Bool {
        controller.permissionSnapshot.microphone == .granted &&
            controller.permissionSnapshot.accessibility == .granted &&
            controller.permissionSnapshot.inputMonitoring == .granted &&
            controller.monitorErrorMessage == nil
    }

    private var readyStepDone: Bool {
        controller.readinessStatus == .ready
    }

    private var accountStepDetail: String {
        if controller.hostedModeEnabled {
            return accountStepDone ? "Signed in" : "Sign in with Google to continue"
        }

        return accountStepDone ? "API key saved" : "Enter your OpenAI key to continue"
    }

    private var permissionsStepDetail: String {
        permissionsStepDone ? "All required permissions granted" : "Grant all required permissions"
    }

    private var readyStepDetail: String {
        readyStepDone ? "Everything is set" : "Complete previous steps"
    }

    private var readyInstruction: String {
        switch controller.readinessStatus {
        case .ready:
            return "You are ready to dictate."
        case .signInRequired:
            return "Finish Step 1 (Sign in) first."
        case .notEnoughPermissions:
            return "Finish Step 2 (Permissions) first."
        case .backendNotConfigured:
            return "Service setup is missing. Restart the app and try again."
        case .servicePaused:
            return "Service is temporarily paused because the daily budget was reached."
        case .openAIKeyNotConfigured:
            return "OpenAI key is missing in personal-key mode."
        }
    }

    @ViewBuilder
    private func setupStep<Content: View>(
        number: Int,
        title: String,
        state: SetupStepState,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(stepBadgeColor(for: state)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))

                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(state.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stepBadgeColor(for: state))
            }

            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.25))
                )
        )
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        state: PermissionState,
        route: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(state == .granted ? .green : .orange)

                Text("\(title): \(permissionHeadline(for: state))")
                    .font(.system(size: 12, weight: .medium))
            }

            if state != .granted {
                Text("Open: \(route)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button(actionTitle, action: action)
                    .font(.system(size: 11))
            } else {
                Text("No action needed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionHeadline(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "Granted"
        case .denied:
            return "Needs action"
        case .notDetermined:
            return "Not set yet"
        }
    }

    private func stepBadgeColor(for state: SetupStepState) -> Color {
        switch state {
        case .done:
            return .green
        case .actionNeeded:
            return .orange
        }
    }
}

private enum SetupStepState {
    case done
    case actionNeeded

    var label: String {
        switch self {
        case .done:
            return "Done"
        case .actionNeeded:
            return "Action needed"
        }
    }
}
