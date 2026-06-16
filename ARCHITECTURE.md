# Architecture & backend contract

The app is split so the **UI** and the **window-system backend** can be built
independently against fixed interfaces.

## Coordinate convention (READ THIS FIRST)

Everywhere in Swift the app speaks **AppKit screen coordinates: bottom-left
origin, y-up**. `WindowEngine.frame`/`setFrame`, `TabGroup.contentFrame`,
`TabGroup.stripFrame`, and every `CGRect` passed to a panel are bottom-left.

The two places that produce **top-left, y-down** coordinates must convert at the
boundary and never leak that convention upward:

- Accessibility `kAXPosition` (top-left) → convert in `AXWindowEngine`.
- `CGEvent` mouse locations (top-left) → convert in `DragMonitor`.
- `CGWindowListCopyWindowInfo` bounds (top-left) → convert where read.

Convert with the primary screen height: `y_appkit = NSScreen.screens[0].frame.height - y_cg - height`
(use the standard full-display flip; account for multi-monitor by using the
union/zero-screen height consistently).

## The contract

### UI → backend
- `TabDescriptor` (`Sources/Model`) — value type the strip renders.
- `TabGroupViewModel` (`Sources/Group`) — published tab state plus callbacks.
- `TabBarPanel`, `DropIndicatorPanel`, `TabStripView`, `TabItemView`, `Theme`
  (`Sources/UI`) — the backend instantiates and positions panels.

### Backend surface
- `WindowEngine` protocol + `AXWindowEngine` (`Sources/Accessibility`).
- `SpacesService` + `Tabbed-Bridging-Header.h` (`Sources/Accessibility`).
- `DragMonitor` + `DragMonitorDelegate` (`Sources/Drag`).
- `TabGroupController` orchestration (`Sources/Group`).

## Behavior spec

1. **Gesture.** While ⌘ is held, pressing the left button over a standard window
   starts a takeover: the dragged window follows the cursor, and mouse events are
   *consumed* so the underlying app doesn't react. Releasing the button drops it.
   Releasing ⌘ first cancels.

2. **Drop = tab.** On drop over another standard window (the *target*):
   - The group adopts the **target window's current frame** (its size is
     preserved exactly).
   - The dragged window is **resized/moved to that same frame**.
   - If the target is already in a group, the dragged window is appended.
   - The dropped (dragged) window becomes the **active** tab.

3. **Group rendering.** Every member window occupies `contentFrame`. The active
   window is raised; others sit behind it. The `TabBarPanel` is placed at
   `stripFrame` (top edge of `contentFrame`) and ordered front.

4. **Tab switch.** `onSelect` → activate that window (raise + focus app), keep the
   strip on top.

5. **Untab / close.** `onClose` → remove the window from the group (it becomes a
   free window again — do **not** destroy the user's window). If ≤1 window
   remains, dissolve the group and hide its strip.

6. **Live sync.** Observe each member via AX (`kAXMoved`, `kAXResized`,
   `kAXUIElementDestroyed`, `kAXWindowMiniaturized`):
   - Active window moved/resized → update `contentFrame`, reposition the strip and
     the other members to match.
   - Destroyed/closed → remove from group (rule 5).

7. **Native Spaces.** Use real macOS Spaces via CGS:
   - A group lives on one Space. Its `TabBarPanel` must be **pinned** to that Space
     (order it in while that Space is active; the panel deliberately avoids
     `.canJoinAllSpaces`).
   - Never raise/reposition a group's windows while its Space is not the active
     one. Re-evaluate on `NSWorkspace.activeSpaceDidChangeNotification`.
   - If a window is dropped onto a target on a **different Space**, move the
     dragged window to the target's Space (`CGSMoveWindowsToManagedSpace`) before
     applying the layout.

## Acceptance
- `xcodegen generate && xcodebuild -scheme Tabbed build` succeeds.
- ⌘-drag one window onto another → they become a tab group sized to the target.
- Clicking tabs switches windows; the strip tracks the active window when moved.
- Switching macOS Spaces hides/shows the right strips and never yanks windows
  across Spaces.
