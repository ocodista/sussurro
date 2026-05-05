import AppKit
import SwiftUI

extension View {
    func pointingHandCursor(_ isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering, isEnabled {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
    }
}
