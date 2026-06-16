import AppKit
import ApplicationServices

/// Coordinates drag gestures, real windows, and floating tab strips.
@MainActor
final class TabGroupController: NSObject, DragMonitorDelegate {
    private let engine: WindowEngine
    private lazy var dragMonitor: DragMonitor = {
        let m = DragMonitor(engine: engine)
        m.delegate = self
        return m
    }()

    private let observer = AXObserverBridge()
    private let appFocusObserver = AXAppObserverBridge()
    private let windowCreationObserver = AXAppObserverBridge()
    private let dropIndicator = DropIndicatorPanel()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private(set) var groups: [TabGroup] = []
    private(set) var autoAddNewWindowsToStack = AppSettings.autoAddNewWindowsToStack
    private(set) var alwaysUseCompactMode = AppSettings.alwaysUseCompactMode

    private var draggedWindow: ManagedWindow?
    private var draggedSize: CGSize?
    private var dragGrabOffset: CGSize = .zero
    private var dragTargets: [WindowFrame] = []
    private var isApplyingLayout = false
    private weak var mostRecentGroup: TabGroup?

    init(engine: WindowEngine) {
        self.engine = engine
        super.init()
        observer.onEvent = { [weak self] id, notification in
            self?.handleWindowNotification(id: id, notification: notification)
        }
        appFocusObserver.onEvent = { [weak self] _, _, _ in
            self?.syncPanelZOrderWithFrontmostGroupSoon()
        }
        windowCreationObserver.onEvent = { [weak self] pid, notification, element in
            guard notification == kAXWindowCreatedNotification else { return }
            self?.handleWindowCreated(pid: pid, element: element)
        }
    }

    func start() {
        dragMonitor.start()
        observeSpaceChanges()
        observeApplicationChanges()
        if autoAddNewWindowsToStack {
            observeRunningAppsForWindowCreation()
        }
    }

    // MARK: - DragMonitorDelegate

    func dragDidBegin(window: ManagedWindow?, at point: CGPoint) {
        guard let window else { return }
        draggedWindow = window
        if let frame = engine.frame(of: window) {
            draggedSize = frame.size
            dragGrabOffset = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
        } else {
            draggedSize = nil
            dragGrabOffset = .zero
        }
        dragTargets = engine.onScreenWindowFrames(excluding: [window.id])
        engine.raise(window)
    }

    func dragDidMove(to point: CGPoint) {
        guard let dragged = draggedWindow else { return }
        if let size = draggedSize {
            let origin = CGPoint(x: point.x - dragGrabOffset.width,
                                 y: point.y - dragGrabOffset.height)
            engine.setFrame(CGRect(origin: origin, size: size), of: dragged)
        }
        if let hit = dragTargets.first(where: { $0.frame.contains(point) }) {
            dropIndicator.present(over: hit.frame)
        } else {
            dropIndicator.dismiss()
        }
    }

    func dragDidEnd(at point: CGPoint) {
        let dragged = draggedWindow
        resetDragState()
        DispatchQueue.main.async { [weak self] in
            guard let self, let dragged else { return }
            if let target = self.engine.window(at: point, excluding: [dragged.id]) {
                self.formGroup(dragged: dragged, target: target)
            } else if let sourceGroup = self.group(containing: dragged.id) {
                self.remove(dragged.id, from: sourceGroup, keepWindowObserved: false)
                self.engine.activate(dragged)
            }
        }
    }

    func dragDidCancel() {
        resetDragState()
    }

    private func resetDragState() {
        draggedWindow = nil
        draggedSize = nil
        dragTargets = []
        dropIndicator.dismiss()
    }

    // MARK: - Core action

    /// Tab `dragged` onto `target`, preserving the target frame.
    func formGroup(dragged: ManagedWindow, target: ManagedWindow, knownFrame: CGRect? = nil) {
        guard dragged.id != target.id,
              let targetFrame = knownFrame ?? engine.frame(of: target) else {
            return
        }

        let targetSpace = engine.spaceID(of: target)
        if let draggedSpace = engine.spaceID(of: dragged),
           let targetSpace,
           draggedSpace != targetSpace {
            engine.move(dragged, toSpaceOf: target)
        }

        if let sourceGroup = group(containing: dragged.id), !sourceGroup.contains(target.id) {
            remove(dragged.id, from: sourceGroup, keepWindowObserved: true)
        }

        engine.setFrame(targetFrame, of: dragged)

        let destination: TabGroup
        if let existing = group(containing: target.id) {
            destination = existing
            destination.contentFrame = targetFrame
            destination.spaceID = targetSpace
            if !destination.contains(dragged.id) {
                destination.windows.append(dragged)
            }
            destination.activeIndex = destination.windows.firstIndex { $0.id == dragged.id } ?? destination.activeIndex
        } else {
            destination = TabGroup(
                windows: [target, dragged],
                activeIndex: 1,
                contentFrame: targetFrame,
                spaceID: targetSpace
            )
            wire(destination)
            groups.append(destination)
        }

        observeWindows(in: destination)
        markRecentlyUsed(destination)
        updateFocusObservers()
        applyLayout(for: destination)
    }

