import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var controller: MenuBarController

    @State private var apiKeyDraft: String = ""
    @State private var saveMessage: String?
    @State private var emailDraft: String = ""
    @State private var otpDraft: String = ""
    @State private var turnstileDraft: String = ""
    @State private var isSendingCode = false
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuration")
                .font(.system(size: 20, weight: .semibold))

            Text(configurationSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            if controller.hostedModeEnabled {
                hostedAuthSection
            }

            if !controller.hostedModeEnabled || controller.shouldShowLegacyAPIKeyEntry {
                if controller.hostedModeEnabled {
                    Divider()
                }

                legacyAPIKeySection
            }

            Divider()

            permissionsSection

            Divider()

            HStack(spacing: 8) {
                Button("Test Permissions") {
                    controller.testPermissions()
                }

                Button("Refresh") {
                    controller.refreshPermissions()
                    Task {
                        await controller.refreshQuotaStatus()
                    }
                }

                Spacer()

                Text("Overall Status: \(controller.statusText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 560)
        .onAppear {
            controller.refreshPermissions()
            apiKeyDraft = controller.currentAPIKey()
            saveMessage = nil

            if let signedInEmail = controller.signedInEmail {
                emailDraft = signedInEmail
            }

            Task {
                await controller.refreshQuotaStatus()
            }
        }
    }

    private var configurationSubtitle: String {
        if controller.hostedModeEnabled {
            return "Sign in with email and verify required permissions."
        }

        return "Set your OpenAI API key and verify required permissions."
    }

    private var hostedAuthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(.system(size: 13, weight: .semibold))

            Text("Backend: \(controller.backendURLText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Status: \(controller.authSummaryText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if !controller.quotaSummaryText.isEmpty {
                Text(controller.quotaSummaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            TextField("Email", text: $emailDraft)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            SecureField("Verification code", text: $otpDraft)
                .textFieldStyle(.roundedBorder)

            TextField("Turnstile token (optional when not enforced)", text: $turnstileDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button(isSendingCode ? "Sending..." : "Send Code") {
                    guard !isSendingCode else {
                        return
                    }

                    isSendingCode = true
                    Task {
                        await controller.sendSignInCode(email: emailDraft, turnstileToken: turnstileDraft)
                        isSendingCode = false
                    }
                }
                .disabled(isSendingCode)

                Button(isVerifying ? "Signing In..." : "Sign In") {
                    guard !isVerifying else {
                        return
                    }

                    isVerifying = true
                    Task {
                        await controller.verifySignInCode(email: emailDraft, otp: otpDraft)
                        isVerifying = false
                    }
                }
                .disabled(isVerifying)

                Button("Refresh Quota") {
                    Task {
                        await controller.refreshQuotaStatus()
                    }
                }

                Button("Sign Out") {
                    controller.signOutHostedSession()
                }

                Spacer()
            }

            if let message = controller.authStatusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legacyAPIKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenAI API Key")
                .font(.system(size: 13, weight: .semibold))

            SecureField("sk-...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button("Save API Key") {
                    controller.saveAPIKey(apiKeyDraft)
                    saveMessage = "API key saved on this Mac."
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Status: \(controller.apiKeyConfigured ? "Configured" : "Not configured")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.system(size: 13, weight: .semibold))

            permissionBlock(
                title: "Microphone",
                state: controller.permissionSnapshot.microphone,
                route: "System Settings -> Privacy & Security -> Microphone",
                actionTitle: "Open Microphone Settings",
                action: {
                    controller.openSystemSettings(.microphone)
                }
            )

            permissionBlock(
                title: "Accessibility",
                state: controller.permissionSnapshot.accessibility,
                route: "System Settings -> Privacy & Security -> Accessibility",
                actionTitle: "Open Accessibility Settings",
                action: {
                    controller.openSystemSettings(.accessibility)
                }
            )

            permissionBlock(
                title: "Input Monitoring",
                state: controller.permissionSnapshot.inputMonitoring,
                route: "System Settings -> Privacy & Security -> Input Monitoring",
                actionTitle: "Open Input Monitoring Settings",
                action: {
                    controller.openSystemSettings(.inputMonitoring)
                }
            )
        }
    }

    @ViewBuilder
    private func permissionBlock(
        title: String,
        state: PermissionState,
        route: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(controller.permissionLabel(for: state))")
                .font(.system(size: 12, weight: .medium))

            Text("Navigate: \(route)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button(actionTitle, action: action)
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
