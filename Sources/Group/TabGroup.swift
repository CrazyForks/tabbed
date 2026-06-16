import AppKit

/// One tab group: a set of real windows that share a single on-screen frame,
/// with a floating tab strip on top. Only the active window is raised; the rest
/// sit behind it at the same frame (fully occluded), so switching tabs is just
/// "raise the chosen window".
@MainActor
final class TabGroup {
    let id = UUID()
    let viewModel = TabGroupViewModel()
    let panel: TabBarPanel

    /// Member windows, in tab order.
    var windows: [ManagedWindow]
    var activeIndex: Int

    /// Content frame shared by every member window (AppKit, bottom-left origin).
    /// This is the frame of the window that was dropped *onto* — preserved.
    var contentFrame: CGRect

    /// The Space this group lives on (native macOS Space id).
    var spaceID: UInt64?

    /// Content frame captured at the start of a strip-drag, so cumulative
    /// gesture translation can be applied as an absolute offset.
    var moveAnchorFrame: CGRect?

    init(windows: [ManagedWindow], activeIndex: Int, contentFrame: CGRect, spaceID: UInt64?) {
        self.windows = windows
        self.activeIndex = activeIndex
        self.contentFrame = contentFrame
        self.spaceID = spaceID
        self.panel = TabBarPanel(model: viewModel)
        syncViewModel()
    }

    var activeWindow: ManagedWindow? {
        windows.indices.contains(activeIndex) ? windows[activeIndex] : nil
    }

    func contains(_ id: WindowID) -> Bool {
        windows.contains { $0.id == id }
    }

    /// True if there is enough vertical space above the window's top edge to fit
    /// the full strip without covering anything (the window isn't against the top
    /// of the screen / menu bar).
    var hasRoomAbove: Bool {
        let screen = NSScreen.screens.first { $0.frame.intersects(contentFrame) } ?? NSScreen.main
        let ceiling = screen?.visibleFrame.maxY ?? contentFrame.maxY
        return contentFrame.maxY + Theme.stripHeight <= ceiling
    }

    /// Whether the strip should use the compact corner pill rather than the full
    /// bar — because there's no room above, the user forced it via the setting,
    /// or the debug env override is set. Single source of truth so the resting
    /// frame (`stripFrame`) and panel positioning always agree.
    var useCompact: Bool {
        !hasRoomAbove
            || AppSettings.alwaysUseCompactMode
            || ProcessInfo.processInfo.environment["TABBED_FORCE_COMPACT"] != nil
    }

    /// Full-width strip sitting *just above* the window's top edge (the normal,
    /// roomy layout). Never covers the window's own title bar.
    var stripFrameAbove: CGRect {
        CGRect(x: contentFrame.minX, y: contentFrame.maxY,
               width: contentFrame.width, height: Theme.stripHeight)
    }

    /// Compact pill resting frame: a small icon-only pill hugging the
    /// top-right corner of the window, inset by a ~6pt margin.
    var compactPillFrame: CGRect {
        let height = Theme.stripHeight
        let inset = Theme.compactInset
        let count = CGFloat(max(windows.count, 1))
        let width = min(count * Theme.compactIconSlot + Theme.compactPillPadding * 2,
                        contentFrame.width - inset * 2)
        let x = contentFrame.maxX - width - inset
        let y = contentFrame.maxY - height - inset
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Expanded frame for the compact pill on hover: a near-full-width bar
    /// overlapping the window's top edge. Inset by `compactInset` on the sides and
    /// top so it lines up exactly with the resting pill (same top-right corner)
    /// instead of sitting flush against the window edges.
    var compactExpandedFrame: CGRect {
        let inset = Theme.compactInset
        return CGRect(x: contentFrame.minX + inset,
                      y: contentFrame.maxY - Theme.stripHeight - inset,
                      width: contentFrame.width - inset * 2,
                      height: Theme.stripHeight)
    }

    /// Panel frame for the resting compact pill, grown by `compactInset` on every
    /// side so the panel also covers the inset gap where the frosted matte halo is
    /// drawn. Top/right reach the window edge; left/bottom get a soft halo. The
    /// pill itself is re-inset back to `compactPillFrame` inside the panel.
    var compactPillMatteFrame: CGRect {
        compactPillFrame.insetBy(dx: -Theme.compactInset, dy: -Theme.compactInset)
    }

    /// Panel frame for the expanded compact bar, grown by `compactInset` on every
    /// side for the matte halo. Top/left/right land exactly on the window edges;
    /// the bottom gets a one-inset halo (the window edge below is much farther, so
    /// the matte deliberately does not extend all the way down).
    var compactExpandedMatteFrame: CGRect {
        compactExpandedFrame.insetBy(dx: -Theme.compactInset, dy: -Theme.compactInset)
    }

    /// Resting frame the tab strip's panel should occupy: the full bar above the
    /// window when there's room, otherwise the compact top-right pill (matte-grown).
    var stripFrame: CGRect {
        useCompact ? compactPillMatteFrame : stripFrameAbove
    }

    /// Push current model state into the observable view model for the UI.
    func syncViewModel() {
        viewModel.tabs = windows.map(\.descriptor)
        viewModel.activeID = activeWindow?.id
    }
}
