// Adapted from QuotaView/IslandConceptBoard.swift (MIT), Copyright (c) 2026 Duoasa.
// Fixed canvas, presentation-layer retargeting and pointer routing are retained;
// Codex Monitor supplies its own session model, content and classic surface.
// Source pin and full license: Resources/ThirdPartyNotices.txt.
import AppKit
import SwiftUI

// Drawing-only margins; the original metrics and animation curves are unchanged.
extension ActivityIslandPanelMetrics {
    init(alertOver base: ActivityIslandPanelMetrics) {
        hostSize = base.hostSize
        compactRect = base.compactRect
        let width: CGFloat = min(base.hostSize.width, 380)
        expandedRect = CGRect(x: (base.hostSize.width - width) / 2, y: base.expandedRect.minY,
            width: width, height: 156 + (base.hardwareGap > 0 ? base.compactRect.height : 0))
        rowHeight = base.rowHeight; visibleRowCount = base.visibleRowCount
        hardwareGap = base.hardwareGap; maximumUsageHeight = base.maximumUsageHeight
    }
    init(shadowing base: ActivityIslandPanelMetrics) {
        let side = IslandHardwareBlack.shadowHorizontalInset
        hostSize = CGSize(width: base.hostSize.width + side * 2,
                          height: base.hostSize.height + IslandHardwareBlack.shadowBottomInset)
        compactRect = base.compactRect.offsetBy(dx: side, dy: 0)
        expandedRect = base.expandedRect.offsetBy(dx: side, dy: 0)
        rowHeight = base.rowHeight
        visibleRowCount = base.visibleRowCount
        hardwareGap = base.hardwareGap
        maximumUsageHeight = base.maximumUsageHeight
    }
}

final class ActivityIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // QuotaView d16307f appearance compatibility (non-public AppKit selectors).
    // Keep this panel's glass optically active without making it key or
    // changing the foreground application. No process-wide appearance override.
    @objc(hasKeyAppearance)
    private nonisolated func islandKeyAppearance() -> Bool { true }
    @objc(_hasKeyAppearance)
    private nonisolated func islandInternalKeyAppearance() -> Bool { true }
    @objc(_hasActiveAppearance)
    private nonisolated func islandActiveAppearance() -> Bool { true }
    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private nonisolated func islandActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

@MainActor
final class ActivityIslandSurface: NSView {
    override var isFlipped: Bool { true }
    private let model: ActivityIslandViewModel
    private let shell = CAShapeLayer()
    private let clipping = CAShapeLayer()
    private let content = NSView()
    private let glassContainer = NSView()
    private var glassHost: NSHostingView<IslandAlertBackdrop>?
    private var glassGeometry: IslandGlassGeometry?
    private let compactHost: NSHostingView<ActivityIslandView>
    private let expandedHost: NSHostingView<ActivityIslandView>
    private let usageHost: NSHostingView<IslandFloatingUsageCapsule>
    private let usageGeometry: IslandGlassGeometry
    let completionConfetti = ActivityIslandCompletionConfetti()
    private(set) var targetRect = CGRect.zero
    private var lastCompact: Bool?
    private(set) var transitionCount = 0
    private(set) var layoutCommitCount = 0

