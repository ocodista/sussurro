import AppKit
import SwiftUI

@MainActor
final class FloatingRecorderWindowController: NSWindowController {
    init(settings: AppSettings) {
        let recorder = AudioRecorder(settings: settings)
        let transcriber = WhisperTranscriber(settings: settings)
        let contentView = RecorderView(recorder: recorder, transcriber: transcriber, settings: settings)

        let panel = FloatingRecorderPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "Sussurro"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentMinSize = NSSize(width: 640, height: 620)
        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()

        super.init(window: panel)
    }

    func show() {
        if window?.isVisible == false {
            window?.center()
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FloatingRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
