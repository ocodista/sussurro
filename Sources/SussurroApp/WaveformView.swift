import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let isRecording: Bool
    var height: CGFloat = 56
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let barCount = max(1, levels.count)
            let availableWidth = max(0, geometry.size.width)
            let spacing = Self.barSpacing(for: availableWidth, barCount: barCount)
            let barWidth = Self.barWidth(for: availableWidth, barCount: barCount, spacing: spacing)

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
            .frame(width: availableWidth, height: geometry.size.height, alignment: .center)
            .clipped()
            .animation(.linear(duration: 0.08), value: levels)
        }
        .frame(height: height)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(isRecording ? 0.15 : 0.06), lineWidth: 1)
        )
    }

    private static func barSpacing(for availableWidth: CGFloat, barCount: Int) -> CGFloat {
        guard barCount > 1 else { return 0 }

        let minimumBarWidth: CGFloat = 1.5
        let maximumSpacingThatFits = max(
            0,
            (availableWidth - minimumBarWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
        )
        return min(3, maximumSpacingThatFits)
    }

    private static func barWidth(for availableWidth: CGFloat, barCount: Int, spacing: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(max(0, barCount - 1))
        let width = (availableWidth - totalSpacing) / CGFloat(max(1, barCount))
        return max(0, width)
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
