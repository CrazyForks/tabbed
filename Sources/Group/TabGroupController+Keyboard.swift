import AppKit

extension TabGroupController: KeyboardShortcutMonitorDelegate {
    /// Activate the tab at `index` in the group the user is currently focused on.
    func keyboardShortcutSelectTab(at index: Int) -> Bool {
        guard let group = focusedGroup(),
              group.windows.indices.contains(index) else {
            return false
        }
        // Already active — still consume so the keystroke doesn't reach the app.
        if index != group.activeIndex {
            selectTab(group.windows[index].id, in: group)
        }
        return true
    }

    /// Step to the adjacent tab, wrapping around the ends.
    func keyboardShortcutCycleTab(forward: Bool) -> Bool {
        guard let group = focusedGroup(), group.windows.count > 1 else {
            return false
        }
        let count = group.windows.count
        let next = forward
            ? (group.activeIndex + 1) % count
            : (group.activeIndex - 1 + count) % count
        selectTab(group.windows[next].id, in: group)
        return true
    }

    /// The on-screen group whose active window currently holds focus.
    private func focusedGroup() -> TabGroup? {
        guard let group = frontmostGroup(), isGroupOnActiveSpace(group) else {
            return nil
        }
        return group
    }
}
