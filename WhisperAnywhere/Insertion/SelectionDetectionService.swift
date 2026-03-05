import AppKit
@preconcurrency import ApplicationServices
import OSLog

protocol SelectionDetecting: Sendable {
    func detectSelectedText() async -> String?
}

struct NoSelectionDetector: SelectionDetecting {
    func detectSelectedText() async -> String? {
        nil
    }
}

final class CopySelectionDetector: SelectionDetecting, @unchecked Sendable {
    private let logger = Logger(subsystem: "ai.whisperanywhere.app", category: "SelectionDetector")
    private let keyCodeC: CGKeyCode = 8
    private let copyPropagationDelayNanoseconds: UInt64

    init(copyPropagationDelayNanoseconds: UInt64 = 75_000_000) {
        self.copyPropagationDelayNanoseconds = copyPropagationDelayNanoseconds
    }

    func detectSelectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.error("Selection detection skipped: Accessibility trust unavailable")
            return nil
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        defer {
            snapshot.restore(to: pasteboard)
        }

        guard postCommandC() else {
            logger.error("Selection detection failed: unable to post Cmd+C")
            return nil
        }

        try? await Task.sleep(nanoseconds: copyPropagationDelayNanoseconds)

        guard pasteboard.changeCount != initialChangeCount else {
            logger.info("Selection detection: clipboard unchanged after Cmd+C")
            return nil
        }

        guard let copiedText = pasteboard.string(forType: .string),
              !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("Selection detection: clipboard updated but no non-empty string selection")
            return nil
        }

        logger.info("Selection detection succeeded selectedChars=\(copiedText.count, privacy: .public)")
        return copiedText
    }

    private func postCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var typeMap: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeMap[type] = data
                }
            }
            return typeMap
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else {
            return
        }

        let restoredItems = items.map { typeMap in
            let item = NSPasteboardItem()
            for (type, data) in typeMap {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
