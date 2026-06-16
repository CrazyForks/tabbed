import AppKit
import ApplicationServices

/// A handle to one real OS window owned by some other application.
///
/// Wraps the Accessibility element plus enough identity to look the window up in
/// CoreGraphics / CGS Spaces queries.
@MainActor
final class ManagedWindow {
    let id: WindowID                 // CGWindowID — stable for the window's lifetime
    let pid: pid_t
    let element: AXUIElement         // kAXWindowRole element
    var title: String
    var appName: String
    var appBundleID: String?

    init(id: WindowID, pid: pid_t, element: AXUIElement,
         title: String, appName: String, appBundleID: String?) {
        self.id = id
        self.pid = pid
        self.element = element
        self.title = title
        self.appName = appName
        self.appBundleID = appBundleID
    }

    var descriptor: TabDescriptor {
        TabDescriptor(id: id, title: title, appName: appName,
                      appBundleID: appBundleID, pid: pid)
    }
}

/// Lightweight static snapshot of one on-screen window. Used for cheap drag-time
/// hit-testing (in-memory rect tests) without per-event Accessibility queries.
struct WindowFrame {
    let id: WindowID
    let pid: pid_t
    let frame: CGRect   // AppKit screen coords (bottom-left origin)
}

/// Everything the rest of the app needs from the window system. The real
/// implementation (`AXWindowEngine`) is backed by Accessibility + private CGS
/// Spaces APIs.
@MainActor
protocol WindowEngine: AnyObject {
    /// The frontmost manageable window under `point` (screen coords, top-left
    /// origin as reported by CoreGraphics), skipping any in `excluding` and
    /// skipping our own panels.
    func window(at point: CGPoint, excluding: Set<WindowID>) -> ManagedWindow?

    /// Snapshot of on-screen standard windows (front-to-back) for cheap drag
    /// hit-testing. No Accessibility calls — frames come straight from the
    /// window server, so this is fast enough to call once per drag.
    func onScreenWindowFrames(excluding: Set<WindowID>) -> [WindowFrame]

    /// Resolve a live AX window element into the app's managed window model.
    /// Returns nil for non-standard windows or elements that do not map to a
    /// CoreGraphics window number.
    func managedWindow(from element: AXUIElement, pid: pid_t) -> ManagedWindow?

    /// Current frame in screen coords (bottom-left origin, AppKit convention).
    func frame(of window: ManagedWindow) -> CGRect?

    /// Live frame straight from the window server (`CGWindowList`) by id. This is
    /// fresher than `frame(of:)` (which uses Accessibility and lags during a live
    /// OS title-bar drag), so it's used to keep the strip glued while the user
    /// drags the window itself.
    func windowServerFrame(of id: WindowID) -> CGRect?

    /// Move/resize the window. `frame` is bottom-left origin (AppKit).
    func setFrame(_ frame: CGRect, of window: ManagedWindow)

    /// Bring the window above its peers without necessarily activating the app.
    func raise(_ window: ManagedWindow)

    /// Activate the owning app and focus the window (used on tab selection).
    func activate(_ window: ManagedWindow)

    func isAlive(_ window: ManagedWindow) -> Bool

    /// Refresh `title` from AX and return it.
    func refreshTitle(_ window: ManagedWindow) -> String

    // MARK: Spaces (native macOS Spaces — see SpacesService)

    /// The Space ID the window currently lives on, if resolvable.
    func spaceID(of window: ManagedWindow) -> UInt64?

    /// The Space ID currently visible on the window's display.
    func activeSpaceID(forScreenOf window: ManagedWindow) -> UInt64?

    /// Move `window` onto the same Space as `reference` (native Space move).
    /// Used when tabbing a window that lives on a different Space onto a target.
    func move(_ window: ManagedWindow, toSpaceOf reference: ManagedWindow)
}