    init(model: ActivityIslandViewModel) {
        self.model = model
        let geometry = IslandGlassGeometry(value: .init(rect: .zero, radius: 0, compact: true), degree: 0.45)
        usageGeometry = geometry
        usageHost = NSHostingView(rootView: IslandFloatingUsageCapsule(model: model, geometry: geometry))
        compactHost = NSHostingView(rootView: ActivityIslandView(model: model, compact: true))
        expandedHost = NSHostingView(rootView: ActivityIslandView(model: model, compact: false))
        super.init(frame: .zero)
        wantsLayer = true; content.wantsLayer = true
        layer?.opacity = 0
        compactHost.wantsLayer = true; expandedHost.wantsLayer = true
        expandedHost.layer?.masksToBounds = true
        compactHost.sizingOptions = []; expandedHost.sizingOptions = []
        shell.shadowColor = NSColor.black.cgColor
        shell.shadowOpacity = 0.26; shell.shadowRadius = 7
        shell.shadowOffset = CGSize(width: 0, height: 2)
        layer?.addSublayer(shell)
        glassContainer.wantsLayer = true
        addSubview(glassContainer)
        addSubview(content); content.layer?.mask = clipping
        content.addSubview(expandedHost); content.addSubview(compactHost)
        usageHost.sizingOptions = []
        addSubview(usageHost)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(metrics: ActivityIslandPanelMetrics, compact: Bool, animated: Bool,
                material: ActivityIslandMaterial = .classic, degree: Double = 0.45) {
        let newRect = compact ? metrics.compactRect : metrics.expandedRect
        usageHost.frame = bounds
        usageGeometry.update(value: .init(rect: newRect, radius: 0, compact: compact), degree: 0.45, animated: animated)
        let changed = newRect != targetRect || lastCompact != compact || content.frame != bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shell.fillColor = NSColor.black.cgColor
        shell.shadowOpacity = 0 // The synchronized SwiftUI backdrop owns the hardware shadow.
        if content.frame != bounds { content.frame = bounds }
        if glassContainer.frame != bounds { glassContainer.frame = bounds }
        glassContainer.isHidden = false
        content.layer?.mask = clipping
        for (host, rect) in [(compactHost, metrics.compactRect), (expandedHost, metrics.expandedRect)] {
            let frame = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
            if host.frame != frame { host.frame = frame; layoutCommitCount += 1 }
        }
        CATransaction.commit()
        if !animated { cancelAnimations() }
        let value = IslandGlassGeometry.Value(rect: newRect, radius: compact ? 13 : 24, compact: compact)
        if let glassHost, let glassGeometry {
            if glassHost.frame != bounds { glassHost.frame = bounds }
            glassGeometry.update(value: value, degree: degree, animated: animated)
        } else {
            let geometry = IslandGlassGeometry(value: value, degree: degree)
            let host = NSHostingView(rootView: IslandAlertBackdrop(model: model, geometry: geometry))
            host.sizingOptions = []; host.frame = bounds
            glassGeometry = geometry; glassHost = host; glassContainer.addSubview(host)
        }
        guard changed else { return }
        let radius: CGFloat = compact ? 13 : 24
        var shift = CGAffineTransform(translationX: newRect.minX, y: newRect.minY)
        let path = IslandNotchShape(bottomRadius: radius).path(in: CGRect(origin: .zero, size: newRect.size)).cgPath.copy(using: &shift)!
        var mirror = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        let maskPath = path.copy(using: &mirror)!
        let oldPath = shell.presentation()?.path ?? shell.path
        let oldMask = clipping.presentation()?.path ?? clipping.path
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shell.path = path; shell.shadowPath = path; clipping.path = maskPath
        CATransaction.commit()
        if animated, let oldPath, let oldMask {
            transitionCount += 1
            animate(layer: shell, key: "path", from: oldPath, to: path, duration: ActivityIslandSurfaceMotion.duration)
            animate(layer: shell, key: "shadowPath", from: oldPath, to: path, duration: ActivityIslandSurfaceMotion.duration)
            animate(layer: clipping, key: "path", from: oldMask, to: maskPath, duration: ActivityIslandSurfaceMotion.duration)
        }
        if lastCompact != compact {
            setContent(compactHost, visible: compact, animated: animated)
            setContent(expandedHost, visible: !compact, animated: animated)
        }
        targetRect = newRect; lastCompact = compact
        compactHost.setAccessibilityHidden(!compact)
        expandedHost.setAccessibilityHidden(compact)
        expandedHost.layoutSubtreeIfNeeded()
    }
    private func animate(layer: CALayer, key: String, from: Any, to: Any, duration: Double) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from; animation.toValue = to; animation.duration = duration
        animation.timingFunction = ActivityIslandSurfaceMotion.timingFunction
        layer.add(animation, forKey: key)
    }
    private func setContent(_ host: NSView, visible: Bool, animated: Bool) {
        guard let layer = host.layer else { return }
        let previous = layer.presentation()?.opacity ?? layer.opacity
        let oldTransform = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = visible ? 1 : 0
        layer.transform = visible ? CATransform3DIdentity : CATransform3DMakeTranslation(0, 5, 0)
        CATransaction.commit()
        if animated {
            animate(layer: layer, key: "opacity", from: previous, to: layer.opacity,
                    duration: ActivityIslandSurfaceMotion.contentDuration)
            animate(layer: layer, key: "transform", from: NSValue(caTransform3D: oldTransform),
                    to: NSValue(caTransform3D: layer.transform), duration: ActivityIslandSurfaceMotion.duration)
        }
    }
    func setVisible(_ visible: Bool, animated: Bool) {
        if !visible { completionConfetti.stop() }
        guard let layer else { return }
        if layer.opacity == (visible ? 1 : 0) {
            if !animated { layer.removeAnimation(forKey: "opacity") }
            return
        }
        let previous = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = visible ? 1 : 0
        CATransaction.commit()
        if animated { animate(layer: layer, key: "opacity", from: previous, to: layer.opacity,
                              duration: ActivityIslandSurfaceMotion.contentDuration) }
        else { layer.removeAnimation(forKey: "opacity") }
    }
    func containsSurfacePoint(_ point: CGPoint) -> Bool {
        (shell.presentation()?.path ?? shell.path)?.contains(point) ?? false
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard containsSurfacePoint(local) else { return nil }
        let host: NSView = lastCompact == true ? compactHost : expandedHost
        return host.hitTest(convert(local, to: content)) ?? self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var hasActiveAnimations: Bool {
        [shell, clipping, compactHost.layer, expandedHost.layer, layer].compactMap { $0 }
            .contains { !($0.animationKeys() ?? []).isEmpty }
    }
    func cancelAnimations() {
        [shell, clipping, compactHost.layer, expandedHost.layer, layer].compactMap { $0 }
            .forEach { $0.removeAllAnimations() }
        glassGeometry?.stop()
        usageGeometry.stop()
    }
}

@MainActor
final class ActivityIslandPanelPresenter {
    let model: ActivityIslandViewModel
    let panel: ActivityIslandPanel
    let surface: ActivityIslandSurface
    var onDismissOutside: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onNeedsRefresh: (() -> Void)?
    private var monitors: [Any] = []
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []
    private var hoverOpen: DispatchWorkItem?
    private var transitionHitUpdate: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var pointerInside = false
    private var suppressHoverUntilExit = false
    private var suspended = false
    var alertsAvailable: Bool { !suspended && !NSApp.isHidden }
    var alertPointerInside: Bool { panel.isVisible && containsPointer(at: NSEvent.mouseLocation) }
    private let presentsWindows: Bool

