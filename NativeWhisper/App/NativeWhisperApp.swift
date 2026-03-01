import AppKit
import SwiftUI

final class NativeWhisperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct NativeWhisperApp: App {
    private enum PrivacyPane {
        case microphone
        case accessibility
        case inputMonitoring
        case privacySecurity
    }

    @NSApplicationDelegateAdaptor(NativeWhisperAppDelegate.self) private var appDelegate
    @StateObject private var controller = MenuBarController()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Status: \(controller.statusText)")
                    .font(.system(size: 12, weight: .semibold))

                if let monitorError = controller.monitorErrorMessage {
                    Text("Input monitor error: \(monitorError)")
                        .font(.system(size: 11))
                }

                Divider()

                Text("Permissions")
                    .font(.system(size: 12, weight: .semibold))

                permissionRow(label: "Microphone", state: controller.permissionSnapshot.microphone)
                permissionRow(label: "Accessibility", state: controller.permissionSnapshot.accessibility)
                permissionRow(label: "Input Monitoring", state: controller.permissionSnapshot.inputMonitoring)

                if hasDeniedPermissions {
                    Divider()

                    Text("Action Needed")
                        .font(.system(size: 12, weight: .semibold))

                    if controller.permissionSnapshot.microphone == .denied {
                        deniedPermissionBlock(
                            title: "Microphone is denied",
                            steps: "1) Open Microphone settings. 2) Enable NativeWhisper. 3) Quit and reopen NativeWhisper.",
                            actionTitle: "Open Microphone Settings"
                        ) {
                            openSystemSettings(.microphone)
                        }
                    }

                    if controller.permissionSnapshot.accessibility == .denied {
                        deniedPermissionBlock(
                            title: "Accessibility is denied",
                            steps: "1) Open Accessibility settings. 2) Enable NativeWhisper. 3) Quit and reopen NativeWhisper.",
                            actionTitle: "Open Accessibility Settings"
                        ) {
                            openSystemSettings(.accessibility)
                        }
                    }

                    if controller.permissionSnapshot.inputMonitoring == .denied {
                        deniedPermissionBlock(
                            title: "Input Monitoring is denied",
                            steps: "1) Open Input Monitoring settings. 2) Enable NativeWhisper. 3) Quit and reopen NativeWhisper.",
                            actionTitle: "Open Input Monitoring Settings"
                        ) {
                            openSystemSettings(.inputMonitoring)
                        }
                    }

                    Text("If NativeWhisper is already enabled in Settings but still shows denied after an update, toggle it off, quit the app, toggle it on, then relaunch.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button("Open Privacy & Security") {
                        openSystemSettings(.privacySecurity)
                    }
                }

                Divider()

                Button("Test Permissions") {
                    controller.testPermissions()
                }

                Button("Refresh Status") {
                    controller.refreshPermissions()
                }

                Button("Quit") {
                    controller.quitApp()
                }
            }
            .padding(10)
            .frame(minWidth: 360)
            .onAppear {
                controller.refreshPermissions()
            }
        } label: {
            Label("NativeWhisper", systemImage: controller.menuIconName)
        }
        .menuBarExtraStyle(.window)
    }

    private var hasDeniedPermissions: Bool {
        controller.permissionSnapshot.microphone == .denied ||
            controller.permissionSnapshot.accessibility == .denied ||
            controller.permissionSnapshot.inputMonitoring == .denied
    }

    @ViewBuilder
    private func permissionRow(label: String, state: PermissionState) -> some View {
        Text("\(label): \(permissionLabel(for: state))")
            .font(.system(size: 11))
    }

    @ViewBuilder
    private func deniedPermissionBlock(
        title: String,
        steps: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))

        Text(steps)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        Button(actionTitle, action: action)
    }

    private func permissionLabel(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        }
    }

    private func openSystemSettings(_ pane: PrivacyPane) {
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
}
