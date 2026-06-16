import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var autoAddMenuItem: NSMenuItem?
    private var compactModeMenuItem: NSMenuItem?
    private let engine = AXWindowEngine()
    private lazy var controller = TabGroupController(engine: engine)

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        setUpStatusItem()

        let trusted = ensureAccessibilityPermission()
        NSLog("[Tabbed] accessibility trusted = \(trusted)")
        guard trusted else {
            // Keep the menu item available while the user grants access.
            statusItem?.button?.appearsDisabled = true
            return
        }
        controller.start()
        NSLog("[Tabbed] controller started — global ⌘-drag monitor active")
    }

    // MARK: - Status bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled",
                                     accessibilityDescription: "Tabbed")
        let menu = NSMenu()
        menu.addItem(withTitle: "Tabbed", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let autoAddItem = menu.addItem(
            withTitle: "Auto-add New Windows to Stack",
            action: #selector(toggleAutoAddNewWindowsToStack),
            keyEquivalent: ""
        )
        autoAddItem.target = self
        autoAddItem.state = AppSettings.autoAddNewWindowsToStack ? .on : .off
        autoAddMenuItem = autoAddItem

        let compactItem = menu.addItem(
            withTitle: "Always Use Compact Mode",
            action: #selector(toggleAlwaysUseCompactMode),
            keyEquivalent: ""
        )
        compactItem.target = self
        compactItem.state = AppSettings.alwaysUseCompactMode ? .on : .off
        compactModeMenuItem = compactItem

        menu.addItem(withTitle: "Open Accessibility Settings…",
                     action: #selector(openAXSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tabbed",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleAutoAddNewWindowsToStack() {
        let enabled = !controller.autoAddNewWindowsToStack
        controller.setAutoAddNewWindowsToStack(enabled)
        autoAddMenuItem?.state = enabled ? .on : .off
    }

    @objc private func toggleAlwaysUseCompactMode() {
        let enabled = !controller.alwaysUseCompactMode
        controller.setAlwaysUseCompactMode(enabled)
        compactModeMenuItem?.state = enabled ? .on : .off
    }

    @objc private func openAXSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Permissions

    private func ensureAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
