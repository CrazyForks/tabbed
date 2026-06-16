import Foundation

enum AppSettings {
    private static let autoAddNewWindowsToStackKey = "autoAddNewWindowsToStack"
    private static let alwaysUseCompactModeKey = "alwaysUseCompactMode"

    static var autoAddNewWindowsToStack: Bool {
        get { UserDefaults.standard.bool(forKey: autoAddNewWindowsToStackKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoAddNewWindowsToStackKey) }
    }

    /// When on, the strip always uses the compact corner pill (expanding on
    /// hover) instead of the full bar, even when there's room above the window.
    static var alwaysUseCompactMode: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysUseCompactModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysUseCompactModeKey) }
    }
}
