import AppKit
import Foundation
import SwiftUI

enum AudioReactiveDogActivity: Equatable {
    case idle
    case recording
    case playing
    case transcribing

    var isAudioDriven: Bool {
        switch self {
        case .recording, .playing:
            return true
        case .idle, .transcribing:
            return false
        }
    }
}

struct AudioReactiveDogAnimationState: Equatable {
    let mouthOpenness: CGFloat
    let bodyScale: CGFloat
    let rotationDegrees: CGFloat
    let isBlinking: Bool
    let showsThinkingDots: Bool
    let thinkingDotScale: CGFloat

    static func state(activity: AudioReactiveDogActivity, amplitude: Float, date: Date) -> Self {
        let normalizedAmplitude = CGFloat(max(0, min(1, amplitude)))
        let time = date.timeIntervalSinceReferenceDate

        switch activity {
        case .recording, .playing:
            let mouthOpenness = audioDrivenMouthOpenness(for: normalizedAmplitude, time: time)
            return AudioReactiveDogAnimationState(
                mouthOpenness: mouthOpenness,
                bodyScale: 1 + min(0.035, normalizedAmplitude * 0.035),
                rotationDegrees: (normalizedAmplitude - 0.2) * 2.2,
                isBlinking: normalizedAmplitude < 0.08 && blinkPhase(at: time, interval: 3.8),
                showsThinkingDots: false,
                thinkingDotScale: 1
            )
        case .transcribing:
            let pulse = CGFloat((sin(time * 2.4) + 1) / 2)
            return AudioReactiveDogAnimationState(
                mouthOpenness: 0,
                bodyScale: 1 + pulse * 0.025,
                rotationDegrees: 0,
                isBlinking: blinkPhase(at: time, interval: 4.6),
                showsThinkingDots: true,
                thinkingDotScale: 0.72 + pulse * 0.28
            )
        case .idle:
            return AudioReactiveDogAnimationState(
                mouthOpenness: 0,
                bodyScale: 1,
                rotationDegrees: 0,
                isBlinking: blinkPhase(at: time, interval: 5.2),
                showsThinkingDots: false,
                thinkingDotScale: 1
            )
        }
    }

    private static func audioDrivenMouthOpenness(for amplitude: CGFloat, time: TimeInterval) -> CGFloat {
        let threshold: CGFloat = 0.03
        let intensity = min(1, max(0, (amplitude - threshold) / 0.22))
        guard intensity > 0 else { return 0 }

        let chatter = CGFloat((sin(time * (16 + Double(intensity) * 10)) + 1) / 2)
        return min(1, intensity * (0.45 + 0.55 * chatter))
    }

    private static func blinkPhase(at time: TimeInterval, interval: TimeInterval) -> Bool {
        time.truncatingRemainder(dividingBy: interval) < 0.11
    }
}

struct AudioReactiveDogLogo: View {
    let logo: NSImage?
    let activity: AudioReactiveDogActivity
    let amplitude: Float
    let statusColor: Color
    var size: CGFloat = 34
    var showsStatusDot = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
            let state = AudioReactiveDogAnimationState.state(
                activity: activity,
                amplitude: amplitude,
                date: timeline.date
            )

            ZStack {
                mascotImage(state: state)
                mouthOverlay(state: state)
                blinkOverlay(state: state)

                if state.showsThinkingDots {
                    thinkingDots(state: state)
                }

                if showsStatusDot {
                    statusDot
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .animation(.easeOut(duration: 0.08), value: state.mouthOpenness)
            .animation(.easeInOut(duration: 0.16), value: state.bodyScale)
            .animation(.easeInOut(duration: 0.12), value: state.isBlinking)
        }
    }

    @ViewBuilder
    private func mascotImage(state: AudioReactiveDogAnimationState) -> some View {
        if let logo {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .scaleEffect(state.bodyScale)
                .rotationEffect(.degrees(Double(state.rotationDegrees)))
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(statusColor.opacity(0.82))
                )
                .scaleEffect(state.bodyScale)
        }
    }

    private func mouthOverlay(state: AudioReactiveDogAnimationState) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.black.opacity(0.80), Color(red: 0.08, green: 0.11, blue: 0.16).opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(
                width: size * (0.18 + state.mouthOpenness * 0.16),
                height: size * (0.040 + state.mouthOpenness * 0.18)
            )
            .rotationEffect(.degrees(7))
            .offset(x: size * 0.045, y: size * 0.155)
            .opacity(activity.isAudioDriven ? 0.94 : 0)
            .allowsHitTesting(false)
    }

    private func blinkOverlay(state: AudioReactiveDogAnimationState) -> some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.68))
            .frame(width: size * 0.075, height: size * 0.012)
            .offset(x: size * 0.025, y: -size * 0.145)
            .opacity(state.isBlinking ? 0.88 : 0)
            .allowsHitTesting(false)
    }

    private func thinkingDots(state: AudioReactiveDogAnimationState) -> some View {
        HStack(spacing: size * 0.025) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.72 - Double(index) * 0.12))
                    .frame(width: size * 0.055, height: size * 0.055)
                    .scaleEffect(state.thinkingDotScale - CGFloat(index) * 0.08)
            }
        }
        .offset(x: size * 0.19, y: -size * 0.25)
        .allowsHitTesting(false)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size * 0.24, height: size * 0.24)
            .overlay(Circle().stroke(Color(red: 0.065, green: 0.067, blue: 0.078), lineWidth: max(1, size * 0.045)))
            .shadow(color: statusColor.opacity(activity == .recording ? 0.55 : 0.18), radius: activity == .recording ? 6 : 2)
            .frame(width: size, height: size, alignment: .bottomTrailing)
            .allowsHitTesting(false)
    }

    private var accessibilityLabel: String {
        switch activity {
        case .idle:
            return "Sussurro mascot"
        case .recording:
            return "Sussurro mascot reacting to microphone input"
        case .playing:
            return "Sussurro mascot reacting to audio playback"
        case .transcribing:
            return "Sussurro mascot thinking while transcribing"
        }
    }
}
