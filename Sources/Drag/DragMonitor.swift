import AppKit
import CoreGraphics

/// Reports a "Command + drag a window" gesture to its delegate.
@MainActor
protocol DragMonitorDelegate: AnyObject {
    /// The user pressed the left button with Command held over `window`
    /// (nil if there is no manageable window there — the gesture is then ignored).
    func dragDidBegin(window: ManagedWindow?, at point: CGPoint)
    /// Cursor moved while the gesture is active. `point` is screen coords.
    func dragDidMove(to point: CGPoint)
    /// Button released while the gesture is active.
    func dragDidEnd(at point: CGPoint)
    /// Command released (or otherwise aborted) before the button came up.
    func dragDidCancel()
}

/// Detects the global Command-drag gesture and consumes mouse events only after
/// the movement threshold is crossed.
@MainActor
final class DragMonitor {
    weak var delegate: DragMonitorDelegate?
    private let engine: WindowEngine
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTakingOverDrag = false
    private var isMouseDown = false
    /// True between Command mouse-down and either takeover or cancellation.
    private var pendingGesture = false
    private var downPoint: CGPoint = .zero
    /// Movement required before a Command-drag takes over the mouse.
    private static let dragThreshold: CGFloat = 6

    init(engine: WindowEngine) {
        self.engine = engine
    }

    /// Install the event tap.
    func start() {
        guard eventTap == nil else { return }

        let mask = Self.mask(for: [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .flagsChanged
        ])

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[DragMonitor] failed to create CGEventTap")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTakingOverDrag = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isTakingOverDrag {
                isTakingOverDrag = false
                isMouseDown = false
                delegate?.dragDidCancel()
            }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return event
        }

        let point = appKitPoint(fromCGEvent: event)
        let commandIsDown = event.flags.contains(.maskCommand)

        switch type {
        case .leftMouseDown:
            isMouseDown = true
            downPoint = point
            pendingGesture = commandIsDown
            return event

        case .leftMouseDragged:
            if isTakingOverDrag {
                delegate?.dragDidMove(to: point)
                return nil
            }
            if pendingGesture, commandIsDown,
               hypot(point.x - downPoint.x, point.y - downPoint.y) > Self.dragThreshold {
                pendingGesture = false
                if beginTakeover(at: downPoint) {
                    delegate?.dragDidMove(to: point)
                    return nil
                }
            }
            return event

        case .leftMouseUp:
            isMouseDown = false
            pendingGesture = false
            if isTakingOverDrag {
                isTakingOverDrag = false
                delegate?.dragDidEnd(at: point)
                return nil
            }
            return event

        case .flagsChanged:
            if isTakingOverDrag, !commandIsDown {
                isTakingOverDrag = false
                delegate?.dragDidCancel()
            } else if !isTakingOverDrag, commandIsDown, isMouseDown {
                if beginTakeover(at: point) {
                    pendingGesture = false
                    delegate?.dragDidMove(to: point)
                }
            } else if pendingGesture, !commandIsDown {
                pendingGesture = false
            }
            return event

        default:
            return isTakingOverDrag ? nil : event
        }
    }

    /// Start a takeover at `point` if there is a window there. Returns whether
    /// it actually started.
    private func beginTakeover(at point: CGPoint) -> Bool {
        let window = engine.window(at: point, excluding: [])
        delegate?.dragDidBegin(window: window, at: point)
        guard window != nil else { return false }
        isTakingOverDrag = true
        return true
    }

    private func appKitPoint(fromCGEvent event: CGEvent) -> CGPoint {
        let point = event.location
        let height = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    private static func mask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }

        return MainActor.assumeIsolated {
            let monitor = Unmanaged<DragMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            guard let result = monitor.handle(type: type, event: event) else { return nil }
            return Unmanaged.passUnretained(result)
        }
    }
}
