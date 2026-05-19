import AVFoundation
import Foundation

enum AudioFileMetadata {
    static func byteCount(for url: URL, fileManager: FileManager = .default) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }

        return size.int64Value
    }

    static func byteCount(for recording: RecordedAudio, fileManager: FileManager = .default) -> Int64? {
        let byteCounts = recording.audioURLs.compactMap { byteCount(for: $0, fileManager: fileManager) }
        guard !byteCounts.isEmpty else { return nil }
        return byteCounts.reduce(0, +)
    }

    static func duration(for url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = audioFile.fileFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return TimeInterval(audioFile.length) / sampleRate
    }

    static func duration(for recording: RecordedAudio) -> TimeInterval? {
        let referenceDate = [recording.microphoneStartedAt, recording.systemAudioStartedAt]
            .compactMap { $0 }
            .min() ?? recording.microphoneStartedAt
        var durations: [TimeInterval] = []

        if let microphoneDuration = duration(for: recording.microphoneURL) {
            let offset = max(0, recording.microphoneStartedAt.timeIntervalSince(referenceDate))
            durations.append(offset + microphoneDuration)
        }

        if let systemAudioURL = recording.systemAudioURL,
           let systemAudioDuration = duration(for: systemAudioURL)
        {
            let offset = max(0, (recording.systemAudioStartedAt ?? referenceDate).timeIntervalSince(referenceDate))
            durations.append(offset + systemAudioDuration)
        }

        return durations.max()
    }

    static func formattedFileSize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
