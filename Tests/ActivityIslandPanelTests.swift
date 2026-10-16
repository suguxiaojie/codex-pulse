import AppKit
import SwiftUI

@main
@MainActor
enum ActivityIslandPanelTests {
    static var checks = 0
    static var failures = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(name)") }
    }
    static func settle(_ duration: TimeInterval = 0.05) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            // NSApplication.run normally dispatches these WindowServer events.
            // A command-line fixture must pump AppKit, not only Foundation timers.
            // https://developer.apple.com/documentation/appkit/nsapplication/sendevent(_:)
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows()
        }
    }
    static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { settle(0.01) }
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screenSize = CGSize(width: 1200, height: 800)
        let one = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize)
        let four = ActivityIslandPanelMetrics(rowCount: 4, availableSize: screenSize)
        let many = ActivityIslandPanelMetrics(rowCount: 12, availableSize: screenSize)
        expect(one.hostSize == four.hostSize && four.hostSize == many.hostSize, "native canvas does not resize with row count")
        expect(many.visibleRowCount == 4, "long lists retain four-row viewport")
        expect(one.expandedRect.height < four.expandedRect.height, "single task uses a shorter surface")
        let small = ActivityIslandPanelMetrics(rowCount: 12, availableSize: CGSize(width: 600, height: 250))
        expect(small.visibleRowCount < 4 && small.hostSize.height <= 250, "short screen reduces visible rows")
        let costNow = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!
        let officialCostInput = AccountUsageSnapshot.parse(["summary": ["lifetimeTokens": 4_000_000],
            "dailyUsageBuckets": [["startDate": "2026-10-15", "tokens": 2_000_000],
                                  ["startDate": "2026-09-17", "tokens": 1_000_000],
                                  ["startDate": "2026-09-16", "tokens": 1_000_000]]], now: costNow)
        let officialCost = IslandDashboardCost(account: officialCostInput, local: .empty, now: costNow)
        expect(officialCost.days.count == 30 && officialCost.total == 1.5, "dashboard uses upstream UTC thirty-day token proxy, not local model prices")
        expect(officialCost.latest?.cost == 1 && officialCost.days.last?.cost == nil, "latest known day differs from missing today")
        let unknownCost = IslandDashboardCost(account: AccountUsageSnapshot.parse(["summary": ["lifetimeTokens": 1]], now: costNow), local: .empty, now: costNow)
        expect(unknownCost.total == nil, "missing daily token buckets never become a fabricated zero cost")
        let resetQuota = QuotaState.loaded([RateLimitBucket(id: "codex", name: "Codex", planType: "pro",
            primary: .init(usedPercent: 40, windowDurationMinutes: 10080, resetsAt: nil), secondary: nil,
            creditBalance: nil, hasCredits: false)], Date())
        let usableCredits = QuotaResetCreditSummary(availableCount: 2, credits: [])
        expect(IslandResetActionPolicy.canRequest(credits: usableCredits, quota: resetQuota, busy: false, privacy: false, fingerprint: "account"), "valid reset data permits confirmation UI")
        expect(!IslandResetActionPolicy.canRequest(credits: usableCredits, quota: .loading, busy: false, privacy: false, fingerprint: "account"), "stale or missing quota cannot authorize reset")
        expect(!IslandResetActionPolicy.canRequest(credits: usableCredits, quota: resetQuota, busy: true, privacy: false, fingerprint: "account"), "in-flight reset blocks duplicate confirmation")
        expect(!IslandResetActionPolicy.canRequest(credits: usableCredits, quota: resetQuota, busy: false, privacy: true, fingerprint: "account"), "privacy blocks reset")
        expect(!IslandResetActionPolicy.canRequest(credits: .init(availableCount: 0, credits: []), quota: resetQuota, busy: false, privacy: false, fingerprint: "account"), "empty credits block reset")
        expect(!IslandResetActionPolicy.canRequest(credits: usableCredits, quota: resetQuota, busy: false, privacy: false, fingerprint: nil), "unknown account blocks reset")
        let ticketSource = CGRect(x: 300, y: 180, width: 54, height: 32)
        let ticketDestination = CGRect(x: 150, y: 20, width: 201.29, height: 120)
        expect(DashboardResetTicketFlight.sample(progress: 0, source: ticketSource, destination: ticketDestination).position == CGPoint(x: ticketSource.midX, y: ticketSource.midY), "ticket starts at actual usage anchor")
        expect(abs(DashboardResetTicketFlight.sample(progress: 1, source: ticketSource, destination: ticketDestination).position.y - ticketDestination.midY) < 0.001, "ticket lands at reset anchor")
        let heatmapDate = Date()
        let heatmap = IslandDashboardHeatmap(activity: [.init(date: heatmapDate, tokens: 50)], endingAt: heatmapDate,
            mode: .cumulative, lifetimeTokens: 200)
        expect(heatmap.cells.last?.tokens == 200, "cumulative heatmap carries historical baseline exactly once")
        let weeklyHeatmap = IslandDashboardHeatmap(activity: [.init(date: heatmapDate, tokens: 50)], endingAt: heatmapDate,
            mode: .weekly, lifetimeTokens: 200)
        expect(weeklyHeatmap.cells.last?.tokens == 50, "weekly heatmap excludes pre-window baseline")
        let tasksCanvas = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, reservesUsagePage: true)
        let usageCanvas = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, usagePage: true, reservesUsagePage: true)
        let measuredUsage = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, usagePage: true, reservesUsagePage: true, usagePageHeight: 420)
        expect(measuredUsage.expandedRect.height == 420 && measuredUsage.hostSize == usageCanvas.hostSize, "measured content changes shell height without resizing canvas")
        expect(tasksCanvas.hostSize == usageCanvas.hostSize, "usage navigation retains native host canvas for shell animation")
        expect(usageCanvas.expandedRect.height > tasksCanvas.expandedRect.height, "usage page expands within the same shell")
        let shortUsage = ActivityIslandPanelMetrics(rowCount: 1, availableSize: CGSize(width: 600, height: 250), usagePage: true, reservesUsagePage: true)
        expect(shortUsage.hostSize.height <= 250, "usage page is constrained on short displays")
        let geometry = ActivityIslandWidthGeometry(screenWidth: 1440, cameraWidth: 200)
        expect(geometry.compactWidth == 480, "hardware notch keeps upstream side clearance")
        expect(geometry.expandedWidth(preferred: 900) == 680, "retired oversized widths normalize to upstream range")
        expect(geometry.expandedWidth(preferred: 560) == 560, "minimum width preserves readable notch chrome")
        let narrow = ActivityIslandWidthGeometry(screenWidth: 500)
        expect(narrow.expandedWidth(preferred: 680) == 452, "narrow displays constrain the actual island width")
        expect(one.compactRect.width == 340, "compact geometry is fixed and ignores retired scaling")

        let ids = (0..<8).map { "session-\($0)" }
        let layout = ActivityIslandListLayout(sessionIDs: ids)
        let anchor = layout.anchor(at: 100)!
        expect(anchor.sessionID == "session-1", "anchor identifies the row crossing viewport top")
        let inserted = ActivityIslandListLayout(sessionIDs: ["new"] + ids)
        expect(inserted.offset(for: anchor) == 170, "insertion above viewport preserves reading position")
        let removed = ActivityIslandListLayout(sessionIDs: ids.filter { $0 != anchor.sessionID })
        expect(removed.offset(for: anchor) == nil, "removed anchor falls back to native clamping")
        expect(layout.visibleSessionIDs(offset: 0, viewport: 82) == ["session-0"], "visibility does not start offscreen effects")
        expect(layout.visibleSessionIDs(offset: 82, viewport: 70) == ["session-1"], "row boundary changes visible renderer identity")

        let phases: [TaskPhase] = [.usingTool, .working, .waitingApproval, .completed, .ended, .usingTool]
        let titles = ["额度监控插件", "CoverAI 博客", "验证发布产物", "更新项目文档", "取消旧轮任务", "一个很长的中文项目名称与 English title，用于检查截断"]
        let rows = phases.enumerated().map { index, phase in
            ActivitySessionSnapshot(sessionID: ids[index], turnID: "turn-\(index)", projectID: index < 2 ? "/Monitor" : "/Project\(index)",
                projectName: "示例项目", title: titles[index], phase: phase,
                actionText: ["正在验证菜单栏布局", "整理文章结构与来源", "等待批准后运行测试", "本轮工作已完成", "本轮工作已取消", "读取 ActivityIslandPanel.swift"][index],
                updatedAt: Date(timeIntervalSince1970: 100),
                tokenUsage: .init(sessionID: ids[index], turnID: "turn-\(index)", total: index == 5 ? nil : (index + 1) * 12345),
                endReason: phase == .completed ? .completed : phase == .ended ? .cancelled : nil,
                modelName: "gpt-6.1-sol", reasoningEffort: "high", startedAt: Date().addingTimeInterval(-120))
        }
        let scroll = ActivityIslandNativeScroll()
        scroll.frame = CGRect(x: 0, y: 0, width: 404, height: 200)
        scroll.configure(rows: rows, playback: false, rowHeight: 70, onInteraction: nil)
        scroll.layoutSubtreeIfNeeded()
        scroll.scroll(to: 100)
        let nativeOffset = scroll.contentView.bounds.minY
        expect(abs(nativeOffset - 100) < 1, "native scroll accepts offset")
        scroll.configure(rows: [rows[5]] + Array(rows.prefix(5)),
                         playback: false, rowHeight: 70, onInteraction: nil)
        expect(abs(scroll.contentView.bounds.minY - 178) < 1, "native row insertion restores captured anchor")
        scroll.configure(rows: Array(rows.prefix(1)),
                         playback: false, rowHeight: 70, onInteraction: nil)
        expect(scroll.contentView.bounds.minY == 0, "shrinking list clamps obsolete scroll offset")
        settle()
        expect(scroll.visibility.sessionIDs.isEmpty, "hidden native scroll keeps all renderers stopped")
        scroll.stop()
        let smoke = ActivityStateSmokeMetalView(frame: CGRect(x: 0, y: 0, width: 400, height: 62))
        expect(smoke.isRendererAvailable, "imported QuotaView Metal pipeline compiles")
        expect(!smoke.fullSurfacePresentation, "task effects retain upstream state-driven progress front")
        for effect in ActivityIslandProgressEffect.allCases {
            smoke.setEffect(effect); smoke.setState(.working, taskIdentity: .init(sessionID: "sample", turnID: effect.rawValue))
            smoke.setPlaybackEnabled(true); smoke.setReduceMotion(true)
            expect(smoke.isPaused, "\(effect.rawValue) respects reduced motion")
            smoke.setReduceMotion(false); smoke.setPlaybackEnabled(false)
            expect(smoke.isPaused, "\(effect.rawValue) stops while hidden")
        }
        expect(ActivityIslandPreviewAssets.image("Wallpaper") != nil && ActivityIslandPreviewAssets.codexIcon != nil,
               "shared preview and provider assets load")

        let particles = ActivityIslandCompletionConfetti()
        let particleCanvas = CALayer(); particleCanvas.frame = CGRect(x: 0, y: 0, width: 700, height: 400)
        let particleRect = CGRect(x: 10, y: 0, width: 680, height: 160)
        particles.update(serial: 0, in: particleCanvas, rect: particleRect, reduceMotion: false, visible: true)
        expect(!particles.isActive, "baseline never plays historical completion confetti")
        particles.update(serial: 1, in: particleCanvas, rect: particleRect, reduceMotion: false, visible: true)
        expect(particles.isActive && particles.burstCount == 1, "fresh completion creates one finite edge burst")
        particles.update(serial: 1, in: particleCanvas, rect: particleRect, reduceMotion: false, visible: true)
        expect(particles.burstCount == 1, "ordinary content refresh cannot replay celebration")
        particles.update(serial: 1, in: particleCanvas, rect: particleRect, reduceMotion: true, visible: true)
        expect(!particles.isActive, "reduce motion stops active celebration")
        particles.update(serial: 2, in: particleCanvas, rect: particleRect, reduceMotion: true, visible: true)
        particles.update(serial: 2, in: particleCanvas, rect: particleRect, reduceMotion: false, visible: true)
        expect(particles.burstCount == 1, "enabling motion cannot replay a skipped completion")
        particles.update(serial: 3, in: particleCanvas, rect: particleRect, reduceMotion: false, visible: false)
        expect(!particles.isActive, "hidden panel consumes completion without particles")
        particles.update(serial: 4, in: particleCanvas, rect: particleRect, reduceMotion: false, visible: true)
        settle(2.3)
        expect(!particles.isActive && (particleCanvas.sublayers ?? []).isEmpty, "finite burst removes all emitter layers")
        let model = ActivityIslandViewModel()
        let quotaNow = Date(timeIntervalSince1970: 1000)
        let shortQuota = RateLimitWindow(usedPercent: 28, windowDurationMinutes: 300, resetsAt: quotaNow.addingTimeInterval(12000))
        let weekQuota = RateLimitWindow(usedPercent: 54, windowDurationMinutes: 10080, resetsAt: quotaNow.addingTimeInterval(345600))
        expect(IslandFloatingQuotaPeriods.windows([weekQuota, shortQuota]) == [shortQuota, weekQuota], "capsule orders periods by duration rather than field order")
        expect(IslandFloatingQuotaPeriods.windows([weekQuota]) == [weekQuota], "weekly-only account uses one compact segment")
        expect(IslandFloatingQuotaPeriods.windows([shortQuota]) == [shortQuota, nil], "short-only account keeps unknown weekly placeholder like upstream")
        expect(IslandFloatingQuotaPeriods.windows([]) == [nil], "unknown quota never invents zero remaining")
        expect(!IslandFloatingQuotaPeriods.current(.failed("offline", previous: [])), "failed refresh cannot present previous values as current")
        expect(!IslandFloatingQuotaPeriods.current(.loading), "loading quota remains unknown")
        let codexQuota = RateLimitBucket(id: "codex", name: "Codex", planType: nil, primary: weekQuota,
            secondary: shortQuota, creditBalance: nil, hasCredits: false)
        expect(model.showsCompactQuota && model.idleSummary == "暂无运行任务", "empty model chooses quota idle instead of a fabricated task")
        model.quotaState = .loaded([codexQuota], quotaNow)
        expect(model.compactQuotaPercent == "72%", "compact quota uses five-hour window when available")
        model.privacyMode = true
        expect(model.compactQuotaPercent == "—", "privacy hides resident quota percentage")
        model.privacyMode = false
        model.quotaState = .failed("offline", previous: [codexQuota])
        expect(model.compactQuotaPercent == "—", "stale quota is not presented as current")
        model.sessions = [rows[3]]
        expect(model.showsCompactQuota && model.idleSummary == "全部任务已完成", "all-completed branch uses upstream quota summary")
        model.sessions = [rows[0], rows[3]]
        expect(!model.showsCompactQuota, "real active task retains task banner alongside completed receipts")
        model.sessions = []; model.floatingUsageEnabled = false
        expect(model.showsCompactQuota, "floating capsule toggle does not disable primary idle banner")
        model.floatingUsageEnabled = true; model.quotaState = .loading
        let foreignQuota = RateLimitBucket(id: "spark", name: "Spark", planType: nil, primary: shortQuota,
            secondary: nil, creditBalance: nil, hasCredits: false)
        expect(IslandFloatingQuotaPeriods.windows(.loaded([foreignQuota, codexQuota], quotaNow)) == [shortQuota, weekQuota],
            "capsule uses official Codex bucket even when another model is first")
        expect(IslandFloatingQuotaPeriods.windows(.loaded([foreignQuota], quotaNow)).isEmpty,
            "missing Codex bucket never borrows a different model quota")
        expect(IslandFloatingQuotaPeriods.countdown(until: quotaNow, now: quotaNow) == "待刷新", "expired reset cannot show negative time")
        expect(IslandFloatingQuotaPeriods.countdown(until: quotaNow.addingTimeInterval(61), now: quotaNow) == "2 分", "sub-hour reset countdown rounds up")
        expect(IslandFloatingQuotaPeriods.countdown(until: nil, now: quotaNow) == "—", "missing reset remains unknown")
        model.privacyMode = true
        expect(!model.showsFloatingUsage, "privacy suppresses floating account quota")
        model.privacyMode = false; model.floatingUsageEnabled = false
        expect(!model.showsFloatingUsage, "capsule toggle suppresses live capsule")
        model.floatingUsageEnabled = true
        let withCapsule = ActivityIslandPanelMetrics(rowCount: 12, availableSize: screenSize, floatingUsage: true)
        expect(withCapsule.hostSize.height >= withCapsule.expandedRect.maxY + 40, "four-row canvas reserves room below island for capsule")
        let capsuleOnlyPoint = CGPoint(x: one.compactRect.midX, y: one.compactRect.maxY + 24)
        model.sessions = rows; model.reduceMotionOverride = true
        model.snapshot = ActivityIslandSnapshot(projectID: rows[0].projectID, projectName: rows[0].title,
            phase: rows[0].phase, actionText: rows[0].actionText, sessionCount: rows.count,
            projectCount: 5, updatedAt: rows[0].updatedAt, sessionID: rows[0].sessionID,
            turnID: rows[0].turnID, turnTokenUsage: rows[0].tokenUsage)
        let preferences = ActivityIslandPreferences.defaults
        expect(IslandOperationText(operation: "已完成", statusTitle: "已完成", completed: true).detail.isEmpty,
            "completed operation removes redundant status detail")
        expect(IslandOperationText(operation: "已完成 · 输出报告", statusTitle: "已完成", completed: true).detail == "输出报告",
            "completed operation preserves meaningful detail")
        let presenter = ActivityIslandPanelPresenter(model: model, presentsWindows: false)
        guard let screen = NSScreen.main else { throw NSError(domain: "PanelTests", code: 1) }
        let originalKeyWindow = NSApp.keyWindow
        model.presentation = .expanded
        presenter.present(screen: screen, preferences: preferences, animated: false)
        presenter.surface.layoutSubtreeIfNeeded(); settle()
        func nativeLists(_ view: NSView) -> [ActivityIslandNativeScroll] {
            (view as? ActivityIslandNativeScroll).map { [$0] } ?? view.subviews.flatMap(nativeLists)
        }
        let hostedList = nativeLists(presenter.surface).first
        model.material = .classic; settle()
        expect(hostedList?.host.rootView.liquidGlassEnabled == false, "classic setting reaches nested native list host")
        model.material = .liquidGlass; settle()
        expect(hostedList?.host.rootView.liquidGlassEnabled == true, "glass setting updates existing native list host")
        model.presentation = .compact; settle()
        expect(hostedList?.host.rootView.glassActive == false, "hidden expanded list disables native card glass")
        model.presentation = .expanded; settle()
        expect(hostedList?.host.rootView.glassActive == true, "expanded list restores native card glass")
        let nativeFrame = presenter.panel.frame
        let center = CGPoint(x: nativeFrame.midX, y: nativeFrame.maxY - 30)
        presenter.updatePointerRouting(at: center)
        expect(!presenter.panel.ignoresMouseEvents, "visible surface receives native pointer events")
        let empty = CGPoint(x: nativeFrame.minX + 1, y: nativeFrame.minY + 1)
        presenter.updatePointerRouting(at: empty)
        expect(presenter.panel.ignoresMouseEvents, "transparent reserve releases cross-window pointer routing")
        expect(NSApp.keyWindow === originalKeyWindow,
               "readonly panel does not acquire key focus")
        expect(!presenter.surface.hasActiveAnimations, "reduce motion leaves no native animation")
        let commits = presenter.surface.layoutCommitCount
        presenter.present(screen: screen, preferences: preferences, animated: false)
        expect(presenter.surface.layoutCommitCount == commits, "data refresh does not relayout fixed hosts")

        if let path = ProcessInfo.processInfo.environment["CODEX_ISLAND_PREVIEW_PATH"] {
            let bounds = CGRect(origin: .zero, size: presenter.panel.frame.size)
            guard let bitmap = presenter.surface.bitmapImageRepForCachingDisplay(in: bounds) else {
                throw NSError(domain: "PanelTests", code: 2)
            }
            presenter.surface.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "PanelTests", code: 3) }
            try data.write(to: URL(fileURLWithPath: path))
        }
        presenter.surface.update(metrics: model.metrics, compact: false, animated: false, material: .classic)
        let classicLayer = presenter.surface.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        expect(classicLayer?.fillColor?.alpha == 1, "classic material is truly opaque and ignores legacy opacity")
        let expandedRect = model.metrics.expandedRect
        presenter.surface.update(metrics: model.metrics, compact: true, animated: true)
        expect(presenter.surface.hasActiveAnimations, "collapse installs shared native path and content transitions")
        let transitions = presenter.surface.transitionCount
        presenter.surface.update(metrics: model.metrics, compact: true, animated: true)
        expect(presenter.surface.transitionCount == transitions, "identical geometry cannot restart its transition")
        presenter.surface.update(metrics: model.metrics, compact: false, animated: true)
        expect(presenter.surface.targetRect == expandedRect, "fast reversal targets expanded geometry")
        presenter.surface.cancelAnimations()
        expect(!presenter.surface.hasActiveAnimations, "explicit stop removes every animation")
        model.presentation = .compact
        presenter.present(screen: screen, preferences: preferences, animated: false)
        CATransaction.flush(); settle()
        expect(presenter.panel.frame == nativeFrame, "collapse keeps native window canvas unchanged")
        expect(presenter.surface.containsSurfacePoint(CGPoint(x: nativeFrame.width / 2, y: 30)), "compact body remains hittable")
        expect(!presenter.surface.containsSurfacePoint(CGPoint(x: nativeFrame.width / 2, y: nativeFrame.height - 10)),
               "former expanded content is not a compact hit target")
        expect(!presenter.surface.containsSurfacePoint(capsuleOnlyPoint), "quota capsule does not intercept desktop input")
        model.sessions = []; model.presentation = .compact
        presenter.present(screen: screen, preferences: preferences, animated: false); settle(0.1)
        func taskEffects(_ view: NSView) -> [ActivityStateSmokeMetalView] {
            (view as? ActivityStateSmokeMetalView).map { [$0] } ?? view.subviews.flatMap(taskEffects)
        }
        expect(presenter.surface.targetRect == model.metrics.compactRect && model.showsCompactQuota,
            "production native surface keeps compact geometry after last task disappears")
        expect(taskEffects(presenter.surface).isEmpty, "idle native tree contains no running task effect renderer")
        model.presentation = .expanded
        presenter.present(screen: screen, preferences: preferences, animated: false); settle(0.1)
        expect(nativeLists(presenter.surface).isEmpty, "empty expanded panel has no placeholder task list")
        model.sessions = rows; model.presentation = .compact
        model.completionBurstSerial = 7
        presenter.hide(animated: false)
        expect(presenter.surface.completionConfetti.lastSerial == 7 && !presenter.surface.completionConfetti.isActive,
            "native hide consumes completion so wake cannot replay hidden celebration")
        model.completionBurstSerial = 0
        expect(!presenter.panel.isVisible && !model.playbackVisible, "hide stops both native window and playback")
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_VISIBLE_QA"] == "1" {
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let visible = ActivityIslandPanelPresenter(model: model)
            var collapseClicks = 0
            model.onCollapse = { collapseClicks += 1 }
            model.presentation = .expanded
            model.reduceMotionOverride = false
            visible.present(screen: screen, preferences: preferences, animated: false)
            waitUntil { model.playbackVisible }
            settle(0.05)
            expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                   "visible nonactivating panel preserves foreground application")
            func scrolls(_ view: NSView) -> [ActivityIslandNativeScroll] {
                (view as? ActivityIslandNativeScroll).map { [$0] } ?? view.subviews.flatMap(scrolls)
            }
            let list = scrolls(visible.surface).first
            waitUntil { !(list?.visibility.sessionIDs.isEmpty ?? true) }
            print("Visible QA: window=\(visible.panel.isVisible), occlusion=\(visible.panel.occlusionState.rawValue), hidden=\(NSApp.isHidden), playback=\(model.playbackVisible), systemReduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion), scrolls=\(scrolls(visible.surface).count)")
            if let list {
                print("Visible QA scroll: frame=\(list.frame), viewport=\(list.contentSize), hidden=\(list.isHiddenOrHasHiddenAncestor), visibility=\(list.visibility.sessionIDs.count)")
            }
            expect(list != nil && !(list?.visibility.sessionIDs.isEmpty ?? true), "visible list starts only viewport effects")
            func effects(_ view: NSView) -> [ActivityStateSmokeMetalView] {
                (view as? ActivityStateSmokeMetalView).map { [$0] } ?? view.subviews.flatMap(effects)
            }
            let effectView = effects(visible.surface).first
            waitUntil { effectView?.displayedProgressPosition != nil }
            print("Visible QA Metal: frame=\(effectView?.frame ?? .zero), paused=\(effectView?.isPaused ?? true), progress=\(effectView?.displayedProgressPosition ?? -1)")
            expect(effectView?.frame.height == 62 && (effectView?.frame.width ?? 0) > 500,
                   "selected task renderer fills the complete card canvas")
            expect(effectView?.isPaused == false && (effectView?.displayedProgressPosition ?? 0) > 0,
                   "visible task renderer draws and advances the upstream state front")
            for update in 0..<50 {
                model.sessions[0].actionText = "Action \(update)"
                settle(0.1)
            }
            let updatedEffect = effects(visible.surface).first
            print("Visible QA Metal updates: retained=\(effectView === updatedEffect), progress=\(updatedEffect?.displayedProgressPosition ?? -1)")
            expect(effectView === updatedEffect && (updatedEffect?.displayedProgressPosition ?? 0) > 0.1,
                   "frequent state updates preserve the renderer and advance beyond plan discovery")
            model.sessions[0].phase = .waitingApproval
            waitUntil { updatedEffect?.isHidden == true }
            expect(updatedEffect?.isHidden == true && updatedEffect?.isPaused == true,
                   "confirmation replaces progress with the upstream edge reminder")
            model.sessions[0].phase = .completed
            waitUntil { updatedEffect?.isHidden == false }
            expect(updatedEffect?.isHidden == false, "completion restores the renderer for the completion sequence")
            let beforeScroll = list?.visibility.sessionIDs ?? []
            list?.scroll(to: 150); settle(0.1)
            expect(list?.visibility.sessionIDs != beforeScroll, "native scrolling updates visible effect identities")
            expect(list?.visibility.sessionIDs.count ?? 99 <= 5, "viewport bounds live effect count")
            let shell = visible.surface.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
            model.presentation = .compact
            visible.present(screen: screen, preferences: preferences, animated: true)
            CATransaction.flush(); settle(0.06)
            let middle = shell?.presentation()?.path?.boundingBoxOfPath.width ?? 0
            expect(middle > model.metrics.compactRect.width && middle < model.metrics.expandedRect.width,
                   "live shell passes through intermediate geometry")
            model.presentation = .expanded
            visible.present(screen: screen, preferences: preferences, animated: true)
            CATransaction.flush(); settle(0.03)
            let reversed = shell?.presentation()?.path?.boundingBoxOfPath.width ?? 0
            expect(reversed >= middle - 2, "live reversal continues from presentation geometry")
            settle(0.45)
            expect(abs((shell?.presentation()?.path?.boundingBoxOfPath.width ?? 0) - model.metrics.expandedRect.width) < 1,
                   "live reversal settles at the expanded target")
            let rect = model.metrics.expandedRect
            let buttonPoint = NSPoint(x: rect.maxX - 40,
                y: visible.panel.frame.height - rect.minY - ActivityIslandPanelMetrics.headerHeight / 2)
            let time = ProcessInfo.processInfo.systemUptime
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: buttonPoint, modifierFlags: [],
                timestamp: time + 0.01, windowNumber: visible.panel.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 0)!
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: buttonPoint, modifierFlags: [],
                timestamp: time, windowNumber: visible.panel.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.postEvent(up, atStart: false)
            visible.panel.sendEvent(down); settle(0.1)
            expect(collapseClicks == 1, "nonactivating native panel delivers the first collapse-button click")
            var expandClicks = 0
            model.onExpand = { expandClicks += 1 }
            model.presentation = .compact
            visible.present(screen: screen, preferences: preferences, animated: false)
            settle(0.05)
            func compactOrbs(_ view: NSView) -> [ActivityRippleGlowMetalView] {
                (view as? ActivityRippleGlowMetalView).map { [$0] } ?? view.subviews.flatMap(compactOrbs)
            }
            let compactOrb = compactOrbs(visible.surface).first { $0.frame.width > 30 && $0.frame.width < 40 }
            expect(compactOrb?.isRendererAvailable == true && (compactOrb?.drawableSize.width ?? 0) > 60,
                   "compact sphere uses upstream diameter correction and supersampled drawable")
            let compact = model.metrics.compactRect
            let compactPoint = NSPoint(x: compact.minX + 60,
                y: visible.panel.frame.height - compact.midY)
            let compactUp = NSEvent.mouseEvent(with: .leftMouseUp, location: compactPoint, modifierFlags: [],
                timestamp: time + 1.01, windowNumber: visible.panel.windowNumber, context: nil,
                eventNumber: 4, clickCount: 1, pressure: 0)!
            let compactDown = NSEvent.mouseEvent(with: .leftMouseDown, location: compactPoint, modifierFlags: [],
                timestamp: time + 1, windowNumber: visible.panel.windowNumber, context: nil,
                eventNumber: 3, clickCount: 1, pressure: 1)!
            NSApp.postEvent(compactUp, atStart: false)
            visible.panel.sendEvent(compactDown); settle(0.1)
            expect(expandClicks == 1, "compact task surface delivers first-click expansion")
            var automatic = ActivityIslandLifecycle()
            let automaticTimer = ActivityIslandCollapseTimer()
            _ = automatic.handle(.activityChanged(requiresAttention: false), popupDuration: 1)
            let originalDeadline = automatic.collapseDeadline
            model.presentation = automatic.presentation
            visible.present(screen: screen, preferences: preferences, animated: false)
            _ = automatic.handle(.pointerEntered)
            let expires = Date().addingTimeInterval(1.8)
            while Date() < expires && model.presentation == .expanded {
                _ = automatic.handle(.contentUpdated(requiresAttention: false))
                model.sessions[0].sessionTotalTokens = (model.sessions[0].sessionTotalTokens ?? 0) + 1
                automaticTimer.update(deadline: automatic.collapseDeadline) {
                    model.presentation = automatic.handle(.expandedHoldElapsed)
                    visible.present(screen: screen, preferences: preferences, animated: true)
                }
                settle(0.03)
            }
            expect(model.presentation == .compact && originalDeadline != nil,
                   "real window automatically compacts despite pointer entry and continuous token updates")
            settle(0.45)
            expect(visible.surface.targetRect == model.metrics.compactRect,
                   "automatic deadline also reaches actual compact native geometry")
            visible.hide(animated: false); settle(0.1)
            expect(list?.visibility.sessionIDs.isEmpty == true, "hidden panel releases every visible effect")
            expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                   "closing QA panel preserves foreground application")
        }
        print("Activity Island panel: \(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
        // Optional real-window inspection, isolated from user preferences/data.
        if let seconds = ProcessInfo.processInfo.environment["CODEX_ISLAND_COMPLETION_QA_SECONDS"].flatMap(Double.init) {
            model.sessions = [ActivitySessionSnapshot(sessionID: "completion-qa", turnID: "one", projectID: "qa",
                projectName: "示例项目", title: "【测试样例】本轮 Token 与完成礼花", phase: .completed, actionText: "已完成",
                updatedAt: Date(), tokenUsage: .init(sessionID: "completion-qa", turnID: "one", total: 6_900_000), endReason: .completed,
                modelName: "gpt-6.1-sol", reasoningEffort: "medium", startedAt: Date().addingTimeInterval(-180),
                sessionTotalTokens: 122_100_000)]
            model.focusedSessionID = nil; model.snapshot = nil
            model.presentation = .expanded; model.reduceMotionOverride = false
            let inspection = ActivityIslandPanelPresenter(model: model)
            var sample = preferences
            sample.glassDegree = Double(ProcessInfo.processInfo.environment["CODEX_ISLAND_QA_DEGREE"] ?? "0.45") ?? 0.45
            sample.material = ProcessInfo.processInfo.environment["CODEX_ISLAND_QA_CLASSIC"] == "1" ? .classic : .liquidGlass
            model.material = sample.material
            model.onRefresh = {
                guard let layer = inspection.surface.layer else { return }
                inspection.surface.completionConfetti.update(serial: 1, in: layer,
                    rect: inspection.surface.targetRect, reduceMotion: false, visible: true)
            }
            if ProcessInfo.processInfo.environment["CODEX_ISLAND_IDLE_QA"] == "1" {
                model.sessions = []; model.presentation = .compact; model.onRefresh = nil
                model.quotaState = .loaded([codexQuota], quotaNow)
                inspection.panel.title = "【测试样例】常驻额度／空闲横幅"
                model.onExpand = {
                    model.presentation = .expanded
                    inspection.present(screen: screen, preferences: sample, animated: false)
                    inspection.panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.midY - 100))
                }
            }
            inspection.present(screen: screen, preferences: sample, animated: false)
            inspection.panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.midY - 100))
            settle(min(60, max(0, seconds)))
            inspection.hide(animated: false)
        }
    }
}
