import AppKit
import Foundation

protocol Chiming: Sendable {
    @MainActor
    func playStartChime()
}

final class SystemChimeService: Chiming, @unchecked Sendable {
    private let soundURL = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
    private lazy var sound: NSSound? = NSSound(contentsOf: soundURL, byReference: true)

    @MainActor
    func playStartChime() {
        guard let sound else {
            NSSound.beep()
            return
        }

        if sound.isPlaying {
            sound.stop()
        }
        sound.play()
    }
}
