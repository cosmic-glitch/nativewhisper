import SwiftUI

enum RecordingHUDMode: Equatable {
    case recording
    case transcribing
    case message(String)
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var bands: [Float] = Array(repeating: 0.08, count: 5)
    @Published var mode: RecordingHUDMode = .recording
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        Group {
            if model.mode == .recording {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    HStack(spacing: 4) {
                        ForEach(Array(model.bands.enumerated()), id: \.offset) { index, band in
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 4, height: barHeight(for: band))
                        }
                    }
                    .frame(height: 18)
                    .animation(.easeOut(duration: 0.08), value: model.bands)
                }
            } else if model.mode == .transcribing {
                Text("Transcribing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if case let .message(text) = model.mode {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.clear)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func barHeight(for band: Float) -> CGFloat {
        let clamped = CGFloat(min(max(band, 0), 1))
        let floor: CGFloat = 0.01
        let adjusted = max(clamped, floor)
        let boosted = pow(adjusted, 1.1)
        let minHeight: CGFloat = 3
        let dynamicRange: CGFloat = 17
        return minHeight + (boosted * dynamicRange)
    }
}
