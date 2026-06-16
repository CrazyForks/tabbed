import AppKit
import Combine

/// Observable state for a single tab group's strip UI.
///
/// This is the **contract between the backend and the UI**:
///   - The backend (`TabGroupController`) owns the real windows and pushes
///     state in by mutating `tabs` / `activeID`.
///   - The UI (`TabStripView`) renders from those published values and calls
///     `select(_:)` / `close(_:)` to ask the backend to act.
@MainActor
final class TabGroupViewModel: ObservableObject, Identifiable {
    let id = UUID()

    @Published var tabs: [TabDescriptor] = []
    @Published var activeID: WindowID?

    /// True when the strip is in compact "pill" mode (no room above the window).
    @Published var compact = false
    /// True while the mouse is over the (compact) panel; drives the pill ↔ full
    /// bar expansion. Set from the panel's AppKit tracking area.
    @Published var hovered = false

    // Wired up by the backend when it creates the group.
    var onSelect: ((WindowID) -> Void)?
    var onClose: ((WindowID) -> Void)?

    // Dragging the strip moves the whole group. Translation is cumulative since
    // the gesture began, in AppKit screen-space points (y-up).
    var onMoveBegan: (() -> Void)?
    var onMoveChanged: ((CGSize) -> Void)?
    var onMoveEnded: (() -> Void)?

    /// Clicking the blank area of the strip focuses the group's active window.
    var onActivateActive: (() -> Void)?

    func select(_ id: WindowID) { onSelect?(id) }
    func close(_ id: WindowID) { onClose?(id) }
    func activateActive() { onActivateActive?() }

    func moveBegan() { onMoveBegan?() }
    func moveChanged(_ translation: CGSize) { onMoveChanged?(translation) }
    func moveEnded() { onMoveEnded?() }
}
