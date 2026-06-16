import AppKit

struct WindowServerWindow {
    let id: WindowID
    let pid: pid_t
    let layer: Int
    let alpha: Double
    let frame: CGRect
    let ownerInfo: [String: Any]

    var isVisibleStandardLayerWindow: Bool {
        layer == 0 && alpha > 0
    }
}

enum WindowServerSnapshot {
    static func onScreenWindows(
        excludingOwnPID ownPID: pid_t,
        excluding excludedIDs: Set<WindowID> = []
    ) -> [WindowServerWindow] {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(0)
        ) as? [[String: Any]] else {
            return []
        }

        return infos.compactMap { window(from: $0) }.filter { window in
            window.pid != ownPID
                && !excludedIDs.contains(window.id)
                && window.isVisibleStandardLayerWindow
        }
    }

    static func window(id: WindowID) -> WindowServerWindow? {
        guard let infos = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = infos.first else {
            return nil
        }
        return window(from: info)
    }

    static func frontmostVisibleWindow(excludingOwnPID ownPID: pid_t) -> WindowServerWindow? {
        onScreenWindows(excludingOwnPID: ownPID).first
    }

    private static func window(from info: [String: Any]) -> WindowServerWindow? {
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
              let layer = info[kCGWindowLayer as String] as? NSNumber,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        guard let cgFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return nil
        }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
        return WindowServerWindow(
            id: WindowID(number.uint32Value),
            pid: pid_t(ownerPID.int32Value),
            layer: layer.intValue,
            alpha: alpha,
            frame: CoordinateConverter.appKitFrame(fromCG: cgFrame),
            ownerInfo: info
        )
    }
}
