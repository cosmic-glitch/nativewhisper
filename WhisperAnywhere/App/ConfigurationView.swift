import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var controller: MenuBarController

    @State private var testText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            Divider()
            accountSection
            Divider()
            permissionsSection
            Divider()
            tryItSection
            Divider()
            footerActions
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 520)
        .onAppear {
            controller.refreshPermissions()
            Task {
                await controller.prepareMicrophonePermissionOnSetupOpenIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("Whisper Anywhere Configuration")
            .font(.system(size: 20, weight: .semibold))
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.system(size: 13, weight: .semibold))

            if controller.isSignedIn {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))

                    if let email = controller.signedInEmail {
                        Text(email)
                            .font(.system(size: 12))
                    } else {
                        Text("Signed in")
                            .font(.system(size: 12))
                    }

                    Spacer()

                    Button("Sign Out") {
                        controller.signOut()
                    }
                    .font(.system(size: 11))
                }
            } else {
                if controller.isSigningIn {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Signing in...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sign in with Google") {
                        controller.signInWithGoogle()
                    }
                }
            }

            if let message = controller.authStatusMessage,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.system(size: 13, weight: .semibold))

            compactPermissionRow(
                title: "Microphone",
                state: controller.permissionSnapshot.microphone,
                explanation: "Whisper Anywhere records your voice to transcribe it. macOS requires microphone permission for this.",
                steps: microphoneSteps,
                action: microphoneAction
            )

            compactPermissionRow(
                title: "Accessibility",
                state: controller.permissionSnapshot.accessibility,
                explanation: "Whisper Anywhere types transcribed text into your active text field. macOS requires Accessibility permission for this.",
                steps: [
                    "Click \"Open Settings\" below",
                    "Find \"Whisper Anywhere\" in the list",
                    "Toggle it ON",
                    "Come back here and click Refresh"
                ],
                action: ("Open Accessibility Settings", {
                    controller.openSystemSettings(.accessibility)
                })
            )

            compactPermissionRow(
                title: "Input Monitoring",
                state: controller.permissionSnapshot.inputMonitoring,
                explanation: "Whisper Anywhere listens for the Fn key to start and stop recording. macOS requires Input Monitoring permission for this.",
                steps: [
                    "Click \"Open Settings\" below",
                    "Find \"Whisper Anywhere\" in the list",
                    "Toggle it ON",
                    "Come back here and click Refresh"
                ],
                action: ("Open Input Monitoring Settings", {
                    controller.openSystemSettings(.inputMonitoring)
                })
            )

            if hasAnyDeniedPermission {
                HStack(spacing: 8) {
                    Button("Request Permissions") {
                        controller.testPermissions()
                    }
                    .font(.system(size: 11))

                    Button("Refresh") {
                        controller.refreshPermissions()
                    }
                    .font(.system(size: 11))
                }
            }

            if let monitorError = controller.monitorErrorMessage,
               !monitorError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(monitorError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Try It

    private var tryItSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try it")
                .font(.system(size: 13, weight: .semibold))

            if controller.readinessStatus == .ready {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Click the text box below")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("2. Hold the Fn key and speak")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("3. Release Fn \u{2014} your words appear in the box")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                TextField("Your transcribed text will appear here", text: $testText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            } else {
                Text(tryItBlockedMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(true)
                    .opacity(0.4)
            }
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        VStack(spacing: 8) {
            Button("Done") {
                controller.dismissConfiguration()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.readinessStatus != .ready)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 4) {
                Text("Whisper Anywhere will keep running and appear as")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Image(systemName: MenuBarController.idleMenuIconName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("on the right side of the menu bar on top.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Permission Row

    @ViewBuilder
    private func compactPermissionRow(
        title: String,
        state: PermissionState,
        explanation: String,
        steps: [String],
        action: (String, () -> Void)?
    ) -> some View {
        if state == .granted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))

                Text(title)
                    .font(.system(size: 12))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))

                    Text("\(title) \u{2014} Not granted")
                        .font(.system(size: 12, weight: .medium))
                }

                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if let (title, handler) = action {
                    Button(title, action: handler)
                        .font(.system(size: 11))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.06))
            )
        }
    }

    // MARK: - Helpers

    private var microphoneSteps: [String] {
        switch controller.permissionSnapshot.microphone {
        case .notDetermined:
            return [
                "Click \"Allow Microphone Access\" below",
                "Click \"Allow\" in the macOS prompt that appears"
            ]
        case .denied:
            return [
                "Click \"Open Settings\" below",
                "Find \"Whisper Anywhere\" in the list",
                "Toggle it ON",
                "Come back here and click Refresh"
            ]
        case .granted:
            return []
        }
    }

    private var microphoneAction: (String, () -> Void)? {
        switch controller.permissionSnapshot.microphone {
        case .notDetermined:
            return ("Allow Microphone Access", {
                Task {
                    await controller.requestMicrophoneAccessFromConfiguration()
                }
            })
        case .denied:
            return ("Open Microphone Settings", {
                controller.openSystemSettings(.microphone)
            })
        case .granted:
            return nil
        }
    }

    private var hasAnyDeniedPermission: Bool {
        controller.permissionSnapshot.microphone != .granted ||
            controller.permissionSnapshot.accessibility != .granted ||
            controller.permissionSnapshot.inputMonitoring != .granted
    }

    private var tryItBlockedMessage: String {
        switch controller.readinessStatus {
        case .ready:
            return ""
        case .signInRequired:
            return "Sign in above to get started."
        case .notEnoughPermissions:
            return "Grant all permissions above to get started."
        }
    }
}
