import SwiftUI

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var level: Float = 0.08
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    private let barProfile: [CGFloat] = [0.68, 0.86, 1.0, 0.86, 0.68]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 4) {
                ForEach(Array(barProfile.enumerated()), id: \.offset) { index, profile in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 4, height: barHeight(index: index, profile: profile))
                }
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 3)
    }

    private func barHeight(index: Int, profile: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(max(model.level, 0), 1))
        let smoothedFloor: CGFloat = 0.10
        let adjusted = max(clamped, smoothedFloor)
        let minHeight: CGFloat = 5
        let dynamicRange: CGFloat = 17
        return minHeight + (adjusted * dynamicRange * profile)
    }
}
