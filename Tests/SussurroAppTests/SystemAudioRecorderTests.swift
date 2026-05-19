import AudioToolbox
import CoreMedia
import ScreenCaptureKit
import XCTest
@testable import SussurroApp

final class SystemAudioRecorderTests: XCTestCase {
    func testRootMeanSquareLevelReadsFloatPCMSamples() throws {
        let sampleBuffer = try makeFloatSampleBuffer(samples: [0.05, -0.05, 0.05, -0.05])

        XCTAssertEqual(SystemAudioRecorder.rootMeanSquareLevel(for: sampleBuffer), 0.4, accuracy: 0.001)
    }

    func testScreenCaptureKitUserDeclinedErrorIsTreatedAsSystemAudioPermissionError() {
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.userDeclined.rawValue
        )

        XCTAssertTrue(SystemAudioRecorder.isSystemAudioPermissionError(error))
    }

    func testUnrelatedScreenCaptureKitErrorIsNotTreatedAsPermissionError() {
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.failedToStartAudioCapture.rawValue
        )

        XCTAssertFalse(SystemAudioRecorder.isSystemAudioPermissionError(error))
    }

    private func makeFloatSampleBuffer(samples: [Float]) throws -> CMSampleBuffer {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw SampleBufferError.formatDescription(status)
        }

        let byteCount = samples.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw SampleBufferError.blockBuffer(status)
        }

        status = samples.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return noErr }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard status == noErr else {
            throw SampleBufferError.replaceData(status)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleSize = MemoryLayout<Float>.size
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: samples.count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw SampleBufferError.sampleBuffer(status)
        }

        return sampleBuffer
    }
}

private enum SampleBufferError: Error {
    case formatDescription(OSStatus)
    case blockBuffer(OSStatus)
    case replaceData(OSStatus)
    case sampleBuffer(OSStatus)
}
