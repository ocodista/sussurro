import Carbon
import Foundation

@MainActor
final class GlobalHotKey {
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerCommandOptionM() throws {
        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else { return noErr }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    hotKey.action()
                }
                return noErr
            },
            1,
            [eventType],
            unmanagedSelf,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.couldNotInstallHandler(status: handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )

        guard hotKeyStatus == noErr else {
            throw HotKeyError.couldNotRegisterShortcut(status: hotKeyStatus)
        }
    }

    private static let signature: OSType = OSType(UInt32(UnicodeScalar("C").value) << 24 | UInt32(UnicodeScalar("S").value) << 16 | UInt32(UnicodeScalar("T").value) << 8 | UInt32(UnicodeScalar("T").value))
}

enum HotKeyError: LocalizedError {
    case couldNotInstallHandler(status: OSStatus)
    case couldNotRegisterShortcut(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .couldNotInstallHandler(status):
            return "Could not install keyboard shortcut handler. OSStatus: \(status)."
        case let .couldNotRegisterShortcut(status):
            return "Could not register ⌘⌥M. Another app may already be using it. OSStatus: \(status)."
        }
    }
}
