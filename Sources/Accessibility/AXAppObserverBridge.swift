import ApplicationServices
import Foundation

@MainActor
final class AXAppObserverBridge {
    var onEvent: ((pid_t, String, AXUIElement) -> Void)?

    private struct Observation {
        let observer: AXObserver
        let source: CFRunLoopSource
        let element: AXUIElement
        var notifications: Set<String>
    }

    private var observations: [pid_t: Observation] = [:]

    func observe(pid: pid_t, notifications: [String]) {
        guard !notifications.isEmpty else { return }

        if var observation = observations[pid] {
            for notification in notifications where !observation.notifications.contains(notification) {
                let error = AXObserverAddNotification(
                    observation.observer,
                    observation.element,
                    notification as CFString,
                    Unmanaged.passUnretained(self).toOpaque()
                )
                if error == .success || error == .notificationAlreadyRegistered {
                    observation.notifications.insert(notification)
                }
            }
            observations[pid] = observation
            return
        }

        var observer: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &observer) == .success,
              let observer else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        var registered: Set<String> = []
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            let error = AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                refcon
            )
            if error == .success || error == .notificationAlreadyRegistered {
                registered.insert(notification)
            }
        }

        guard !registered.isEmpty else { return }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        observations[pid] = Observation(
            observer: observer,
            source: source,
            element: appElement,
            notifications: registered
        )
    }

    func setObservedPIDs(_ pids: Set<pid_t>, notifications: [String]) {
        for pid in Array(observations.keys) where !pids.contains(pid) {
            unobserve(pid)
        }
        for pid in pids {
            observe(pid: pid, notifications: notifications)
        }
    }

    func unobserve(_ pid: pid_t) {
        guard let observation = observations.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), observation.source, .commonModes)
    }

    func unobserveAll() {
        for pid in Array(observations.keys) {
            unobserve(pid)
        }
    }

    private func pid(for observer: AXObserver) -> pid_t? {
        for (pid, observation) in observations where CFEqual(observation.observer, observer) {
            return pid
        }
        return nil
    }

    private static let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon else { return }

        MainActor.assumeIsolated {
            let bridge = Unmanaged<AXAppObserverBridge>.fromOpaque(refcon).takeUnretainedValue()
            guard let pid = bridge.pid(for: observer) else { return }
            bridge.onEvent?(pid, notification as String, element)
        }
    }
}
