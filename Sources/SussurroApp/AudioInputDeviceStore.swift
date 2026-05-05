import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

@MainActor
final class AudioInputDeviceStore: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        do {
            devices = try Self.availableInputDevices()
            errorMessage = nil
        } catch {
            devices = []
            errorMessage = error.localizedDescription
        }
    }

    func isMissingSelectedDevice(uid: String) -> Bool {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUID.isEmpty else { return false }
        return !devices.contains { $0.uid == trimmedUID }
    }

    static func inputDeviceID(forUID uid: String) throws -> AudioDeviceID? {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUID.isEmpty else { return nil }
        return try availableInputDevices().first { $0.uid == trimmedUID }?.id
    }

    static func defaultInputDeviceID() throws -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw AudioInputDeviceError.coreAudioFailure(operation: "read the default input device", status: status)
        }

        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    private static func availableInputDevices() throws -> [AudioInputDevice] {
        try allDeviceIDs()
            .filter(hasInputStreams)
            .compactMap { deviceID in
                guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID),
                      !uid.isEmpty else {
                    return nil
                }

                let name = stringProperty(kAudioDevicePropertyDeviceNameCFString, for: deviceID) ?? "Input \(deviceID)"
                return AudioInputDevice(id: deviceID, uid: uid, name: name)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw AudioInputDeviceError.coreAudioFailure(operation: "list audio devices", status: status)
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return -1 }

            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        guard status == noErr else {
            throw AudioInputDeviceError.coreAudioFailure(operation: "read audio devices", status: status)
        }

        return deviceIDs
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let valuePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        valuePointer.initialize(to: nil)
        defer {
            valuePointer.deinitialize(count: 1)
            valuePointer.deallocate()
        }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, UnsafeMutableRawPointer(valuePointer))
        guard status == noErr, let value = valuePointer.pointee else { return nil }
        return value as String
    }
}

enum AudioInputDeviceError: LocalizedError {
    case coreAudioFailure(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .coreAudioFailure(operation, status):
            return "Could not \(operation) (Core Audio status \(status))."
        }
    }
}
