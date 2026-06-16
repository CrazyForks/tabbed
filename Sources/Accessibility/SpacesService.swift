import AppKit

/// Native macOS Spaces support, backed by private CGS APIs.
@MainActor
final class SpacesService {
    private let allSpacesMask: Int32 = 0x7

    func spaceID(forWindow window: WindowID) -> UInt64? {
        let connection = _CGSDefaultConnection()
        let windows = [NSNumber(value: window)] as CFArray
        guard let spaces = copyArray(CGSCopySpacesForWindows(connection, allSpacesMask, windows)) else {
            return nil
        }

        return spaces.compactMap(spaceID(from:)).first
    }

    func activeSpaceID() -> UInt64? {
        let connection = _CGSDefaultConnection()

        if let displayID = mainDisplayIdentifier() {
            let active = CGSManagedDisplayGetCurrentSpace(connection, displayID as CFString)
            if active != 0 {
                return active
            }
        }

        guard let displays = copyArray(CGSCopyManagedDisplaySpaces(connection)) else {
            return nil
        }

        if let displayID = mainDisplayIdentifier() {
            for display in displays {
                guard let dict = display as? [String: Any],
                      dict["Display Identifier"] as? String == displayID,
                      let current = dict["Current Space"] else {
                    continue
                }
                return spaceID(from: current)
            }
        }

        for display in displays {
            guard let dict = display as? [String: Any],
                  let current = dict["Current Space"],
                  let id = spaceID(from: current) else {
                continue
            }
            return id
        }

        return nil
    }

    func move(window: WindowID, toSpaceOf reference: WindowID) {
        guard let targetSpace = spaceID(forWindow: reference) else { return }
        let connection = _CGSDefaultConnection()
        let windows = [NSNumber(value: window)] as CFArray
        CGSMoveWindowsToManagedSpace(connection, windows, targetSpace)
    }

    private func copyArray(_ unmanaged: Unmanaged<CFArray>?) -> [Any]? {
        unmanaged?.takeRetainedValue() as? [Any]
    }

    private func spaceID(from value: Any) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }

        guard let dict = value as? [String: Any] else { return nil }
        if let number = dict["ManagedSpaceID"] as? NSNumber {
            return number.uint64Value
        }
        if let number = dict["id64"] as? NSNumber {
            return number.uint64Value
        }
        if let number = dict["id"] as? NSNumber {
            return number.uint64Value
        }
        return nil
    }

    private func mainDisplayIdentifier() -> String? {
        let displayID: CGDirectDisplayID
        if let screenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            displayID = CGDirectDisplayID(screenNumber.uint32Value)
        } else {
            displayID = CGMainDisplayID()
        }

        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else {
            return nil
        }

        return string as String
    }
}
