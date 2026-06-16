# Tabbed

A tiny macOS menu-bar utility with exactly **one** feature:

> Hold **⌘ Command** and drag any window on top of another window to merge them
> into a **tabbed group**. The window you drop *onto* keeps its size; the dragged
> window is resized to match. A floating tab strip lets you switch between them.

It is **not** a window manager. It does not tile, it has no workspaces, and it
leaves every other window alone. It works with **native macOS Spaces** (Mission
Control) — not virtual/AeroSpace-style workspaces.

## How it works

A "tab group" is an illusion built from real OS windows:

- All windows in a group share one on-screen frame (the drop target's frame).
- Only the active window is raised; the others sit behind it, fully occluded.
- A borderless floating panel draws the tab strip over the top edge of the frame.
- Switching a tab just raises the chosen window.

Window manipulation uses the Accessibility API; Space awareness uses the private
CGS Spaces API. The app must run un-sandboxed and needs Accessibility permission.

## Build

```sh
xcodegen generate
open Tabbed.xcodeproj      # or: xcodebuild -scheme Tabbed build
```

On first launch, grant **System Settings → Privacy & Security → Accessibility**.

## Install

```sh
brew tap ZimengXiong/tools
brew install --cask tabbed
```

## Layout

| Path | Owner | What |
|------|-------|------|
| `Sources/App` | UI | Menu-bar entry point, permission gate |
| `Sources/UI` | UI | Tab strip, tab item, drop indicator, hosting panels |
| `Sources/Model` | shared | `TabDescriptor`, ids |
| `Sources/Group` | shared/backend | `TabGroup`, `TabGroupViewModel`, `TabGroupController` |
| `Sources/Accessibility` | backend | AX window engine, Spaces service, bridging header |
| `Sources/Drag` | backend | Global ⌘-drag event tap |

See `ARCHITECTURE.md` for the backend contract and coordinate conventions.
