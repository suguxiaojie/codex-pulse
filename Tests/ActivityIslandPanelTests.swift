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
        IslandMascotTests.run()
        IslandHardwareBlackTests.run()
        IslandDesktopPreviewTests.run()
        let screenSize = CGSize(width: 1200, height: 800)
        let one = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize)
        let four = ActivityIslandPanelMetrics(rowCount: 4, availableSize: screenSize)
        let many = ActivityIslandPanelMetrics(rowCount: 12, availableSize: screenSize)
        expect(one.hostSize == four.hostSize && four.hostSize == many.hostSize, "native canvas does not resize with row count")
        expect(many.visibleRowCount == 1, "focus stage has one main card regardless of session count")
        let five = ActivityIslandPanelMetrics(rowCount: 5, availableSize: screenSize)
        expect(five.expandedRect.height == one.expandedRect.height + ActivityIslandPanelMetrics.railHeight,
            "five sessions add only the 30 pt rail and its 8 pt gap")
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
        let claudeNow = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        func utcDay(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T00:00:00Z")! }
        let claudeSummary = ClaudeCodeUsageSummary(days: [
            .init(date: utcDay("2026-09-21"), tokens: 100, estimatedCost: 1),
            .init(date: utcDay("2026-09-22"), tokens: 200, estimatedCost: 2),
            .init(date: utcDay("2026-10-20"), tokens: 300, estimatedCost: nil),
            .init(date: utcDay("2026-10-21"), tokens: 400, estimatedCost: 4),
            .init(date: utcDay("2026-10-22"), tokens: 999, estimatedCost: 9)
        ], lifetimeTokens: 1999, complete: true, fileCount: 1, updatedAt: claudeNow)
        let claudeLimits = ClaudeCodeRateLimits(fiveHour: .init(usedPercent: 25, resetsAt: claudeNow.addingTimeInterval(3600)),
            sevenDay: .init(usedPercent: 50, resetsAt: claudeNow.addingTimeInterval(-1)), capturedAt: claudeNow)
        let claudeProjection = IslandClaudeUsage(usage: claudeSummary, limits: claudeLimits, statusLineEnabled: true,
            now: claudeNow, calendar: nyCalendar)
        expect(claudeProjection.recentTokens == 400 && claudeProjection.monthlyTokens == 900 && claudeProjection.lifetimeTokens == 1000,
            "Claude token scopes exclude future and use thirty local days")
        expect(claudeProjection.activity.last?.date == nyCalendar.startOfDay(for: claudeNow), "Claude day label does not shift backwards in New York")
        expect(claudeProjection.fiveHour?.remainingPercent == 75 && claudeProjection.weekly == nil, "Claude quota preserves valid window and hides expired one")
        expect(claudeProjection.cost.days.count == 30 && claudeProjection.cost.total == nil && claudeProjection.cost.latest?.cost == 4,
            "unpriced Claude day makes total unknown while preserving priced latest day")
        let staleClaude = IslandClaudeUsage(usage: claudeSummary, limits: claudeLimits, statusLineEnabled: true,
            now: claudeNow.addingTimeInterval(301), calendar: nyCalendar)
        // Stale quota remains observable until reset, explicitly labeled by the presentation.
        expect(staleClaude.fiveHour?.remainingPercent == 75 && staleClaude.monthlyTokens == 900, "stale quota retains last observation")
        let disabledClaudeQuota = IslandClaudeUsage(usage: claudeSummary, limits: claudeLimits, statusLineEnabled: false,
            now: claudeNow, calendar: nyCalendar)
        expect(disabledClaudeQuota.fiveHour == nil && disabledClaudeQuota.weekly == nil, "disabled statusLine never exposes retained quota")
        let missingClaude = IslandClaudeUsage(usage: nil, limits: nil, statusLineEnabled: true, now: claudeNow)
        expect(missingClaude.recentTokens == nil && missingClaude.cost.total == nil && missingClaude.activity.isEmpty,
            "missing Claude data never falls back to Codex or fabricated zero")
        let pricedClaude = IslandClaudeUsage(usage: .init(days: [.init(date: utcDay("2026-10-20"), tokens: 300, estimatedCost: 3)],
            lifetimeTokens: 300, complete: true, fileCount: 1, updatedAt: claudeNow), limits: nil,
            statusLineEnabled: true, now: claudeNow, calendar: nyCalendar)
        expect(pricedClaude.cost.total == 3 && pricedClaude.cost.latest?.cost == 3,
            "Claude model prices are used directly and latest recorded day skips zero-filled today")
        let partialClaude = IslandClaudeUsage(usage: .init(days: [], lifetimeTokens: 0, complete: false, fileCount: 1, updatedAt: claudeNow),
            limits: nil, statusLineEnabled: true, now: claudeNow)
        expect(!partialClaude.complete && partialClaude.cost.total == nil, "partial scan does not report a complete zero cost")
        func presentation(_ limits: ClaudeCodeRateLimits? = claudeLimits, at now: Date = claudeNow,
                          enabled: Bool = true, summary: ClaudeCodeUsageSummary? = claudeSummary) -> IslandUsagePresentation {
            .claude(usage: summary, limits: limits, statusLineEnabled: enabled, now: now, calendar: nyCalendar)
        }
        let current = presentation()
        expect(current.quotas[0].freshness == .current && current.quotas[0].remainingPercent == 75, "presentation current quota")
        let stale = presentation(at: claudeNow.addingTimeInterval(301))
        expect(stale.quotas[0].freshness == .stale(observedAt: claudeNow) && stale.quotas[0].remainingPercent == 75, "presentation stale quota retains percent")
        expect(stale.quotas[0].freshness.observationLabel(now: claudeNow.addingTimeInterval(301)) == "5 分钟前观测", "stale observation minutes")
        expect(stale.quotas[0].freshness.observationLabel(now: claudeNow.addingTimeInterval(7200)) == "2 小时前观测", "stale observation hours")
        expect(presentation(at: claudeNow.addingTimeInterval(3600)).quotas[0].freshness == .unavailable, "reset boundary is unavailable")
        let noReset = ClaudeCodeRateLimits(fiveHour: .init(usedPercent: 25, resetsAt: nil), sevenDay: nil, capturedAt: claudeNow)
        expect(presentation(noReset, at: claudeNow.addingTimeInterval(301)).quotas[0].remainingPercent == nil, "stale without reset unavailable")
        expect(presentation(enabled: false).quotas.allSatisfy { $0.freshness == .unavailable }, "statusLine disabled unavailable")
        expect(presentation(at: claudeNow.addingTimeInterval(-61)).quotas[0].freshness == .unavailable, "future capture outside tolerance unavailable")
        expect(presentation(at: claudeNow.addingTimeInterval(-60)).quotas[0].freshness == .current, "future capture tolerance inclusive")
        expect(presentation(at: claudeNow.addingTimeInterval(300)).quotas[0].freshness == .current, "current 300 second boundary inclusive")
        expect(current.cost.total == 6 && current.cost.totalIsLowerBound && current.cost.note == "含未定价模型", "partial prices sum known days as lower bound")
        let partialSummary = ClaudeCodeUsageSummary(days: claudeSummary.days, lifetimeTokens: 1999, complete: false, fileCount: 1, updatedAt: claudeNow)
        expect(presentation(summary: partialSummary).cost.note == "扫描中 · 部分记录", "scan note takes priority over unpriced")
        let allUnknown = ClaudeCodeUsageSummary(days: [.init(date: utcDay("2026-10-21"), tokens: 100, estimatedCost: nil)], lifetimeTokens: 100, complete: true, fileCount: 1, updatedAt: claudeNow)
        expect(presentation(summary: allUnknown).cost.total == nil, "all recorded prices unknown does not sum padding zeroes")
        expect(presentation(summary: nil).cost.total == nil, "missing summary cost remains unavailable")
        expect(current.metrics.count == 3 && current.metrics[0].dateTag == nil, "today needs no date tag")
        let weekOld = ClaudeCodeUsageSummary(days: [.init(date: utcDay("2026-10-14"), tokens: 100, estimatedCost: 1)], lifetimeTokens: 100, complete: true, fileCount: 1, updatedAt: claudeNow)
        let oldPresentation = presentation(summary: weekOld)
        expect(oldPresentation.metrics[0].dateTag == "10 月 14 日" && oldPresentation.cost.latestDateTag == "10 月 14 日", "New York last recorded date preserved in metric and cost")
        let codexPresentation = IslandUsagePresentation.codex(quotaState: resetQuota, accountUsage: officialCostInput, usageCost: .empty, resetCredits: usableCredits, now: costNow)
        expect(codexPresentation.metrics.map(\.tokens) == [officialCostInput?.recentTokens, officialCostInput?.monthlyTokens, officialCostInput?.lifetimeTokens], "Codex three metrics preserve official priority")
        expect(codexPresentation.cost.total == officialCost.total && codexPresentation.cost.latest == officialCost.latest, "Codex cost total and latest unchanged")
        expect(codexPresentation.metrics[0].dateTag == "10 月 15 日", "Codex official day label preserved")
        var localSnapshot = CostSnapshot.empty
        localSnapshot.updatedAt = costNow
        localSnapshot.aggregate.usage.day.tokens = 500
        localSnapshot.aggregate.usage.month.tokens = 2000
        localSnapshot.aggregate.lifetimeTokens = 7000
        localSnapshot.aggregate.usage.activity = [.init(date: costNow, tokens: 500)]
        localSnapshot.aggregate.costActivity = [.init(date: costNow, dollars: 0.75)]
        let localPresentation = IslandUsagePresentation.codex(quotaState: resetQuota, accountUsage: nil, usageCost: localSnapshot, resetCredits: nil, now: costNow)
        let localChart = IslandDashboardCost(account: nil, local: localSnapshot.aggregate, now: costNow)
        expect(localPresentation.metrics.map(\.tokens) == [localSnapshot.usage.day.tokens, localSnapshot.usage.month.tokens, localSnapshot.aggregate.lifetimeTokens], "Codex local metric fallback unchanged")
        expect(localPresentation.cost.total == localChart.total && localPresentation.cost.latest == localChart.latest, "Codex local chart fallback unchanged")
        expect(current.cost.helpText.contains("不含网页搜索等按次计费"), "cost help excludes per-call charges")
        let sourceModel = ActivityIslandViewModel()
        sourceModel.selectUsageProvider(.claude)
        expect(sourceModel.usageProvider == .codex, "disabled Claude cannot be selected")
        sourceModel.updateClaudeEnabled(true); sourceModel.claudeUsage = claudeSummary
        sourceModel.selectUsageProvider(.claude)
        expect(sourceModel.usageProvider == .claude, "enabled Claude is selectable without official quota")
        sourceModel.resetBusy = true; sourceModel.selectUsageProvider(.codex)
        expect(sourceModel.usageProvider == .claude, "busy reset blocks provider changes")
        sourceModel.resetBusy = false; sourceModel.selectUsageProvider(.codex)
        sourceModel.resetConfirmationPresented = true; sourceModel.selectUsageProvider(.claude)
        expect(sourceModel.usageProvider == .codex, "pending reset confirmation cannot switch source")
        sourceModel.resetConfirmationPresented = false; sourceModel.selectUsageProvider(.claude)
        sourceModel.updateClaudeEnabled(false)
        expect(sourceModel.usageProvider == .codex && sourceModel.claudeUsage == nil && sourceModel.claudeLimits == nil,
            "disabling Claude returns to Codex and clears retained Claude presentation")
        let tasksCanvas = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, reservesUsagePage: true)
        let usageCanvas = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, usagePage: true, reservesUsagePage: true)
        let measuredUsage = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, usagePage: true, reservesUsagePage: true, usagePageHeight: 420)
        expect(measuredUsage.expandedRect.height == 420 && measuredUsage.hostSize == usageCanvas.hostSize, "measured content changes shell height without resizing canvas")
        expect(tasksCanvas.hostSize == usageCanvas.hostSize, "usage navigation retains native host canvas for shell animation")
        expect(usageCanvas.expandedRect.height > tasksCanvas.expandedRect.height, "usage page expands within the same shell")
        let shortUsage = ActivityIslandPanelMetrics(rowCount: 1, availableSize: CGSize(width: 600, height: 250), usagePage: true, reservesUsagePage: true)
        expect(measuredUsage.expandedRect.height <= measuredUsage.maximumUsageHeight, "usage fits maximum usage height")
        let overflowingUsage = ActivityIslandPanelMetrics(rowCount: 1, availableSize: CGSize(width: 600, height: 250), usagePage: true, reservesUsagePage: true, usagePageHeight: 900)
        expect(overflowingUsage.expandedRect.height <= overflowingUsage.maximumUsageHeight, "oversized usage clamps for page scrolling")
        expect(shortUsage.hostSize.height <= 250, "usage page is constrained on short displays")
        // Source placement is a notch-safety contract: body/header must not construct the selector.
        let dashboardURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexNotchMonitor/ActivityIslandUsageDashboard.swift")
        let dashboardSource = try String(contentsOf: dashboardURL, encoding: .utf8)
        let usageStart = dashboardSource.range(of: "    private func usagePage(")!
        let usageEnd = dashboardSource.range(of: "    private func pageFlow(")!
        expect(!dashboardSource[..<usageStart.lowerBound].contains("IslandUsageProviderSwitch"), "provider switch is absent from dashboard body and notch header construction")
        let usageConstruction = String(dashboardSource[usageStart.lowerBound..<usageEnd.lowerBound])
        expect(usageConstruction.range(of: "IslandUsageProviderSwitch(model: model)")!.lowerBound < usageConstruction.range(of: "if let status = p.statusLine")!.lowerBound,
            "provider switch is constructed in usage content before status line")
        // The restored content selector adds a row; screen limits, not the retired compact-height target, apply.
        // Measure the real SwiftUI hierarchy with synthetic data, without showing or installing an app.
        let usageModel = ActivityIslandViewModel()
        usageModel.metrics = usageCanvas
        usageModel.quotaState = resetQuota
        usageModel.accountUsage = officialCostInput
        usageModel.resetCredits = usableCredits
        var measuredHeight: CGFloat = 0
        usageModel.onUsageHeightChange = { measuredHeight = $0 }
        let usageHost = NSHostingView(rootView: ActivityIslandUsageDashboard(model: usageModel))
        let usageWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: usageCanvas.expandedRect.width, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        usageWindow.contentView = usageHost
        usageHost.layoutSubtreeIfNeeded(); settle(0.3)
        expect(measuredHeight > 0 && measuredHeight <= usageCanvas.maximumUsageHeight, "Codex content selector and usage fit screen limit")
        expect(measuredHeight <= usageCanvas.maximumUsageHeight, "measured Codex page fits screen limit")
        print("Usage layout measured Codex: \(measuredHeight) pt")
        usageModel.updateClaudeEnabled(true); usageModel.claudeUsage = claudeSummary; usageModel.claudeLimits = claudeLimits
        usageModel.selectUsageProvider(.claude)
        usageHost.layoutSubtreeIfNeeded(); settle(0.3)
        expect(measuredHeight > 0 && measuredHeight <= usageCanvas.maximumUsageHeight, "Claude content selector and usage fit screen limit")
        print("Usage layout measured Claude: \(measuredHeight) pt")
        let narrowUsage = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, expandedWidth: 560,
            safeAreaTop: 32, hardwareGap: 200, usagePage: true, reservesUsagePage: true)
        usageModel.metrics = narrowUsage
        usageModel.selectUsageProvider(.codex)
        usageHost.layoutSubtreeIfNeeded(); settle(0.3)
        expect(narrowUsage.expandedRect.width == 560 && measuredHeight > 0 && measuredHeight <= narrowUsage.maximumUsageHeight,
            "560 pt notched Codex usage fits maximum height")
        print("Usage layout measured Codex (560 pt): \(measuredHeight) pt")
        usageModel.claudeStatusLineEnabled = true
        usageModel.claudeLimits = .init(fiveHour: .init(usedPercent: 12, resetsAt: Date().addingTimeInterval(14400)),
            sevenDay: .init(usedPercent: 15, resetsAt: Date().addingTimeInterval(568800)), capturedAt: Date())
        usageModel.selectUsageProvider(.claude)
        usageHost.layoutSubtreeIfNeeded(); settle(0.3)
        expect(measuredHeight > 0 && measuredHeight <= narrowUsage.maximumUsageHeight, "560 pt notched Claude usage fits maximum height")
        print("Usage layout measured Claude (560 pt): \(measuredHeight) pt")
        usageModel.metrics = overflowingUsage
        usageHost.layoutSubtreeIfNeeded(); settle(0.3)
        expect(measuredHeight <= overflowingUsage.maximumUsageHeight, "real DashboardPageLayout scrolls oversized content within screen limit")
        usageWindow.contentView = nil
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
        let markRect = CGRect(x: 0, y: 0, width: 13, height: 13)
        let markPath = ClaudeMarkShape().path(in: markRect)
        expect(!markPath.isEmpty, "Claude mark produces a nonempty 13 pt path")
        expect(markRect.contains(markPath.boundingRect), "Claude mark stays inside its 13 pt bounds")
        let offsetMarkRect = CGRect(x: 20, y: 30, width: 13, height: 13)
        expect(offsetMarkRect.contains(ClaudeMarkShape().path(in: offsetMarkRect).boundingRect),
            "Claude mark respects the supplied rectangle origin")
        let providerHost = NSHostingView(rootView: IslandUsageProviderSwitch(model: sourceModel))
        expect(providerHost.fittingSize == CGSize(width: 240, height: 28), "provider logos preserve the 240 by 28 pt control size")

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
        // Compact results must render static text independently of the running marquee host.
        let resultModel = ActivityIslandViewModel()
        resultModel.presentation = .compact
        var resultRow = ActivitySessionSnapshot(sessionID: "result-fixture", turnID: "turn", projectID: "p",
            projectName: "P", title: "验收任务", phase: .working, actionText: "运行中", updatedAt: Date(), tokenUsage: nil)
        func resultMarquees(_ view: NSView) -> [IslandScrollingTextHost] {
            (view as? IslandScrollingTextHost).map { [$0] } ?? view.subviews.flatMap(resultMarquees)
        }
        for gap: CGFloat in [0, 180] {
            resultModel.metrics = ActivityIslandPanelMetrics(rowCount: 1, availableSize: screenSize, hardwareGap: gap)
            let host = NSHostingView(rootView: ActivityIslandView(model: resultModel, compact: true))
            host.frame = CGRect(origin: .zero, size: resultModel.metrics.compactRect.size)
            for reduced in [false, true] {
                resultModel.reduceMotionOverride = reduced
                for (reason, prefix): (SessionEndReason, String) in [(.completed, "完成"), (.cancelled, "取消"), (.failed, "失败"), (.ended, "结束")] {
                    resultRow.phase = .working; resultRow.endReason = nil
                    resultModel.sessions = [resultRow]; resultModel.compactReceipt = nil
                    host.layoutSubtreeIfNeeded(); settle()
                    expect(!resultMarquees(host).isEmpty, "running label retains original marquee")
                    resultRow.phase = reason.phase; resultRow.endReason = reason
                    resultRow.actionText = ""
                    resultRow.recentSteps = [.init(id: "empty-step", title: "", state: .done)]
                    resultModel.sessions = [resultRow]
                    resultModel.compactReceipt = reason == .completed ? resultRow : nil
                    host.layoutSubtreeIfNeeded(); settle()
                    expect(IslandSessionPresentation(row: resultRow).compactTitle == prefix + " · 验收任务",
                        "result title ignores empty current step and action")
                    expect(resultMarquees(host).isEmpty, "terminal transition removes native marquee even while playback is off")
                    let content = ActivityIslandCompactContent(row: resultRow, rows: [resultRow],
                        width: resultModel.metrics.compactRect.width, height: 40, hardwareGap: gap,
                        animated: false, reduceMotion: reduced)
                    let label = NSHostingView(rootView: content.taskText)
                    expect(label.fittingSize.width > 0 && label.fittingSize.height >= 14, "static result label has nonzero intrinsic size")
                    resultModel.privacyMode = true
                    host.layoutSubtreeIfNeeded(); settle()
                    expect(IslandSessionPresentation(row: resultRow.hidingDetails()).compactTitle == "会话详情已隐藏",
                        "private result label contains no task title")
                    expect(resultMarquees(host).isEmpty, "private result remains static")
                    resultModel.privacyMode = false
                }
            }
        }
        resultRow.title = "  \n "
        expect(IslandSessionPresentation(row: resultRow).compactTitle == "结束 · Codex 任务", "blank result title has a safe fallback")

        let handoffModel = ActivityIslandViewModel()
        handoffModel.reduceMotionOverride = true
        var completedFocus = rows[3]
        completedFocus.updatedAt = Date().addingTimeInterval(-2.94)
        completedFocus.endReason = .completed
        handoffModel.sessions = [completedFocus, rows[0]]
        handoffModel.focusedSessionID = completedFocus.id
        handoffModel.compactReceipt = completedFocus
        handoffModel.completionBurstSerial = 7
        let handoffTimer = ActivityIslandCollapseTimer()
        let handoffDeadline = completedFocus.updatedAt.addingTimeInterval(ActivityIslandFocusHandoff.duration)
        var handoffCount = 0
        handoffTimer.update(deadline: handoffDeadline) {
            if handoffModel.handoffFocus(now: Date()) != nil { handoffCount += 1 }
        }
        waitUntil { handoffCount == 1 }
        expect(handoffModel.focusedSessionID == rows[0].id && handoffCount == 1,
            "one-shot handoff works without data refresh and with Reduce Motion")
        expect(handoffModel.completionBurstSerial == 7 && handoffModel.compactReceipt == completedFocus,
            "timer-only handoff never recreates completion or changes compact receipt")
        expect(handoffModel.handoffFocus(now: Date()) == nil, "repeated handoff is idempotent")
        settle(0.08)
        expect(handoffCount == 1 && handoffTimer.deadline == nil, "handoff timer fires only once")
        handoffTimer.update(deadline: Date().addingTimeInterval(0.03)) { handoffCount += 1 }
        handoffTimer.update(deadline: nil, onExpire: {})
        settle(0.06)
        expect(handoffCount == 1, "new data or explicit selection can cancel pending handoff")
        let idleModel = ActivityIslandViewModel()
        idleModel.presentation = .compact
        func marquees(_ view: NSView) -> [IslandScrollingTextHost] {
            (view as? IslandScrollingTextHost).map { [$0] } ?? view.subviews.flatMap(marquees)
        }
        for gap: CGFloat in [0, 180] {
            idleModel.metrics = ActivityIslandPanelMetrics(rowCount: 0, availableSize: screenSize, hardwareGap: gap)
            idleModel.sessions = [rows[0]]
            let host = NSHostingView(rootView: ActivityIslandView(model: idleModel, compact: true))
            host.frame = CGRect(origin: .zero, size: idleModel.metrics.compactRect.size)
            host.layoutSubtreeIfNeeded(); settle()
            expect(!marquees(host).isEmpty, "active task mounts scrolling text")
            idleModel.sessions = []
            host.layoutSubtreeIfNeeded(); settle()
            expect(marquees(host).isEmpty, "empty quota branch removes all task marquee hosts")
            expect(!idleModel.compactQuotaAccessibilitySummary.contains("0 会话"), "empty quota omits zero session count")
            let available = gap > 0 ? (idleModel.metrics.compactRect.width - 40 - gap - 16) / 2 : 200
            let textWidth = (idleModel.idleSummary as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
            expect(textWidth <= available, "complete idle text fits compact side without session counter")
        }
        model.quotaState = .loaded([codexQuota], quotaNow)
        expect(model.compactQuotaPercent == "72%", "compact quota uses five-hour window when available")
        model.privacyMode = true
        expect(model.compactQuotaPercent == "—", "privacy hides resident quota percentage")
        model.privacyMode = false
        model.quotaState = .failed("offline", previous: [codexQuota])
        expect(model.compactQuotaPercent == "—", "stale quota is not presented as current")
        model.sessions = [rows[3]]
        expect(model.showsCompactQuota && model.idleSummary == "全部任务已完成", "all-completed branch uses upstream quota summary")
        var retainedResult = rows[3]; retainedResult.isRetainedReceipt = true
        model.sessions = [retainedResult]; model.compactReceipt = retainedResult
        expect(model.showsCompactQuota, "retained completion cannot rebuild compact receipt display")
        var failedResult = retainedResult; failedResult.phase = .failed
        failedResult.endReason = .failed
        failedResult.isRetainedReceipt = false
        model.sessions = [failedResult]; model.compactReceipt = nil
        expect(!model.showsCompactQuota, "fresh failed receipt keeps compact failure feedback")
        failedResult.isRetainedReceipt = true
        model.sessions = [failedResult]
        expect(model.showsCompactQuota, "failed receipt returns to quota only in retention period")
        model.sessions = [retainedResult, failedResult]
        expect(model.showsCompactQuota && model.idleSummary == "暂无运行任务", "mixed terminal results retain quota without claiming success")
        model.compactReceipt = nil
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
        func stageScrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(stageScrolls)
        }
        expect(nativeLists(presenter.surface).isEmpty, "production stage no longer embeds the legacy vertical row host")
        expect(!stageScrolls(presenter.surface).isEmpty, "focus stage provides native overflow scrolling")
        let focusedBeforeApproval = model.focusedSessionID
        let fixtureApproval = IslandApprovalContent(id: "fixture-approval", provider: "Codex", title: "执行命令",
            summary: "echo synthetic", command: true,
            actions: [.init(id: "accept", title: "允许一次"), .init(id: "acceptForSession", title: "本会话允许"),
                      .init(id: "decline", title: "拒绝", destructive: true), .init(id: "cancel", title: "取消任务", destructive: true)],
            submit: { _, _ in fatalError("Rendering must never submit") }, fallback: {}, details: {})
        model.approvalContent = { _ in fixtureApproval }
        model.focusedSessionID = rows.first(where: { $0.phase == .waitingApproval })?.id
        model.objectWillChange.send(); settle()
        expect(model.approvalMeasurement?.sessionID == model.focusedSessionID, "only focused approval reports its measurement")
        expect(NSApp.keyWindow === originalKeyWindow, "approval card never acquires key focus")
        var waiting = rows.first(where: { $0.phase == .waitingApproval })!
        waiting.provider = "Claude Code"
        let inline = IslandSessionPresentation(row: waiting, hasInlineApproval: true)
        let claudeFallback = IslandSessionPresentation(row: waiting)
        waiting.provider = "Codex"
        let codexFallback = IslandSessionPresentation(row: waiting)
        expect(inline.runningDetail == "在下方卡片中处理", "inline approval copy")
        expect(claudeFallback.runningDetail == "请在 Claude Code 中确认", "Claude fallback copy")
        expect(codexFallback.runningDetail == "请在 Codex 中处理", "Codex no-handle copy")
        for presentation in [inline, claudeFallback, codexFallback] {
            expect(presentation.compactTitle.contains(presentation.runningDetail), "compact uses provider-aware approval copy")
            expect(presentation.accessibilitySummary.contains(presentation.runningDetail), "accessibility uses provider-aware approval copy")
        }
        func measureApproval(_ content: IslandApprovalContent, width: CGFloat = 504, privacy: Bool = false, name: String) -> CGFloat {
            var measured: CGFloat = 0
            let host = NSHostingView(rootView: ActivityIslandApprovalCard(content: content, privacy: privacy,
                onHeightChange: { measured = $0 }).environment(\.colorScheme, .dark))
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: width, height: 500)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
            host.layoutSubtreeIfNeeded(); settle(0.2)
            expect(measured > 0, "approval reports actual SwiftUI height")
            host.setFrameSize(CGSize(width: width, height: max(1, measured)))
            host.layoutSubtreeIfNeeded(); settle(0.7)
            if let directory = ProcessInfo.processInfo.environment["ISLAND_APPROVAL_QA_DIR"],
               let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            }
            return measured
        }
        let shortHeight = measureApproval(fixtureApproval, name: "approval-command")
        let narrowHeight = measureApproval(fixtureApproval, width: 300, name: "approval-wrapped")
        expect(shortHeight < 190, "short command no longer reserves 190 points")
        expect(narrowHeight > shortHeight && narrowHeight < 190, "narrow actions wrap and increase measured height")
        _ = measureApproval(fixtureApproval, privacy: true, name: "approval-private")
        var questionContent = IslandApprovalContent(id: "fixture-questions", provider: "Claude Code", title: "需要回答",
            summary: "", fallbackTitle: "回终端", submit: { _, _ in fatalError("Rendering must never submit") }, fallback: {}, details: {})
        questionContent.questions = (0..<4).map { index in
            .init(id: "q\(index)", title: "问题 \(index + 1)", options: (0..<12).map { "选项 \($0 + 1)" })
        }
        let questionHeight = measureApproval(questionContent, name: "approval-questions")
        questionContent.questions = (0..<4).map { index in
            .init(id: "q\(index)", title: "问题 \(index + 1)", options: (0..<40).map { "选项 \($0 + 1)" })
        }
        let overflowingHeight = measureApproval(questionContent, name: "approval-overflow")
        expect(questionHeight <= 320 && overflowingHeight == questionHeight, "large question sets scroll within a bounded viewport")
        print("Approval measured heights: short=\(shortHeight), narrow=\(narrowHeight), questions=\(questionHeight), overflow=\(overflowingHeight)")
        presenter.present(screen: screen, preferences: preferences, animated: false); settle()
        let extra = model.approvalHeight(width: model.metrics.expandedRect.width - 56)
        expect(extra > 0 && extra < 190 + ActivityIslandListLayout.rowSpacing, "focus approval uses measured card height")
        let focusRow = model.sessions.first { $0.id == model.focusedSessionID }
        let baseStage = ActivityIslandPanelMetrics.stageHeight(rowCount: model.sessions.count,
            focusHeight: ActivityIslandPanelMetrics.focusHeight(for: focusRow))
        expect(abs(model.metrics.expandedRect.height - (baseStage + extra + 72)) < 1,
            "focused approval adds its measured height to stage and chrome")
        let stage = stageScrolls(presenter.surface).first
        expect(stage?.contentView.layer?.masksToBounds == true, "stage scroll clips overflow before footer")
        expect(model.metrics.expandedRect.height <= model.metrics.maximumUsageHeight, "approval expansion remains screen bounded")
        expect(abs(model.metrics.expandedRect.height - (ActivityIslandPanelMetrics.headerHeight + model.metrics.listHeight + ActivityIslandPanelMetrics.footerHeight)) < 0.5,
            "measured task viewport reserves full footer height")
        model.approvalContent = nil; model.focusedSessionID = focusedBeforeApproval
        model.objectWillChange.send(); settle()
        presenter.present(screen: screen, preferences: preferences, animated: false); settle()
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
        expect(stageScrolls(presenter.surface).isEmpty, "empty expanded panel has no placeholder task list")
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
            model.focusedSessionID = model.sessions.first?.id
            model.reduceMotionOverride = false
            visible.present(screen: screen, preferences: preferences, animated: false)
            waitUntil { model.playbackVisible }
            settle(0.05)
            expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                   "visible nonactivating panel preserves foreground application")
            expect(!stageScrolls(visible.surface).isEmpty && model.playbackVisible,
                   "visible focus stage enables playback")
            func effects(_ view: NSView) -> [ActivityStateSmokeMetalView] {
                (view as? ActivityStateSmokeMetalView).map { [$0] } ?? view.subviews.flatMap(effects)
            }
            let effectView = effects(visible.surface).first
            waitUntil { effectView?.displayedProgressPosition != nil }
            print("Visible QA Metal: frame=\(effectView?.frame ?? .zero), paused=\(effectView?.isPaused ?? true), progress=\(effectView?.displayedProgressPosition ?? -1)")
            expect(effectView?.frame.height == ActivityIslandPanelMetrics.focusHeight(for: model.sessions.first) && (effectView?.frame.width ?? 0) > 500,
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
            expect(effects(visible.surface).count == 1, "only focus card mounts a Metal effect; rail stays lightweight")
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
            expect(compactOrbs(visible.surface).isEmpty,
                   "compact and focus mascots use SwiftUI gradient bodies without the old Metal orb")
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
            expect(!model.playbackVisible && effects(visible.surface).allSatisfy { $0.isPaused }, "hidden panel pauses every focus effect")
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