    private func wire(_ group: TabGroup) {
        group.viewModel.onSelect = { [weak self, weak group] id in
            guard let self, let group else { return }
            self.selectTab(id, in: group)
        }
        group.viewModel.onClose = { [weak self, weak group] id in
            guard let self, let group else { return }
            self.untab(id, from: group)
        }
        group.viewModel.onActivateActive = { [weak self, weak group] in
            guard let self, let group, let active = group.activeWindow else { return }
            self.selectTab(active.id, in: group)
        }
        group.viewModel.onMoveBegan = { [weak group] in
            group?.moveAnchorFrame = group?.contentFrame
        }
        group.viewModel.onMoveChanged = { [weak self, weak group] translation in
            guard let self, let group, let anchor = group.moveAnchorFrame else { return }
            group.contentFrame = anchor.offsetBy(dx: translation.width, dy: translation.height)
            self.positionPanel(for: group)
            if let active = group.activeWindow {
                self.engine.setFrame(group.contentFrame, of: active)
            }
        }
        group.viewModel.onMoveEnded = { [weak self, weak group] in
            guard let self, let group else { return }
            group.moveAnchorFrame = nil
            self.applyLayout(for: group)
        }
    }

    private func group(containing id: WindowID) -> TabGroup? {
        groups.first { $0.contains(id) }
    }

    // MARK: - Group operations

    func add(_ window: ManagedWindow, to group: TabGroup) {
        if group.contains(window.id) {
            group.activeIndex = group.windows.firstIndex { $0.id == window.id } ?? group.activeIndex
            applyLayout(for: group)
            return
        }

        if let sourceGroup = self.group(containing: window.id), sourceGroup !== group {
            remove(window.id, from: sourceGroup, keepWindowObserved: true)
        }

        if let reference = group.activeWindow,
           let windowSpace = engine.spaceID(of: window),
           let groupSpace = group.spaceID,
           windowSpace != groupSpace {
            engine.move(window, toSpaceOf: reference)
        }

        group.windows.append(window)
        group.activeIndex = group.windows.count - 1
        observeWindows(in: group)
        markRecentlyUsed(group)
        updateFocusObservers()
        applyLayout(for: group)
    }

    private func positionPanel(for group: TabGroup) {
        let compact = group.useCompact
        if group.viewModel.compact != compact {
            group.viewModel.compact = compact
        }
        group.panel.applyLayout(
            compact: compact,
            resting: group.stripFrame,
            expanded: compact ? group.compactExpandedFrame : group.stripFrameAbove
        )
        reassertPanelZOrder(for: group)
    }

    func applyLayout(for group: TabGroup) {
        guard isGroupOnActiveSpace(group) else {
            group.panel.hide()
            group.syncViewModel()
            return
        }

        isApplyingLayout = true
        for (index, window) in group.windows.enumerated() {
            _ = engine.refreshTitle(window)
            if index == group.activeIndex {
                engine.setFrame(group.contentFrame, of: window)
            } else {
                parkOffscreen(window)
            }
        }
        if let active = group.activeWindow {
            engine.raise(active)
        }
        isApplyingLayout = false

        positionPanel(for: group)
        group.panel.show()
        group.syncViewModel()
    }

    /// Park inactive tabs out of view without triggering AX clamping.
    private func parkOffscreen(_ window: ManagedWindow) {
        guard let frame = engine.frame(of: window) else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let parked = CGRect(x: visible.maxX - 1,
                            y: visible.minY + 1 - frame.height,
                            width: frame.width, height: frame.height)
        engine.setFrame(parked, of: window)
    }

    func selectTab(_ id: WindowID, in group: TabGroup) {
        guard let idx = group.windows.firstIndex(where: { $0.id == id }) else { return }
        group.activeIndex = idx
        applyLayout(for: group)
        if isGroupOnActiveSpace(group) {
            engine.activate(group.windows[idx])
        }
    }

