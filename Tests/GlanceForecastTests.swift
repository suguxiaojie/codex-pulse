import Foundation

@main
enum GlanceForecastTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { print("FAIL: \(message)"); exit(1) }
    }
    static func main() {
        UserDefaults.standard.setVolatileDomain([CountStyle.preferenceKey: "chinese"], forName: UserDefaults.argumentDomain)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(_ used: Int, _ minutes: Int? = 600, _ resetHours: Double = 5) -> RateLimitWindow {
            .init(usedPercent: used, windowDurationMinutes: minutes, resetsAt: now.addingTimeInterval(resetHours * 3_600))
        }
        func forecast(_ w: RateLimitWindow) -> QuotaPaceForecast { .init(window: w, now: now) }
        check(forecast(window(20)) == .lastsUntilReset, "normal pace lasts")
        check(forecast(window(80)) == .exhausts(at: now.addingTimeInterval(4_500)), "fast pace exhausts")
        check(forecast(window(100)) == .exhausted, "exhausted")
        let earlyExhausted = window(100, 600, 9.5)
        check(forecast(earlyExhausted) == .exhausted, "exhausted before one hour")
        check(forecast(earlyExhausted).copy(resetsAt: earlyExhausted.resetsAt, now: now).primary == "额度已用完", "early exhaustion copy")
        check(forecast(.init(usedPercent: 100, windowDurationMinutes: 600, resetsAt: nil)) == .insufficient, "exhausted with missing reset")
        check(forecast(window(100, 600, -1)) == .insufficient, "exhausted with past reset")
        check(forecast(window(100, 600, 0)) == .insufficient, "exhausted at reset")
        check(forecast(window(100, 600, .infinity)) == .insufficient, "exhausted with invalid reset")
        check(forecast(window(0)) == .lastsUntilReset, "unused")
        check(forecast(window(20, 600, 9.5)) == .insufficient, "less than one hour")
        check(forecast(window(0, 600, 9.5)) == .insufficient, "insufficient takes precedence over zero")
        check(forecast(.init(usedPercent: 20, windowDurationMinutes: 600, resetsAt: nil)) == .insufficient, "missing reset")
        check(forecast(window(20, nil)) == .insufficient, "missing duration")
        check(forecast(window(20, 600, -1)) == .insufficient, "past reset")
        check(forecast(window(20, 600, 0)) == .insufficient, "reset now")
        check(forecast(window(50)) == .lastsUntilReset, "exact reset boundary")
        check(forecast(window(10, 600, 9)) == .lastsUntilReset, "one hour boundary")
        for w in [window(-1), window(101), window(20, 0), window(20, -1), window(20, 600, 11), window(20, 600, .infinity)] {
            check(forecast(w) == .insufficient, "invalid input")
        }
        let reset = now.addingTimeInterval(5 * 3_600)
        let cases: [(QuotaPaceForecast, String, String)] = [
            (.lastsUntilReset, "按当前速度，可用到重置", "估算 · 5 小时后重置"),
            (.exhausts(at: now.addingTimeInterval(7_200)), "按当前速度，约 2 小时后用完", "估算 · 5 小时后重置"),
            (.exhausted, "额度已用完", "5 小时后重置"),
            (.insufficient, "数据不足，暂不预测", "5 小时后重置")]
        for (result, primary, secondary) in cases {
            let copy = result.copy(resetsAt: reset, now: now)
            check(copy.primary == primary && copy.secondary == secondary, "forecast copy: \(primary)")
        }
        check(QuotaPaceForecast.exhausts(at: now.addingTimeInterval(172_800)).copy(resetsAt: reset, now: now).primary == "按当前速度，约 2 天后用完", "days copy")
        check(QuotaPaceForecast.insufficient.copy(resetsAt: nil, now: now).secondary == "重置时间未知", "unknown reset copy")
        for (remaining, tone) in [(19, GlanceTone.critical), (20, .tight), (49, .tight), (50, .calm), (100, .calm)] {
            check(GlanceTone(window: window(100 - remaining), forecast: .lastsUntilReset) == tone, "tone \(remaining)")
        }
        check(GlanceTone(window: window(20), forecast: .exhausts(at: now)) == .tight, "fast pace overrides healthy remaining")
        check(GlanceTone(window: window(0), forecast: .exhausted) == .critical, "exhausted tone")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let buckets = GlanceDayStrip.buckets(samples: [.init(date: yesterday, value: 5), .init(date: now, value: 10), .init(date: now.addingTimeInterval(86400), value: 99), .init(date: now, value: -1)], now: now, calendar: calendar)
        check(buckets.count == 7 && buckets.prefix(5).allSatisfy { $0.value == 0 }, "seven days with missing dates zero filled")
        check(buckets.last?.label == "今" && buckets.last?.value == 10, "today and future excluded")
        check(buckets.filter(\.isPeak).count == 1 && buckets.last!.isPeak, "peak marked")
        check(GlanceDayStrip.buckets(samples: [], now: now, calendar: calendar).allSatisfy { $0.value == 0 && !$0.isPeak }, "empty has no peak")
        let ties = GlanceDayStrip.buckets(samples: [.init(date: now, value: 5), .init(date: yesterday, value: 5)], now: now, calendar: calendar)
        check(ties.filter(\.isPeak).count == 2, "tied peaks")
        check(GlanceDayStrip.summaryText(buckets, formatValue: GlanceDayStrip.tokenText) == "今日 10 · 峰值", "today peak summary")
        check(GlanceDayStrip.summaryText(ties, formatValue: GlanceDayStrip.tokenText) == "今日 5 · 峰值", "today tied peak summary")
        let earlierPeak: [GlanceDayStrip.Bucket] = [
            .init(date: yesterday, label: "一", value: 121_000_000, isPeak: true),
            .init(date: now, label: "今", value: 12_300_000, isPeak: false)]
        check(GlanceDayStrip.summaryText(earlierPeak, formatValue: GlanceDayStrip.tokenText) == "峰值 周一 1.21亿 · 今日 1,230万", "earlier peak summary")
        let zeros = GlanceDayStrip.buckets(samples: [], now: now, calendar: calendar)
        check(GlanceDayStrip.summaryText(zeros, formatValue: GlanceDayStrip.tokenText) == "近 7 天暂无用量", "zero summary")
        check(GlanceDayStrip.summaryText([], formatValue: GlanceDayStrip.tokenText) == "近 7 天暂无用量", "empty summary")
        for (value, label) in [(0.0, "0"), (999, "999"), (1_000, "1,000"),
                               (12_300, "1.2万"), (99_900, "10万"), (100_000, "10万"), (121_000, "12.1万"),
                               (1_000_000, "100万"), (12_300_000, "1,230万"), (99_900_000, "9,990万"),
                               (100_000_000, "1亿"), (121_000_000, "1.21亿"),
                               (1_000_000_000, "10亿"), (12_300_000_000, "123亿"),
                               (100_000_000_000, "1,000亿"), (121_000_000_000, "1,210亿")] {
            check(GlanceDayStrip.tokenText(value) == label, "Token units")
        }
        for value in [-1.0, .infinity, .nan] {
            check(GlanceDayStrip.tokenText(value) == "—", "invalid Token value")
            check(GlanceDayStrip.costText(value) == "—", "invalid cost value")
        }
        for (value, label) in [(0.0, "$0"), (67, "$67"), (517, "$517"),
                               (517.4, "$517"), (517.6, "$518"), (999, "$999"),
                               (1_000, "$1.0K"), (1_200, "$1.2K"), (99_900, "$99.9K"),
                               (100_000, "$100K"), (121_000, "$121K"),
                               (1_000_000, "$1.0M"), (1_200_000, "$1.2M"), (99_900_000, "$99.9M"),
                               (100_000_000, "$100M"), (121_000_000, "$121M")] {
            check(GlanceDayStrip.costText(value) == label, "compact cost: \(value)")
        }
        let costBuckets: [GlanceDayStrip.Bucket] = [
            .init(date: yesterday, label: "一", value: 1_200, isPeak: true),
            .init(date: now, label: "今", value: 67.2, isPeak: false)]
        check(GlanceDayStrip.summaryText(costBuckets, formatValue: GlanceDayStrip.costText) == "峰值 周一 $1.2K · 今日 $67", "compact cost summary")
        check(GlanceDayStrip.summaryText(buckets, formatValue: GlanceDayStrip.costText) == "今日 $10 · 峰值", "today cost peak summary")
        check(GlanceDayStrip.summaryText(zeros, formatValue: GlanceDayStrip.costText) == "近 7 天暂无用量", "zero cost summary")
        // Every enabled-module superset must be at least as tall as its subset.
        func preferences(_ mask: Int) -> GlanceContentPreferences {
            .init(showPrimaryQuota: mask & 1 != 0, showCostEstimate: mask & 2 != 0,
                  showCreditBalance: mask & 4 != 0, showDailyTokens: mask & 8 != 0,
                  showThirtyDayTokens: mask & 16 != 0, showTokenActivity: mask & 32 != 0,
                  showResetEntry: mask & 64 != 0, surfaceOpacity: 0.38)
        }
        for mask in 0..<128 {
            let height = preferences(mask).preferredHeight(primaryQuotaWindowCount: 2)
            check(height >= 230 && height <= 806, "height bounded \(mask)")
            for bit in 0..<7 {
                check(preferences(mask | (1 << bit)).preferredHeight(primaryQuotaWindowCount: 2) >= height, "height monotonic \(mask), \(bit)")
            }
        }
        check(preferences(127).preferredHeight(primaryQuotaWindowCount: 1) == 562, "Codex estimate includes new tabs and module gaps")
        check(preferences(127).preferredHeight(primaryQuotaWindowCount: 1, provider: .claude) == 518, "Claude estimate excludes reset row and its gap")
        check(GlanceLayout.preferredHeight(readingHeight: 461, estimatedHeight: 534) == 559, "measured content overrides undersized legacy estimate")
        check(GlanceLayout.preferredHeight(readingHeight: 461.25, estimatedHeight: 534) == 560, "fractional content rounds up")
        check(GlanceLayout.preferredHeight(readingHeight: 900, estimatedHeight: 534) == 806, "oversized content caps panel")
        check(GlanceLayout.readingViewportHeight(panelHeight: 806) == 708, "cap reserves header and footer outside scroll")
        check(GlanceLayout.readingViewportHeight(panelHeight: 559) == 461, "natural height fits the entire reading area")
        check(GlanceLayout.readingViewportHeight(panelHeight: 400) == 302, "short screen still reserves footer")
        for invalid: CGFloat in [0, -1, .nan, .infinity] {
            check(GlanceLayout.preferredHeight(readingHeight: invalid, estimatedHeight: 562) == 562, "invalid measurement retains estimate")
        }
        check(preferences(127).preferredHeight(primaryQuotaWindowCount: 100) == 806, "many windows capped")
        let suite = "GlanceForecastTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(GlanceContentPreferences.load(from: defaults) == .defaults, "defaults preserved")
        let keys = ["glance.content.primaryQuota", "glance.content.costEstimate", "glance.content.creditBalance", "glance.content.dailyTokens", "glance.content.thirtyDayTokens", "glance.content.tokenActivity", "glance.content.resetEntry"]
        for mask in 0..<128 {
            for (bit, key) in keys.enumerated() { defaults.set(mask & (1 << bit) != 0, forKey: key) }
            defaults.set(0.38, forKey: "glance.surfaceOpacity")
            check(GlanceContentPreferences.load(from: defaults) == preferences(mask), "legacy keys \(mask)")
        }
        defaults.set(0.01, forKey: "glance.surfaceOpacity")
        check(GlanceContentPreferences.load(from: defaults).surfaceOpacity == 0.10, "opacity lower bound")
        defaults.set(1.0, forKey: "glance.surfaceOpacity")
        check(GlanceContentPreferences.load(from: defaults).surfaceOpacity == 0.90, "opacity upper bound")
        check(GlanceStripMetric.cost.title == "成本" && GlanceStripMetric.token.title == "Token", "metric tab labels")
        check(GlanceStripMetric.cost.subtitle() == "近 7 天 · 估算，非账单", "cost subtitle")
        check(GlanceStripMetric.token.subtitle() == "近 7 天 · 当前账号本地用量", "Codex Token subtitle")
        check(GlanceStripMetric.token.subtitle(tokenSourceLabel: "本机 Claude 用量") == "近 7 天 · 本机 Claude 用量", "Claude retains local-source boundary")
        for (value, text) in [(0.0, "$0"), (0.04, "$0"), (0.06, "$0.1"), (67, "$67.0"), (517.5, "$517.5"),
                              (999.99, "$1,000.0"), (1_000, "$1,000.0"), (1_862.42, "$1,862.4"), (1_234_567.89, "$1,234,567.9")] {
            check(GlanceDayStrip.fullCostText(value) == text, "full money grouped: \(value)")
        }
        check(GlanceDayStrip.fullCostText(1_862.4256) == "$1,862.4", "detail money uses one decimal")
        for value in [-1.0, Double.nan, Double.infinity] {
            check(GlanceDayStrip.fullCostText(value) == "—", "invalid full money")
        }
        let moneyBuckets: [GlanceDayStrip.Bucket] = [
            .init(date: now, label: "今", value: 1_862.42, isPeak: true),
            .init(date: yesterday, label: "二", value: 0, isPeak: false)]
        check(GlanceDayStrip.costTotalText(moneyBuckets, unpricedDates: [yesterday]) == "≥ $1,862.4", "grouped lower bound")
        check(GlanceDayStrip.costDetailValue(moneyBuckets[0], unpricedDates: []) == "$1,862.4", "grouped tooltip amount")
        providerTests()
        print("Glance forecast tests passed (\(checks) checks)")
    }
    private static func providerTests() {
        let now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        let future = now.addingTimeInterval(7_200)
        let five = ClaudeCodeRateLimits.Window(usedPercent: 70.6, resetsAt: future)
        let week = ClaudeCodeRateLimits.Window(usedPercent: 20.4, resetsAt: future)
        func snapshot(_ limits: ClaudeCodeRateLimits?, statusLine: Bool = true, usage: ClaudeCodeUsageSummary? = nil,
                      calendar: Calendar = .current) -> GlanceClaudeSnapshot {
            .init(limits: limits, usage: usage, statusLineEnabled: statusLine, now: now, calendar: calendar)
        }
        let limits = ClaudeCodeRateLimits(fiveHour: five, sevenDay: week, capturedAt: now)
        let p = snapshot(limits)
        check(p.windows.map(\.windowDurationMinutes) == [300, 10_080], "Claude window durations")
        check(p.windows.map(\.usedPercent) == [71, 20], "Claude percentages rounded")
        check(p.limitingWindow?.windowDurationMinutes == 300, "Claude limiting window")
        check(p.limitingWindow?.resetsAt == future, "Claude reset preserved")
        check(snapshot(.init(fiveHour: nil, sevenDay: week, capturedAt: now)).limitingWindow?.windowDurationMinutes == 10_080, "Claude weekly only")
        check(snapshot(.init(fiveHour: five, sevenDay: nil, capturedAt: now)).windows.count == 1, "Claude five-hour only")
        check(snapshot(limits, statusLine: false).windows.isEmpty, "statusLine disabled hides retained limits")
        check(snapshot(limits, statusLine: false).quotaPlaceholder == "开启 Claude 状态栏后可显示额度", "disabled status copy")
        check(snapshot(nil).quotaPlaceholder == "等待 Claude Code 下一次回复后同步额度", "missing quota copy")
        let stale = snapshot(.init(fiveHour: five, sevenDay: week, capturedAt: now.addingTimeInterval(-601)))
        check(stale.isStale && stale.glowMultiplier == 0.5 && stale.windows.count == 2, "stale quota retained with half glow")
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        check(stale.observationSuffix() == " · 数据于 " + formatter.string(from: now.addingTimeInterval(-601)), "stale observation copy")
        check(!snapshot(.init(fiveHour: five, sevenDay: nil, capturedAt: now.addingTimeInterval(-600))).isStale, "ten-minute boundary")
        check(p.observationSuffix().isEmpty && p.glowMultiplier == 1, "fresh observation")
        check(snapshot(.init(fiveHour: .init(usedPercent: 10, resetsAt: now), sevenDay: nil, capturedAt: now)).windows.isEmpty, "expired quota hidden")
        check(snapshot(.init(fiveHour: .init(usedPercent: .nan, resetsAt: future), sevenDay: nil, capturedAt: now)).windows.isEmpty, "invalid percentage hidden")
        check(snapshot(.init(fiveHour: five, sevenDay: nil, capturedAt: now.addingTimeInterval(61))).windows.isEmpty, "future observation hidden")
        for saved in ["codex", "claude", "invalid"] {
            check(GlanceProvider.resolve(saved, claudeEnabled: false) == .codex, "disabled provider fallback")
        }
        check(GlanceProvider.resolve("claude", claudeEnabled: true) == .claude, "saved Claude selected")
        check(GlanceProvider.resolve("invalid", claudeEnabled: true) == .codex, "invalid provider fallback")
        let day = ISO8601DateFormatter().date(from: "2026-10-21T00:00:00Z")!
        let previous = day.addingTimeInterval(-86_400)
        let usage = ClaudeCodeUsageSummary(days: [
            .init(date: previous, tokens: 5, estimatedCost: 1.25),
            .init(date: day, tokens: 10, estimatedCost: nil)], lifetimeTokens: 500, complete: true, fileCount: 1, updatedAt: now.addingTimeInterval(10))
        for zone in ["Asia/Shanghai", "America/New_York"] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
            let local = GlanceClaudeSnapshot.localDate(day, calendar: calendar)!
            check(calendar.component(.day, from: local) == 21 && calendar.component(.weekday, from: local) == 4, "UTC day mapped to local Wednesday: \(zone)")
            let projected = snapshot(limits, usage: usage, calendar: calendar)
            let strip = GlanceDayStrip.buckets(samples: projected.tokenSamples, now: now, calendar: calendar)
            check(strip.count == 7 && strip.prefix(5).allSatisfy { $0.value == 0 }, "Claude sparse days filled: \(zone)")
            check(strip.last?.value == 10 && strip.last?.label == "今", "Claude today position: \(zone)")
            check(projected.todayTokens == 10 && projected.monthlyTokens == 15 && projected.lifetimeTokens == 500, "Claude token scopes")
            check(projected.unpricedDates == [local], "Claude unpriced date marker")
            let costStrip = GlanceDayStrip.buckets(samples: projected.costSamples, now: now, calendar: calendar)
            check(costStrip.last?.value == 0, "unknown cost day has zero numeric height")
            check(costStrip.dropLast().last?.value == 1.25, "known cost days retained")
            check(GlanceDayStrip.costTotalText(costStrip, unpricedDates: projected.unpricedDates) == "≥ $1.2", "unknown cost total is known lower bound")
            check(GlanceDayStrip.costDetailValue(costStrip.last!, unpricedDates: projected.unpricedDates) == "金额未知（部分模型未计价）", "unknown cost detail")
            check(GlanceDayStrip.costDetailValue(costStrip.dropLast().last!, unpricedDates: projected.unpricedDates) == "$1.2", "known cost detail uses one decimal")
            check(GlanceDayStrip.costSummaryText(costStrip, unpricedDates: projected.unpricedDates) == "峰值 周二 $1 · 今日 金额未知", "peak excludes unknown today")
            check(GlanceDayStrip.summaryText(strip, formatValue: GlanceDayStrip.tokenText) == "今日 10 · 峰值", "unpriced day still contributes to Token peak")
            check(projected.updatedAt == usage.updatedAt, "latest snapshot timestamp")
        }
        let mixedCosts: [GlanceDayStrip.Bucket] = [
            .init(date: previous, label: "二", value: 999, isPeak: true),
            .init(date: day, label: "今", value: 12.5, isPeak: false)]
        check(GlanceDayStrip.costTotalText(mixedCosts, unpricedDates: [previous]) == "≥ $12.5", "unknown values never contribute to total")
        check(GlanceDayStrip.costSummaryText(mixedCosts, unpricedDates: [previous]) == "今日 $12 · 峰值", "peak recomputed from known days")
        check(GlanceDayStrip.costTotalText(mixedCosts, unpricedDates: []) == "$1,011.5", "fully priced total unchanged")
        check(GlanceDayStrip.costTotalText(mixedCosts, unpricedDates: [day.addingTimeInterval(-864_000)]) == "$1,011.5", "unknown outside strip does not mark total")
        check(GlanceDayStrip.costTotalText(mixedCosts, unpricedDates: [previous, day]) == "≥ $0", "all unknown lower bound")
        check(GlanceDayStrip.costSummaryText(mixedCosts, unpricedDates: [previous, day]) == "近 7 天金额未知", "all unknown is not no usage")
        let zeroCosts = mixedCosts.map { GlanceDayStrip.Bucket(date: $0.date, label: $0.label, value: 0, isPeak: false) }
        check(GlanceDayStrip.costSummaryText(zeroCosts, unpricedDates: [day]) == "已知成本 $0 · 今日 金额未知", "known zero plus unknown does not claim no usage")
        check(GlanceDayStrip.costSummaryText(zeroCosts, unpricedDates: []) == "近 7 天暂无用量", "fully known zeros unchanged")
        check(!snapshot(nil).usageReady, "missing usage pending")
        let incomplete = ClaudeCodeUsageSummary(days: usage.days, lifetimeTokens: 500, complete: false, fileCount: 1, updatedAt: now)
        check(!snapshot(limits, usage: incomplete).usageReady, "partial scan pending")
        for provider in GlanceProvider.allCases {
            func preferences(_ mask: Int) -> GlanceContentPreferences {
                .init(showPrimaryQuota: mask & 1 != 0, showCostEstimate: mask & 2 != 0,
                      showCreditBalance: mask & 4 != 0, showDailyTokens: mask & 8 != 0,
                      showThirtyDayTokens: mask & 16 != 0, showTokenActivity: mask & 32 != 0,
                      showResetEntry: mask & 64 != 0, surfaceOpacity: 0.38)
            }
            for mask in 0..<128 {
                let height = preferences(mask).preferredHeight(primaryQuotaWindowCount: 2, provider: provider)
                check(height >= 230 && height <= 806, "provider height bounded")
                for bit in 0..<7 {
                    check(preferences(mask | (1 << bit)).preferredHeight(primaryQuotaWindowCount: 2, provider: provider) >= height, "provider height monotonic")
                }
                if provider == .claude {
                    check(preferences(mask ^ 4 ^ 64).preferredHeight(primaryQuotaWindowCount: 2, provider: provider) == height, "Claude ignores Credits/reset height")
                }
            }
        }
    }

}
