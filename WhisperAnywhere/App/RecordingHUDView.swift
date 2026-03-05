import SwiftUI

enum RecordingHUDMode: Equatable {
    case recording
    case recordingEditCommand
    case transcribing
    case editing
    case message(String)
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    static let waveformSampleCount = 12
    static let waveformFloor: Float = 0.04

    @Published var bands: [Float] = Array(repeating: waveformFloor, count: waveformSampleCount)
    @Published var level: Float = waveformFloor
    @Published var mode: RecordingHUDMode = .recording
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        Group {
            if isRecordingMode {
                VStack(spacing: 2) {
                    if model.mode == .recordingEditCommand {
                        Text("Edit")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }

                    recordingIndicator
                }
            } else if model.mode == .transcribing {
                Text("Transcribing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if model.mode == .editing {
                Text("Editing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if case let .message(text) = model.mode {
                Text(text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.clear)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var isRecordingMode: Bool {
        model.mode == .recording || model.mode == .recordingEditCommand
    }

    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(dotOpacity(for: index)))
                        .scaleEffect(dotScale(for: index))
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.6)
                        )
                        .shadow(color: .white.opacity(0.25), radius: 1.2)
                }
            }
            .frame(width: 35, alignment: .leading)
            .frame(height: 16)
            .animation(.easeOut(duration: 0.08), value: model.level)
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let clamped = CGFloat(min(max(model.level, 0), 1))
        let eased = pow(clamped, 0.9)
        let baseScale: CGFloat = 0.42
        let dynamicRange: CGFloat = 0.56
        let multipliers: [CGFloat] = [0.82, 1.12, 0.94]
        return baseScale + (dynamicRange * eased * multipliers[index])
    }

    private func dotOpacity(for index: Int) -> Double {
        let clamped = Double(min(max(model.level, 0), 1))
        let base: [Double] = [0.58, 0.66, 0.62]
        let dynamic = 0.26 * clamped
        return min(0.98, base[index] + dynamic)
    }
}
