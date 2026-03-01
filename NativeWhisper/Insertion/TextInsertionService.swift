@preconcurrency import ApplicationServices
import Foundation

protocol TextInserting: Sendable {
    func insert(_ text: String) throws
}

enum TextInsertionServiceError: LocalizedError {
    case accessibilityPermissionMissing
    case eventSourceUnavailable
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required to insert text."
        case .eventSourceUnavailable:
            return "Unable to create keyboard event source."
        case .eventCreationFailed:
            return "Unable to create keyboard events for text insertion."
        }
    }
}

final class TextInsertionService: TextInserting, @unchecked Sendable {
    func insert(_ text: String) throws {
        guard !text.isEmpty else {
            return
        }

        guard AXIsProcessTrusted() else {
            throw TextInsertionServiceError.accessibilityPermissionMissing
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw TextInsertionServiceError.eventSourceUnavailable
        }

        for scalar in text.unicodeScalars {
            let utf16 = Array(String(scalar).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw TextInsertionServiceError.eventCreationFailed
            }

            utf16.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return
                }
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
