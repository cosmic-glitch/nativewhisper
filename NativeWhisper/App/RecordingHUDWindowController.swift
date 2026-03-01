import AppKit
import SwiftUI

@MainActor
protocol RecordingHUDControlling: AnyObject {
    func show()
    func hide()
    func update(level: Float)
}

@MainActor
final class RecordingHUDWindowController: RecordingHUDControlling {
    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let model = RecordingHUDModel()
    private lazy var panel: NSPanel = {
        let size = NSSize(width: 154, height: 46)
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: RecordingHUDView(model: model))
        return panel
    }()

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func update(level: Float) {
        model.level = min(max(level, 0), 1)
    }

    private func positionPanel() {
        let targetScreen = screenForPresentation()
        let frame = panel.frame
        let x = targetScreen.frame.midX - (frame.width / 2)
        let y = targetScreen.frame.minY + 74
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func screenForPresentation() -> NSScreen {
        let mousePoint = NSEvent.mouseLocation
        if let hovered = NSScreen.screens.first(where: { $0.frame.contains(mousePoint) }) {
            return hovered
        }

        return NSScreen.main ?? NSScreen.screens[0]
    }
}
