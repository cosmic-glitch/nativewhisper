@preconcurrency import ApplicationServices
import Foundation

protocol FocusResolving: Sendable {
    func isEditableElementFocused() -> Bool
}

final class FocusResolver: FocusResolving, @unchecked Sendable {
    private static let editableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox"
    ]

    func isEditableElementFocused() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard status == .success,
              let focusedObject,
              CFGetTypeID(focusedObject) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedElement = focusedObject as! AXUIElement

        if let editable = boolAttribute("AXEditable" as CFString, element: focusedElement) {
            return editable
        }

        if let role = stringAttribute(kAXRoleAttribute as CFString, element: focusedElement) {
            return Self.editableRoles.contains(role)
        }

        return false
    }

    private func boolAttribute(_ key: CFString, element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key, &value)
        guard status == .success, let value else {
            return nil
        }
        return value as? Bool
    }

    private func stringAttribute(_ key: CFString, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }
}
