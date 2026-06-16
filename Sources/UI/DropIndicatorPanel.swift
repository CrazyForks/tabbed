import AppKit
import SwiftUI

/// Extra room around the target so the soft border glow isn't clipped by the
/// panel's bounds.
private let dropGlowInset: CGFloat = 16
private let dropCornerRadius: CGFloat = 11

/// A click-through overlay drawn over a candidate target window while the user
/// Command-drags another window over it. Communicates "release to tab here"
/// with a subtle highlighted region rather than a heavy label.
final class DropIndicatorPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true            // never intercept the drag
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: DropIndicatorView())
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show the indicator over `frame` (screen, bottom-left origin).
    func present(over frame: CGRect) {
        // Inflate so the glow around the border has room and isn't clipped.
        setFrame(frame.insetBy(dx: -dropGlowInset, dy: -dropGlowInset), display: true)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}

private struct DropIndicatorView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: dropCornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: dropCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
            )
            .shadow(color: Color.accentColor.opacity(0.40), radius: 10)
            .padding(dropGlowInset)
    }
}