    func untab(_ id: WindowID, from group: TabGroup) {
        guard let window = group.windows.first(where: { $0.id == id }) else { return }
        let base = group.contentFrame
        remove(id, from: group, keepWindowObserved: false)
        let offset: CGFloat = 32
        let size = engine.frame(of: window)?.size ?? base.size
        engine.setFrame(CGRect(x: base.minX + offset, y: base.minY - offset,
                               width: size.width, height: size.height), of: window)
        engine.activate(window)
    }

    // MARK: - Spaces

    private func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private func observeApplicationChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let pid = app.processIdentifier
        for group in groups {
            for window in group.windows where window.pid == pid {
                remove(window.id, from: group, keepWindowObserved: false)
            }
        }
    }

    private func pruneDeadWindows() {
        for group in groups {
            for window in group.windows where !engine.isAlive(window) {
                remove(window.id, from: group, keepWindowObserved: false)
            }
        }
    }

    @objc private func activeSpaceChanged() {
        pruneDeadWindows()
        for group in groups {
            if isGroupOnActiveSpace(group) {
                applyLayout(for: group)
            } else {
                group.panel.hide()
            }
        }
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        pruneDeadWindows()
        syncPanelZOrderWithFrontmostGroupSoon()
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard autoAddNewWindowsToStack,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        observeAppForWindowCreation(app)
    }

    // MARK: - Focus and window creation

    func setAutoAddNewWindowsToStack(_ enabled: Bool) {
        autoAddNewWindowsToStack = enabled
        AppSettings.autoAddNewWindowsToStack = enabled
        if enabled {
            observeRunningAppsForWindowCreation()
        } else {
            windowCreationObserver.unobserveAll()
        }
    }

    func setAlwaysUseCompactMode(_ enabled: Bool) {
        alwaysUseCompactMode = enabled
        AppSettings.alwaysUseCompactMode = enabled
        for group in groups where isGroupOnActiveSpace(group) {
            positionPanel(for: group)
            group.panel.show()
        }
    }

    private func updateFocusObservers() {
        let pids = Set(groups.flatMap(\.windows).map(\.pid).filter { $0 != ownPID })
        appFocusObserver.setObservedPIDs(
            pids,
            notifications: [
                kAXFocusedWindowChangedNotification,
                kAXMainWindowChangedNotification,
                kAXApplicationActivatedNotification
            ]
        )
    }

    private func observeRunningAppsForWindowCreation() {
        for app in NSWorkspace.shared.runningApplications {
            observeAppForWindowCreation(app)
        }
    }

    private func observeAppForWindowCreation(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ownPID else { return }
        windowCreationObserver.observe(
            pid: pid,
            notifications: [kAXWindowCreatedNotification]
        )
    }

    private func handleWindowCreated(pid: pid_t, element: AXUIElement) {
        guard autoAddNewWindowsToStack, pid != ownPID, !groups.isEmpty else { return }
        resolveAndAutoAddWindow(pid: pid, element: element, attemptsRemaining: 3)
    }

    private func resolveAndAutoAddWindow(pid: pid_t, element: AXUIElement, attemptsRemaining: Int) {
        let candidates = candidateWindowElements(from: element, pid: pid)
        let onScreen = Set(engine.onScreenWindowFrames(excluding: []).map { $0.id })
        let window = candidates
            .compactMap { engine.managedWindow(from: $0, pid: pid) }
            .first { group(containing: $0.id) == nil && onScreen.contains($0.id) }

        if let window, let target = targetGroupForNewWindow() {
            add(window, to: target)
            return
        }

        if window != nil {
            return
        }

        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.resolveAndAutoAddWindow(
                pid: pid,
                element: element,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func candidateWindowElements(from element: AXUIElement, pid: pid_t) -> [AXUIElement] {
        var candidates = [element]
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        if let focused = copyAXElementAttribute(kAXFocusedWindowAttribute, from: appElement) {
            candidates.append(focused)
        }
        if let main = copyAXElementAttribute(kAXMainWindowAttribute, from: appElement) {
            candidates.append(main)
        }
        return candidates
    }

    private func targetGroupForNewWindow() -> TabGroup? {
        if let frontmost = frontmostGroup() {
            return frontmost
        }
        if let mostRecentGroup, groups.contains(where: { $0 === mostRecentGroup }) {
            return mostRecentGroup
        }
        return groups.last
    }

    private func frontmostGroup() -> TabGroup? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard pid != ownPID,
              let focusedID = focusedOrMainWindowID(for: pid) else {
            return nil
        }
        return groups.first { group in
            guard let active = group.activeWindow else { return false }
            return active.pid == pid && active.id == focusedID
        }
    }

    private func syncPanelZOrderWithFrontmostGroupSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.syncPanelZOrderWithFrontmostGroup()
        }
    }

    private func syncPanelZOrderWithFrontmostGroup() {
        let frontmost = frontmostGroup()

        if let frontmost, isGroupOnActiveSpace(frontmost) {
            markRecentlyUsed(frontmost)
            positionPanel(for: frontmost)
        }

        for group in groups where group !== frontmost {
            reassertPanelZOrder(for: group)
        }
    }

    private func reassertPanelZOrder(for group: TabGroup) {
        guard isGroupOnActiveSpace(group) else { return }

        let frontmostCGWindowID = frontmostCGWindowID()
        if let active = group.activeWindow,
           frontmostGroup() === group || frontmostCGWindowID == active.id {
            group.panel.order(.above, relativeTo: Int(active.id))
            return
        }

        if let frontmostCGWindowID {
            group.panel.order(.below, relativeTo: Int(frontmostCGWindowID))
        } else {
            group.panel.orderOut(nil)
        }
    }

    private func markRecentlyUsed(_ group: TabGroup) {
        mostRecentGroup = group
    }

    private func focusedOrMainWindowID(for pid: pid_t) -> WindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        if let focused = copyAXElementAttribute(kAXFocusedWindowAttribute, from: appElement),
           let id = windowID(for: focused) {
            return id
        }
        if let main = copyAXElementAttribute(kAXMainWindowAttribute, from: appElement),
           let id = windowID(for: main) {
            return id
        }
        return nil
    }

    private func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func windowID(for element: AXUIElement) -> WindowID? {
        var resolved = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &resolved) == .success,
              resolved != 0 else {
            return nil
        }
        return resolved
    }

    private func frontmostCGWindowID() -> WindowID? {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            CGWindowID(0)
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfos {
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber else {
                continue
            }

            if pid_t(ownerPID.int32Value) == ownPID || layer.intValue != 0 {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 {
                continue
            }
            return WindowID(number.uint32Value)
        }

        return nil
    }

    // MARK: - AX sync

    private func observeWindows(in group: TabGroup) {
        for window in group.windows {
            observer.observe(window)
        }
    }

    private func handleWindowNotification(id: WindowID, notification: String) {
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

    // AX move notifications lag during title-bar drags.
    private var activeMoveTimer: Timer?
    private weak var activeMoveGroup: TabGroup?
    private var activeMoveDeadline: Date = .distantPast

    private func beginTrackingActiveMove(for group: TabGroup) {
        activeMoveGroup = group
        activeMoveDeadline = Date().addingTimeInterval(0.2)
        guard activeMoveTimer == nil else { return }
        activeMoveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickActiveMove() }
        }
    }

    private func tickActiveMove() {
        guard let group = activeMoveGroup, let active = group.activeWindow,
              active.id != draggedWindow?.id, Date() <= activeMoveDeadline,
              let frame = engine.windowServerFrame(of: active.id) ?? engine.frame(of: active) else {
            endTrackingActiveMove()
            return
        }
        group.contentFrame = frame
        positionPanel(for: group)
    }

    private func endTrackingActiveMove() {
        activeMoveTimer?.invalidate()
        activeMoveTimer = nil
        activeMoveGroup = nil
    }

    private func remove(_ id: WindowID, from group: TabGroup, keepWindowObserved: Bool) {
        guard let idx = group.windows.firstIndex(where: { $0.id == id }) else { return }
        group.windows.remove(at: idx)
        if !keepWindowObserved {
            observer.unobserve(id)
        }

        if group.windows.count <= 1 {
            dissolve(group)
            return
        }

        if idx < group.activeIndex {
            group.activeIndex -= 1
        } else if group.activeIndex >= group.windows.count {
            group.activeIndex = group.windows.count - 1
        }

        applyLayout(for: group)
        updateFocusObservers()
    }

    private func dissolve(_ group: TabGroup) {
        group.panel.hide()
        for window in group.windows {
            observer.unobserve(window.id)
            engine.setFrame(group.contentFrame, of: window)
        }
        groups.removeAll { $0 === group }
        if mostRecentGroup === group {
            mostRecentGroup = groups.last
        }
        updateFocusObservers()
    }

    private func isGroupOnActiveSpace(_ group: TabGroup) -> Bool {
        guard let groupSpace = group.spaceID,
              let activeSpace = engine.activeSpaceID() else {
            return true
        }
        return groupSpace == activeSpace
    }
}
