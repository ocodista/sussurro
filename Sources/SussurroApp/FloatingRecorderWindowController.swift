import AppKit
import SwiftUI

@MainActor
final class FloatingRecorderWindowController: NSWindowController {
    init(settings: AppSettings) {
        let recorder = AudioRecorder(settings: settings)
        let transcriber = WhisperTranscriber(settings: settings)
        let panel = FloatingRecorderPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let contentView = RecorderView(
            recorder: recorder,
            transcriber: transcriber,
            settings: settings,
            applyWindowPresentation: { [weak panel] presentation in
                panel?.applyPresentation(presentation)
            },
            minimizeWindow: { [weak panel] in panel?.miniaturize(nil) }
        )

        panel.title = "Sussurro"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentMinSize = RecorderWindowPresentation.expanded.contentSize
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

    @MainActor
    func applyPresentation(_ presentation: RecorderWindowPresentation) {
        let contentSize = presentation.contentSize
        contentMinSize = contentSize

        let currentContentRect = contentRect(forFrameRect: frame)
        guard abs(currentContentRect.width - contentSize.width) > 1
            || abs(currentContentRect.height - contentSize.height) > 1
        else {
            return
        }

        let nextContentRect = NSRect(
            x: currentContentRect.midX - contentSize.width / 2,
            y: currentContentRect.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        let nextFrame = frameRect(forContentRect: nextContentRect)
        setFrame(nextFrame, display: true, animate: true)
    }
}
