import AppKit
import ApplicationServices

extension TabGroupController {
    func observeWindows(in group: TabGroup) {
        for window in group.windows {
            observer.observe(window)
        }
    }

    func handleWindowNotification(id: WindowID, notification: String) {
        guard !isApplyingLayout, let group = group(containing: id) else { return }

        switch notification {
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            remove(id, from: group, keepWindowObserved: false)

        case kAXMovedNotification, kAXResizedNotification:
            guard group.activeWindow?.id == id,
                  id != draggedWindow?.id,
                  isGroupOnActiveSpace(group),
                  let frame = engine.frame(of: group.windows[group.activeIndex]) else {
                return
            }
            group.contentFrame = frame
            positionPanel(for: group)
            beginTrackingActiveMove(for: group)

        default:
            break
        }
    }

    func beginTrackingActiveMove(for group: TabGroup) {
        activeMoveGroup = group
        activeMoveDeadline = Date().addingTimeInterval(0.2)
        guard activeMoveTimer == nil else { return }
        activeMoveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickActiveMove() }
        }
    }

    func tickActiveMove() {
        guard let group = activeMoveGroup, let active = group.activeWindow,
              active.id != draggedWindow?.id, Date() <= activeMoveDeadline,
              let frame = engine.windowServerFrame(of: active.id) ?? engine.frame(of: active) else {
            endTrackingActiveMove()
            return
        }
        group.contentFrame = frame
        positionPanel(for: group)
    }

    func endTrackingActiveMove() {
        activeMoveTimer?.invalidate()
        activeMoveTimer = nil
        activeMoveGroup = nil
    }
}
