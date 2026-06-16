import AppKit

/// A stable OS-level window identifier (the CoreGraphics window number).
typealias WindowID = CGWindowID

/// Lightweight, value-type description of one tab, consumed by the UI layer.
/// The backend produces these from `ManagedWindow`s; the UI never touches AX.
struct TabDescriptor: Identifiable, Equatable {
    let id: WindowID
    var title: String
    var appName: String
    var appBundleID: String?
    var pid: pid_t

    /// Resolved lazily by the UI from `pid` / `appBundleID`.
    func appIcon() -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.icon
        }
        if let bid = appBundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
