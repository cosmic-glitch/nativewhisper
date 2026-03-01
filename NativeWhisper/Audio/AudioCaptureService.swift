import AVFoundation
import Foundation

protocol AudioCapturing: Sendable {
    func start() throws
    func stop() throws -> URL
    func currentNormalizedInputLevel() -> Float?
}

enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case notRecording
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Audio recording is already in progress."
        case .notRecording:
            return "Audio recording is not active."
        case .failedToStart:
            return "Failed to start audio recording."
        }
    }
}

final class AudioCaptureService: NSObject, AudioCapturing, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func start() throws {
        guard recorder == nil else {
            throw AudioCaptureError.alreadyRecording
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nativewhisper-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioCaptureError.failedToStart
        }

        self.recorder = recorder
        currentURL = url
    }

    func stop() throws -> URL {
        guard let recorder, let currentURL else {
            throw AudioCaptureError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        return currentURL
    }

    func currentNormalizedInputLevel() -> Float? {
        guard let recorder else {
            return nil
        }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let amplitude = powf(10.0, averagePower / 20.0)
        return min(max(amplitude, 0), 1)
    }
}
