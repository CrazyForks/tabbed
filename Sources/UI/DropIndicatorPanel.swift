import AppKit
import SwiftUI

/// Extra panel padding so the border glow is not clipped.
private let dropGlowInset: CGFloat = 16
private let dropCornerRadius: CGFloat = 11

/// Click-through overlay shown over a drop target.
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
        ignoresMouseEvents = true
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: DropIndicatorView())
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(over frame: CGRect) {
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
