import AppKit
import SwiftUI

@MainActor
final class FloatingRecorderWindowController: NSWindowController {
    init(settings: AppSettings) {
        let recorder = AudioRecorder(settings: settings)
        let transcriber = WhisperTranscriber(settings: settings)
        let contentView = RecorderView(recorder: recorder, transcriber: transcriber, settings: settings)

        let panel = FloatingRecorderPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "Sussurro"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.minSize = NSSize(width: 600, height: 560)
        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()

        super.init(window: panel)
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
