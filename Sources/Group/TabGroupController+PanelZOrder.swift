import AppKit

extension TabGroupController {
    func frontmostGroup() -> TabGroup? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard pid != ownPID,
              let focusedID = engine.focusedOrMainWindowID(for: pid) else {
            return nil
        }
        return groups.first { group in
            guard let active = group.activeWindow else { return false }
            return active.pid == pid && active.id == focusedID
        }
    }

    func syncPanelZOrderWithFrontmostGroupSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.syncPanelZOrderWithFrontmostGroup()
        }
    }

    func syncPanelZOrderWithFrontmostGroup() {
        let frontmost = frontmostGroup()

        if let frontmost, isGroupOnActiveSpace(frontmost) {
            markRecentlyUsed(frontmost)
            positionPanel(for: frontmost)
        }

        for group in groups where group !== frontmost {
            reassertPanelZOrder(for: group)
        }
    }

    func reassertPanelZOrder(for group: TabGroup) {
        guard isGroupOnActiveSpace(group) else { return }

        let frontmostWindowID = engine.frontmostWindowID()
        if let active = group.activeWindow,
           frontmostGroup() === group || frontmostWindowID == active.id {
            group.panel.order(.above, relativeTo: Int(active.id))
            return
        }

        if let frontmostWindowID {
            group.panel.order(.below, relativeTo: Int(frontmostWindowID))
        } else {
            group.panel.orderOut(nil)
        }
    }

    func markRecentlyUsed(_ group: TabGroup) {
        mostRecentGroup = group
    }
}
