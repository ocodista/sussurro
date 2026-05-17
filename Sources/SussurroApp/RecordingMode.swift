import Foundation

enum RecordingMode: String, CaseIterable, Identifiable, Sendable {
    case dictation
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            return "Dictation"
        case .meeting:
            return "Meeting"
        }
    }

    var detail: String {
        switch self {
        case .dictation:
            return "Microphone only"
        case .meeting:
            return "Mic + system audio · Person A/B"
        }
    }
}

struct RecordedAudio: Sendable, Equatable {
    let mode: RecordingMode
    let microphoneURL: URL
    let systemAudioURL: URL?
    let microphoneStartedAt: Date
    let systemAudioStartedAt: Date?

    var primaryURL: URL { microphoneURL }

    var isMeetingRecording: Bool {
        mode == .meeting
    }
}
