import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var controller: MenuBarController

    @State private var apiKeyDraft: String = ""
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                setupStep(
                    number: 1,
                    title: "Set API key",
                    state: accountStepDone ? .done : .actionNeeded,
                    detail: accountStepDone ? "API key saved" : "Enter your OpenAI API key",
                    content: {
                        accountStepContent
                    }
                )

                setupStep(
                    number: 2,
                    title: "Grant permissions",
                    state: permissionsStepDone ? .done : .actionNeeded,
                    detail: permissionsStepDone ? "All required permissions granted" : "Grant all required permissions",
                    content: {
                        permissionsStepContent
                    }
                )

                readinessGuidePanel
                footerActions
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
                await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup Whisper Anywhere")
                .font(.system(size: 22, weight: .semibold))

            Text("Hold Fn, speak, and release to dictate into your current text cursor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var accountStepContent: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private var permissionsStepContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            microphonePermissionRow

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
                Button("Request remaining permissions") {
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

    private var readinessGuidePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready to dictate")
                .font(.system(size: 15, weight: .semibold))

            if controller.readinessStatus == .ready {
                Text("Everything is ready. Click Done, then hold Fn to dictate.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(readinessGuideMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Current app status: \(controller.statusText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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

    private var footerActions: some View {
        HStack(spacing: 8) {
            if controller.readinessStatus != .ready {
                Text("Complete Steps 1 and 2 to continue.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                controller.dismissConfiguration()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.readinessStatus != .ready)
        }
    }

    private var accountStepDone: Bool {
        controller.apiKeyConfigured
    }

    private var permissionsStepDone: Bool {
        controller.permissionSnapshot.microphone == .granted &&
            controller.permissionSnapshot.accessibility == .granted &&
            controller.permissionSnapshot.inputMonitoring == .granted &&
            controller.monitorErrorMessage == nil
    }

    private var readinessGuideMessage: String {
        switch controller.readinessStatus {
        case .ready:
            return "Everything is ready."
        case .notEnoughPermissions:
            return "Finish permissions in Step 2."
        case .openAIKeyNotConfigured:
            return "Add your OpenAI API key in Step 1."
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

    @ViewBuilder
    private var microphonePermissionRow: some View {
        let state = controller.permissionSnapshot.microphone

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(state == .granted ? .green : .orange)

                Text("Microphone: \(permissionHeadline(for: state))")
                    .font(.system(size: 12, weight: .medium))
            }

            switch state {
            case .granted:
                Text("No action needed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .denied:
                Text("Open: System Settings -> Privacy & Security -> Microphone")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("Open Microphone Settings") {
                    controller.openSystemSettings(.microphone)
                }
                .font(.system(size: 11))
            case .notDetermined:
                Text(
                    "We request microphone access automatically. The app appears in Microphone settings only after the first access request."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if controller.isPreparingInitialMicrophonePrompt {
                    Text("Requesting access...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Allow Microphone Access") {
                        Task {
                            await controller.requestMicrophoneAccessFromConfiguration()
                        }
                    }
                    .font(.system(size: 11))
                }
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
