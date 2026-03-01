import AppKit
import SwiftUI

@MainActor
protocol RecordingHUDControlling: AnyObject {
    func show()
    func hide()
    func setMode(_ mode: RecordingHUDMode)
    func update(level: Float)
    func update(bands: [Float])
}

@MainActor
final class RecordingHUDWindowController: RecordingHUDControlling {
    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
        override var isOpaque: Bool { false }
    }

    private let model = RecordingHUDModel()
    private var mode: RecordingHUDMode = .recording
    private lazy var panel: NSPanel = {
        let size = panelSize(for: .recording)
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
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let hostingView = TransparentHostingView(rootView: RecordingHUDView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        return panel
    }()

    func show() {
        resizePanel(for: mode)
        positionPanel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func setMode(_ mode: RecordingHUDMode) {
        self.mode = mode
        model.mode = mode
        resizePanel(for: mode)
    }

    func update(level: Float) {
        let clamped = min(max(level, 0), 1)
        model.bands = Array(repeating: clamped, count: 5)
    }

    func update(bands: [Float]) {
        guard !bands.isEmpty else {
            return
        }

        if bands.count >= 5 {
            model.bands = Array(bands.prefix(5)).map { min(max($0, 0), 1) }
        } else {
            let padded = bands + Array(repeating: 0.04, count: 5 - bands.count)
            model.bands = padded.map { min(max($0, 0), 1) }
        }
    }

    private func resizePanel(for mode: RecordingHUDMode) {
        let size = panelSize(for: mode)
        panel.setContentSize(size)
        positionPanel()
    }

    private func panelSize(for mode: RecordingHUDMode) -> NSSize {
        switch mode {
        case .recording:
            return NSSize(width: 150, height: 36)
        case .transcribing:
            return NSSize(width: 210, height: 36)
        case .message:
            return NSSize(width: 290, height: 36)
        }
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
