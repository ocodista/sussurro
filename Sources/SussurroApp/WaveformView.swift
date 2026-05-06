import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let isRecording: Bool

    var body: some View {
        GeometryReader { geometry in
            let barCount = max(1, levels.count)
            let spacing: CGFloat = 3
            let barWidth = max(2, (geometry.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    Capsule(style: .continuous)
                        .fill(barGradient(index: index, total: barCount))
                        .frame(
                            width: barWidth,
                            height: max(5, CGFloat(level) * geometry.size.height)
                        )
                        .shadow(color: isRecording ? Color.red.opacity(0.18) : .clear, radius: 8, y: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.08), value: levels)
        }
        .frame(height: 56)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(isRecording ? 0.15 : 0.06), lineWidth: 1)
        )
    }

    private func barGradient(index: Int, total: Int) -> LinearGradient {
        if isRecording {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.28, blue: 0.34), Color(red: 1.0, green: 0.62, blue: 0.45)],
                startPoint: .bottom,
                endPoint: .top
            )
        }

        let opacity = 0.16 + 0.16 * Double(index) / Double(max(total, 1))
        return LinearGradient(
            colors: [Color.white.opacity(opacity), Color.white.opacity(opacity + 0.08)],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
