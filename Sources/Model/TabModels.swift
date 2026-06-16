import AppKit

typealias WindowID = CGWindowID

struct TabDescriptor: Identifiable, Equatable {
    let id: WindowID
    var title: String
    var appName: String
    var appBundleID: String?
    var pid: pid_t

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
