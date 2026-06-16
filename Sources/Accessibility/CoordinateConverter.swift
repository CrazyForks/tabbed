import AppKit
import CoreGraphics

/// Converts between Core Graphics top-left coordinates and AppKit y-up screen coordinates.
enum CoordinateConverter {
    static func appKitFrame(fromCG frame: CGRect, screenHeight: CGFloat = defaultScreenHeight) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenHeight - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    static func cgFrame(fromAppKit frame: CGRect, screenHeight: CGFloat = defaultScreenHeight) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenHeight - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    static func appKitPoint(fromCG point: CGPoint, screenHeight: CGFloat = defaultScreenHeight) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    private static var defaultScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }
}
