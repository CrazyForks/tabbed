import SwiftUI

enum Theme {
    static let stripHeight: CGFloat = 28
    static let stripPadding: CGFloat = 2
    static let tabSpacing: CGFloat = 3

    static let tabMinWidth: CGFloat = 120
    static let tabMaxWidth: CGFloat = 280
    static let tabHeight: CGFloat = stripHeight - stripPadding * 2

    static let stripCornerRadius: CGFloat = tabHeight / 2 + stripPadding
    static let tabCornerRadius: CGFloat = 6

    static let iconSize: CGFloat = 14
    static let titleSize: CGFloat = 12

    // Compact pill metrics.
    static let compactIconSlot: CGFloat = 22
    static let compactPillPadding: CGFloat = 6
    static let compactIconSize: CGFloat = 16
    static let compactInset: CGFloat = 6

    // Pre-macOS-26 fallback tints.
    static let fillActive = 0.16
    static let fillHover = 0.10
    static let fillIdle = 0.0

    static let textActive = 0.95
    static let textHover = 0.80
    static let textIdle = 0.55

    static let strokeActive = 0.22
    static let strokeIdle = 0.08

    static let dropAccent = Color(red: 0.30, green: 0.60, blue: 1.0)
}
