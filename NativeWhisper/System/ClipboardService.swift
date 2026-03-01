import AppKit

protocol ClipboardWriting: Sendable {
    func copy(_ text: String)
}

final class ClipboardService: ClipboardWriting, @unchecked Sendable {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