    init(model: ActivityIslandViewModel, presentsWindows: Bool = true) {
        self.model = model
        self.presentsWindows = presentsWindows
        panel = ActivityIslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        surface = ActivityIslandSurface(model: model)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.canHide = false
        panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.ignoresMouseEvents = true; panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none; panel.contentView = surface
        panel.title = "Codex Pulse · 活动会话"
        model.onApprovalMeasurementChange = { [weak self] in self?.onNeedsRefresh?() }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                self?.handlePointerEvent(event); return event
            }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in self?.handlePointerEvent(event) }) { monitors.append(global) }
        observe(NSWindow.didChangeOcclusionStateNotification, object: panel) { $0.updatePlayback() }
        observe(NSApplication.didHideNotification, object: NSApp) { $0.updatePlayback() }
        observe(NSApplication.didUnhideNotification, object: NSApp) { $0.onNeedsRefresh?() }
        observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                center: NSWorkspace.shared.notificationCenter) { $0.onNeedsRefresh?() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observe(name, center: NSWorkspace.shared.notificationCenter) { $0.setSuspended(true) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observe(name, center: NSWorkspace.shared.notificationCenter) { $0.setSuspended(false) }
        }
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observe(.init(name), center: DistributedNotificationCenter.default()) { $0.setSuspended(value) }
        }
    }
    private func observe(_ name: Notification.Name, object: AnyObject? = nil,
                         center: NotificationCenter = .default,
                         action: @escaping (ActivityIslandPanelPresenter) -> Void) {
        observations.append((center, center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }))
    }
    private func setSuspended(_ value: Bool) {
        suspended = value
        if value { hide(animated: false) } else { onNeedsRefresh?() }
    }
    private var lastPresentation: ActivityIslandPresentation?
    // Opt-in, task-local acceptance evidence. Never enabled by preferences and
    // never records titles, message content, account data or raw identifiers.
    private let auditURL = ProcessInfo.processInfo.environment["CODEX_ISLAND_AUDIT_PATH"].map { URL(fileURLWithPath: $0) }
    private func recordPresentationAudit() {
        guard let auditURL else { return }
        func runningEffects(_ view: NSView) -> Int {
            let own = (view as? ActivityStateSmokeMetalView).map { !$0.isPaused && !$0.isHiddenOrHasHiddenAncestor ? 1 : 0 } ?? 0
            return own + view.subviews.reduce(0) { $0 + runningEffects($1) }
        }
        let mode = model.presentation == .compact ? (model.showsCompactQuota ? "idleQuota" : "taskCompact")
            : model.presentation == .expanded ? (model.sessions.isEmpty ? "emptyExpanded" : "tasksExpanded") : "hidden"
        let record: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()),
            "pid": ProcessInfo.processInfo.processIdentifier, "contentMode": mode,
            "activeRows": model.sessions.filter { $0.phase.isActive }.count, "rowCount": model.sessions.count,
            "showsCompactQuota": model.showsCompactQuota, "idleSummary": model.showsCompactQuota ? model.idleSummary : "",
            "runningTaskEffects": runningEffects(surface), "confettiActive": surface.completionConfetti.isActive,
            "windowVisible": panel.isVisible, "suspended": suspended]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: auditURL, options: .atomic)
        }
    }
    func present(screen: NSScreen, preferences: ActivityIslandPreferences, animated: Bool) {
        hideWork?.cancel(); hideWork = nil
        guard model.presentation != .hidden, !suspended else {
            hide(animated: animated); return
        }
        let wasVisible = panel.isVisible
        let presentationChanged = lastPresentation != model.presentation
        lastPresentation = model.presentation
        let usable = screen.visibleFrame
        let hardwareGap = screen.safeAreaInsets.top > 0 ? max(0, screen.frame.width
            - (screen.auxiliaryTopLeftArea?.width ?? 0) - (screen.auxiliaryTopRightArea?.width ?? 0)) : 0
        let width = ActivityIslandWidthGeometry(screenWidth: usable.width, cameraWidth: hardwareGap).expandedWidth(preferred: preferences.expandedWidth)
        let approvalHeight = model.approvalHeight(width: width - 56)
        let focus = model.sessions.first { $0.id == model.focusedSessionID }
            ?? ActivitySessionSnapshot.compactFocus(rows: model.sessions, selectedID: nil, receipt: nil)
        let focusHeight = ActivityIslandPanelMetrics.focusHeight(for: model.privacyMode ? focus?.hidingDetails() : focus)
        let taskHeight = ActivityIslandPanelMetrics.stageHeight(rowCount: model.sessions.count, focusHeight: focusHeight)
            + approvalHeight + ActivityIslandPanelMetrics.headerHeight + ActivityIslandPanelMetrics.footerHeight
        // Reuse the measured-page height cap for task content; rendering remains the task list.
        let taskMetrics = ActivityIslandPanelMetrics(rowCount: model.sessions.count,
            availableSize: usable.size,
            expandedWidth: CGFloat(preferences.expandedWidth), safeAreaTop: screen.safeAreaInsets.top,
            hardwareGap: hardwareGap,
            floatingUsage: model.floatingUsageEnabled && !model.privacyMode,
            usagePage: model.showsUsagePage || approvalHeight > 0, reservesUsagePage: true,
            usagePageHeight: model.showsUsagePage ? model.usagePageHeight : taskHeight, focusHeight: focusHeight)
        let baseMetrics = model.alert == nil ? taskMetrics : ActivityIslandPanelMetrics(alertOver: taskMetrics)
        let metrics = ActivityIslandPanelMetrics(shadowing: baseMetrics)
        if model.metrics != metrics { model.metrics = metrics }
        let x = screen.frame.midX - baseMetrics.hostSize.width / 2
        let frame = CGRect(x: max(usable.minX, min(usable.maxX - baseMetrics.hostSize.width, x)) - IslandHardwareBlack.shadowHorizontalInset,
            y: screen.frame.maxY - metrics.hostSize.height,
            width: metrics.hostSize.width, height: metrics.hostSize.height)
        let geometryChanged = panel.frame != frame
        if geometryChanged { panel.setFrame(frame, display: false) }
        let reduced = model.reduceMotionOverride || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animate = animated && panel.isVisible && !geometryChanged && !reduced
        surface.update(metrics: metrics, compact: model.presentation == .compact,
                       animated: animate,
                       material: model.showsUsagePage && model.resetDetailVisible && model.presentation == .expanded ? .classic : preferences.material, degree: preferences.glassDegree)
        surface.setVisible(true, animated: animated && !reduced)
        if let layer = surface.layer {
            surface.completionConfetti.update(serial: model.completionBurstSerial, in: layer,
                rect: preferences.confettiIntensity == .light ? surface.targetRect : metrics.compactRect,
                reduceMotion: reduced, visible: presentsWindows && !suspended && !NSApp.isHidden,
                intensity: preferences.confettiIntensity, islandWindow: panel, screen: screen)
        }
        if !panel.isVisible && presentsWindows {
            panel.orderFrontRegardless()
            NSApp.addWindowsItem(panel, title: panel.title, filename: false)
        }
        updatePlayback()
        updatePointerRouting()
        recordPresentationAudit()
        if presentationChanged || geometryChanged {
            transitionHitUpdate?.cancel(); transitionHitUpdate = nil
            if wasVisible && presentationChanged && !geometryChanged {
                let work = DispatchWorkItem { [weak self] in self?.trackPointer() }
                transitionHitUpdate = work
                DispatchQueue.main.asyncAfter(deadline: .now() + ActivityIslandSurfaceMotion.duration + 0.02, execute: work)
            }
        }
    }

    func suppressHover() { suppressHoverUntilExit = pointerInside; hoverOpen?.cancel(); hoverOpen = nil }
    private func updatePlayback() {
        let visible = panel.isVisible && panel.occlusionState.contains(.visible) && !NSApp.isHidden && !suspended
        if !visible { surface.completionConfetti.stop() }
        if model.playbackVisible != visible { model.playbackVisible = visible }
    }
    func containsPointer(at point: CGPoint) -> Bool {
        surface.containsSurfacePoint(CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y))
    }
    func updatePointerRouting(at point: CGPoint? = nil) {
        panel.ignoresMouseEvents = !containsPointer(at: point ?? NSEvent.mouseLocation)
    }
    private func handlePointerEvent(_ event: NSEvent) {
        trackPointer()
        if panel.isVisible && model.presentation == .expanded,
           event.type == .leftMouseDown || event.type == .rightMouseDown,
           !containsPointer(at: NSEvent.mouseLocation) { onDismissOutside?() }
    }
    func trackPointer(at point: CGPoint? = nil) {
        guard panel.isVisible, model.presentation != .hidden, !suspended else { return }
        let inside = containsPointer(at: point ?? NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverOpen?.cancel(); hoverOpen = nil
        if !inside {
            suppressHoverUntilExit = false
            onHoverChanged?(false)
        } else if !suppressHoverUntilExit {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pointerInside, !self.suppressHoverUntilExit else { return }
                self.onHoverChanged?(true)
            }
            hoverOpen = work
            DispatchQueue.main.asyncAfter(deadline: .now() + ActivityIslandSurfaceMotion.hoverOpenDelay, execute: work)
        }
    }
    func hide(animated: Bool) {
        if let layer = surface.layer {
            surface.completionConfetti.update(serial: model.completionBurstSerial, in: layer,
                rect: surface.targetRect, reduceMotion: model.reduceMotionOverride, visible: false)
        }
        lastPresentation = nil
        hoverOpen?.cancel(); hoverOpen = nil
        transitionHitUpdate?.cancel(); transitionHitUpdate = nil
        hideWork?.cancel(); hideWork = nil
        model.playbackVisible = false
        surface.setVisible(false, animated: animated)
        panel.ignoresMouseEvents = true
        let wasInside = pointerInside
        pointerInside = false; suppressHoverUntilExit = false
        if animated && panel.isVisible {
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + ActivityIslandSurfaceMotion.contentDuration, execute: work)
        } else { surface.cancelAnimations(); panel.orderOut(nil) }
        recordPresentationAudit()
        if wasInside { onHoverChanged?(false) }
    }
    deinit {
        monitors.forEach(NSEvent.removeMonitor)
        observations.forEach { $0.0.removeObserver($0.1) }
        hoverOpen?.cancel(); transitionHitUpdate?.cancel(); hideWork?.cancel()
    }
}
