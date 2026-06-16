import AppKit
import ApplicationServices

/// Accessibility-backed implementation of `WindowEngine`.
@MainActor
final class AXWindowEngine: WindowEngine {
    private let spaces = SpacesService()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func window(at point: CGPoint, excluding: Set<WindowID>) -> ManagedWindow? {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(0)
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfos {
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            let windowID = WindowID(number.uint32Value)
            let pid = pid_t(ownerPID.int32Value)
            if pid == ownPID || excluding.contains(windowID) || layer.intValue != 0 {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 {
                continue
            }

            guard let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  cgToAppKit(cgBounds).contains(point),
                  let managed = managedWindow(id: windowID, pid: pid, ownerInfo: info) else {
                continue
            }

            return managed
        }

        return nil
    }

    func onScreenWindowFrames(excluding: Set<WindowID>) -> [WindowFrame] {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(0)
        ) as? [[String: Any]] else {
            return []
        }

        var result: [WindowFrame] = []
        for info in windowInfos {
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            let windowID = WindowID(number.uint32Value)
            let pid = pid_t(ownerPID.int32Value)
            if pid == ownPID || excluding.contains(windowID) || layer.intValue != 0 {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 {
                continue
            }
            guard let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            let frame = cgToAppKit(cgBounds)
            // Skip tiny utility/overlay windows that aren't meaningful drop targets.
            if frame.width < 80 || frame.height < 80 { continue }
            result.append(WindowFrame(id: windowID, pid: pid, frame: frame))
        }
        return result
    }

    func managedWindow(from element: AXUIElement, pid: pid_t) -> ManagedWindow? {
        guard pid != ownPID, isStandardWindow(element) else { return nil }

        var resolved = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &resolved) == .success,
              resolved != 0 else {
            return nil
        }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let title = copyStringAttribute(kAXTitleAttribute, from: element) ?? "Untitled"
        return ManagedWindow(
            id: resolved,
            pid: pid,
            element: element,
            title: title.isEmpty ? "Untitled" : title,
            appName: runningApp?.localizedName ?? "Unknown",
            appBundleID: runningApp?.bundleIdentifier
        )
    }

    func frame(of window: ManagedWindow) -> CGRect? {
        guard let position = copyCGPointAttribute(kAXPositionAttribute, from: window.element),
              let size = copyCGSizeAttribute(kAXSizeAttribute, from: window.element) else {
            return nil
        }

        return cgToAppKit(CGRect(origin: position, size: size))
    }

    func windowServerFrame(of id: WindowID) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = infos.first,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return nil
        }
        return cgToAppKit(cg)
    }

    func setFrame(_ frame: CGRect, of window: ManagedWindow) {
        let cgFrame = appKitToCG(frame)
        setCGSizeAttribute(kAXSizeAttribute, value: cgFrame.size, on: window.element)
        setCGPointAttribute(kAXPositionAttribute, value: cgFrame.origin, on: window.element)
    }

    func raise(_ window: ManagedWindow) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    func activate(_ window: ManagedWindow) {
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window.element)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        raise(window)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    }

    func isAlive(_ window: ManagedWindow) -> Bool {
        guard NSRunningApplication(processIdentifier: window.pid) != nil else { return false }
        var resolved = CGWindowID(0)
        return _AXUIElementGetWindow(window.element, &resolved) == .success && resolved == window.id
    }

    func refreshTitle(_ window: ManagedWindow) -> String {
        if let title = copyStringAttribute(kAXTitleAttribute, from: window.element), !title.isEmpty {
            window.title = title
        }
        return window.title
    }

    func spaceID(of window: ManagedWindow) -> UInt64? {
        return spaces.spaceID(forWindow: window.id)
    }

    func activeSpaceID(forScreenOf window: ManagedWindow) -> UInt64? {
        return spaces.activeSpaceID()
    }

    func move(_ window: ManagedWindow, toSpaceOf reference: ManagedWindow) {
        spaces.move(window: window.id, toSpaceOf: reference.id)
    }

    private func managedWindow(id: WindowID, pid: pid_t, ownerInfo: [String: Any]) -> ManagedWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else {
            return nil
        }

        for element in elements {
            var resolved = CGWindowID(0)
            guard _AXUIElementGetWindow(element, &resolved) == .success, resolved == id else {
                continue
            }
            guard isStandardWindow(element) else { return nil }

            let runningApp = NSRunningApplication(processIdentifier: pid)
            let title = copyStringAttribute(kAXTitleAttribute, from: element)
                ?? (ownerInfo[kCGWindowName as String] as? String)
                ?? "Untitled"
            let appName = runningApp?.localizedName
                ?? (ownerInfo[kCGWindowOwnerName as String] as? String)
                ?? "Unknown"

            return ManagedWindow(
                id: id,
                pid: pid,
                element: element,
                title: title.isEmpty ? "Untitled" : title,
                appName: appName,
                appBundleID: runningApp?.bundleIdentifier
            )
        }

        return nil
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard copyStringAttribute(kAXRoleAttribute, from: element) == kAXWindowRole else {
            return false
        }
        return copyStringAttribute(kAXSubroleAttribute, from: element) == kAXStandardWindowSubrole
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyCGPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func copyCGSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func setCGPointAttribute(_ attribute: String, value: CGPoint, on element: AXUIElement) {
        var mutableValue = value
        guard let axValue = AXValueCreate(.cgPoint, &mutableValue) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

    private func setCGSizeAttribute(_ attribute: String, value: CGSize, on element: AXUIElement) {
        var mutableValue = value
        guard let axValue = AXValueCreate(.cgSize, &mutableValue) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

    private func cgToAppKit(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenHeight - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private func appKitToCG(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenHeight - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private var screenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }
}
