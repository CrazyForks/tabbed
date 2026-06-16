import AppKit
import SwiftUI

/// A borderless floating panel that hosts one group's `TabStripView`.
///
/// Space behaviour: the panel deliberately does **not** use
/// `.canJoinAllSpaces`, so once it is ordered onto a Space it stays pinned to
/// that Space. The backend is responsible for ordering it in while the group's
/// Space is active so it lands on the correct one.
final class TabBarPanel: NSPanel {
    let model: TabGroupViewModel

    /// Layout state for the compact pill mode. `resting` is the small top-right
    /// pill; `expanded` is the full bar shown while hovered.
    private var isCompact = false
    private var restingFrame: CGRect = .zero
    private var expandedFrame: CGRect = .zero

    /// How far the cursor may stray beyond the expanded bar before it collapses
    /// back to the pill — a grace margin so a small overshoot doesn't dismiss it.
    private let collapseSafeZone: CGFloat = 20
    /// Polls the cursor after it leaves the bar; fires a collapse only once the
    /// cursor crosses the padded safe-zone boundary.
    private var collapseWatcher: Timer?

    /// Container that owns the AppKit tracking area. SwiftUI `.onHover` does not
    /// fire on a `.nonactivatingPanel` (it never becomes key), so hover must be
    /// detected at the AppKit layer.
    private let trackingContainer: HoverTrackingView

    init(model: TabGroupViewModel) {
        self.model = model
        self.trackingContainer = HoverTrackingView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: Theme.stripHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Keep the compact pill visible while it overlaps the member window.
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: TabStripView(model: model)
            .environment(\.colorScheme, .dark))
        host.translatesAutoresizingMaskIntoConstraints = false
        trackingContainer.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: trackingContainer.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trackingContainer.trailingAnchor),
            host.topAnchor.constraint(equalTo: trackingContainer.topAnchor),
            host.bottomAnchor.constraint(equalTo: trackingContainer.bottomAnchor)
        ])
        contentView = trackingContainer

        trackingContainer.onHoverChange = { [weak self] hovering in
            self?.handleHover(hovering)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Position the strip. `frame` is in screen (bottom-left origin) coordinates.
    func place(at frame: CGRect) {
        setFrame(frame, display: true)
    }

    /// Configure the panel's layout for the current room-above state. In compact
    /// mode the panel rests at the small top-right pill and expands to the full
    /// bar on hover; otherwise it just sits at `resting`.
    /// All frames are AppKit screen coordinates (bottom-left origin).
    func applyLayout(compact: Bool, resting: CGRect, expanded: CGRect) {
        isCompact = compact
        restingFrame = resting
        expandedFrame = expanded
        if !compact { cancelCollapseWatch() }
        let target = (compact && model.hovered) ? expanded : resting
        setFrame(target, display: true)
    }

    /// Hover transitions for compact mode, driven by the AppKit tracking area.
    /// Expanding is immediate; collapsing is deferred until the cursor leaves a
    /// padded safe zone around the bar, so small overshoots don't dismiss it.
    private func handleHover(_ hovering: Bool) {
        guard isCompact else { return }
        if hovering {
            cancelCollapseWatch()
            setExpanded(true)
        } else {
            beginCollapseWatch()
        }
    }

    /// Animate the panel between its pill (resting) and bar (expanded) frames and
    /// update the model so the SwiftUI content cross-fades in step.
    private func setExpanded(_ expanded: Bool) {
        model.hovered = expanded
        let target = expanded ? expandedFrame : restingFrame
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            animator().setFrame(target, display: true)
        }
    }

    /// After the cursor leaves the bar, keep it open while the cursor stays within
    /// `collapseSafeZone` points of the expanded frame; collapse once it crosses.
    private func beginCollapseWatch() {
        cancelCollapseWatch()
        collapseWatcher = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickCollapseWatch() }
        }
    }

    private func tickCollapseWatch() {
        let safe = expandedFrame.insetBy(dx: -collapseSafeZone, dy: -collapseSafeZone)
        if !safe.contains(NSEvent.mouseLocation) {
            cancelCollapseWatch()
            setExpanded(false)
        }
    }

    private func cancelCollapseWatch() {
        collapseWatcher?.invalidate()
        collapseWatcher = nil
    }

    func show() {
        appearance = NSAppearance(named: .darkAqua)
        orderFrontRegardless()
    }

    func hide() {
        cancelCollapseWatch()
        orderOut(nil)
    }
}

/// Content container that reports mouse enter/exit via an AppKit tracking area.
///
/// Required because the host panel is a `.nonactivatingPanel` that never becomes
/// key, so SwiftUI's `.onHover` won't fire. `.activeAlways` keeps tracking even
/// when the app isn't active; `.inVisibleRect` keeps the tracking rect synced to
/// the (resizing) view bounds automatically.
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
