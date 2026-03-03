import AppKit
import SwiftUI

@MainActor
protocol ConfigurationPresenting: AnyObject {
    func show(controller: MenuBarController)
    func dismiss()
}

@MainActor
final class ConfigurationWindowController: ConfigurationPresenting {
    private var window: NSWindow?

    func show(controller: MenuBarController) {
        let window = window ?? makeWindow()
        window.contentView = NSHostingView(rootView: ConfigurationView(controller: controller))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard let window else {
            return
        }
        window.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Whisper Anywhere Configuration"
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        return window
    }
}
