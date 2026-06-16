import SwiftUI

/// Visual constants for the floating tab strip. Tuned to read as a thin,
/// glassy chrome bar that sits over the top edge of a window group.
enum Theme {
    /// Height of the floating strip, in points. Compact but roomy enough for
    /// readable capsule tabs (matches the reference Liquid Glass tab bar).
    static let stripHeight: CGFloat = 28
    /// Horizontal/vertical padding inside the strip around the row of tabs.
    static let stripPadding: CGFloat = 2
    static let tabSpacing: CGFloat = 3

    static let tabMinWidth: CGFloat = 120
    static let tabMaxWidth: CGFloat = 280
    static let tabHeight: CGFloat = stripHeight - stripPadding * 2

    // Concentric with the capsule pills: outer radius = pill radius + padding,
    // so the bar's curve mirrors the tabs' (tabHeight/2 + stripPadding).
    static let stripCornerRadius: CGFloat = tabHeight / 2 + stripPadding
    static let tabCornerRadius: CGFloat = 6

    static let iconSize: CGFloat = 14
    static let titleSize: CGFloat = 12

    // Compact "pill" strip shown when there's no room above the window. It hugs
    // the top-right corner and shows app icons only, expanding to the full bar
    // on hover.
    static let compactIconSlot: CGFloat = 22
    static let compactPillPadding: CGFloat = 6
    static let compactIconSize: CGFloat = 16
    /// Margin between the compact pill / expanded bar and the window's edges, so
    /// both float *inside* the window corner instead of sitting flush against it.
    /// This same gap is filled by the frosted matte halo (see below).
    static let compactInset: CGFloat = 6

    /// Frosted "matte" halo drawn in the `compactInset` gap around the compact
    /// bar — a slight blur of the window content behind it that lifts the bar off
    /// busy backgrounds. Concentric with the bar's outer curve.
    static let compactMatteCornerRadius: CGFloat = stripCornerRadius + compactInset
    /// Dark wash layered over the matte's blur to add contrast. Tunable.
    static let compactMatteTint: Double = 0.12

    // Tints used only on the pre-macOS-26 fallback path (no Liquid Glass).
    static let fillActive = 0.16
    static let fillHover = 0.10
    static let fillIdle = 0.0

    static let textActive = 0.95
    static let textHover = 0.80
    static let textIdle = 0.55

    static let strokeActive = 0.22
    static let strokeIdle = 0.08

    /// Color used for the drop indicator drawn over a target window.
    static let dropAccent = Color(red: 0.30, green: 0.60, blue: 1.0)
}
