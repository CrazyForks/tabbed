import Foundation

enum AppSettings {
    private static let autoAddNewWindowsToStackKey = "autoAddNewWindowsToStack"
    private static let alwaysUseCompactModeKey = "alwaysUseCompactMode"

    static var autoAddNewWindowsToStack: Bool {
        get { UserDefaults.standard.bool(forKey: autoAddNewWindowsToStackKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoAddNewWindowsToStackKey) }
    }

    /// Force the compact corner strip even when there is room above.
    static var alwaysUseCompactMode: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysUseCompactModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysUseCompactModeKey) }
    }
}
