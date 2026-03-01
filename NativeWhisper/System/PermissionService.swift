import AVFoundation
@preconcurrency import ApplicationServices

enum PermissionState: String {
    case granted
    case denied
    case notDetermined
}

struct PermissionSnapshot {
    let microphone: PermissionState
    let accessibility: PermissionState
    let inputMonitoring: PermissionState
}

protocol PermissionProviding: Sendable {
    func snapshot() -> PermissionSnapshot
    func requestMicrophoneAccess() async -> Bool
    func requestAccessibilityAccess() -> Bool
    func requestInputMonitoringAccess() -> Bool
}

final class PermissionService: PermissionProviding, @unchecked Sendable {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneState(),
            accessibility: accessibilityState(),
            inputMonitoring: inputMonitoringState()
        )
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoringAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestListenEventAccess()
        }
        return true
    }

    private func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private func accessibilityState() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    private func inputMonitoringState() -> PermissionState {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess() ? .granted : .denied
        }
        return .granted
    }
}
