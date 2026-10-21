import Foundation

/// A single, value-only projection shared by both usage providers.
struct IslandUsagePresentation: Equatable {
    enum QuotaFreshness: Equatable {
        case current, stale(observedAt: Date), unavailable
        var isStale: Bool { if case .stale = self { return true }; return false }
        func observationLabel(now: Date) -> String? {
            guard case .stale(let date) = self else { return nil }
            let minutes = max(1, Int(now.timeIntervalSince(date) / 60))
            return minutes < 60 ? "\(minutes) 分钟前观测" : "\(minutes / 60) 小时前观测"
        }
    }
    struct Quota: Equatable {
        let title: String
        let remainingPercent: Int?
        let usedPercent: Int?
        let resetsAt: Date?
        let freshness: QuotaFreshness
    }
    struct Metric: Equatable {
        let title: String
        let tokens: Int?
        let dateTag: String?
    }
    struct Cost: Equatable {
        let title: String
        let total: Double?
        let totalIsLowerBound: Bool
        let note: String
        let days: [IslandDashboardCost.Day]
        let latest: IslandDashboardCost.Day?
        let latestDateTag: String?
        let maximum: Double
        let helpText: String
        let accessibilityHint: String
        func missingLabel(for day: IslandDashboardCost.Day) -> String {
            day.tokens == nil ? "未扫描" : "未定价"
        }
    }
    enum Source: Equatable {
        case codex(planName: String, creditBalance: String?, resetCount: Int?)
        case claude
    }
    let provider: IslandUsageProvider
    let quotas: [Quota]
    let metrics: [Metric]
    let cost: Cost
    let source: Source
    let activity: [DailyTokenActivity]
    let lifetimeTokens: Int?
    let activityHelp: String
    let statusLine: String?
    let updatedAt: Date?
    let supportsReset: Bool

    static func dateTag(_ date: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let date, !calendar.isDate(date, inSameDayAs: now) else { return nil }
        return "\(calendar.component(.month, from: date)) 月 \(calendar.component(.day, from: date)) 日"
    }

    static func claudeQuota(title: String, window: ClaudeCodeRateLimits.Window?, capturedAt: Date?,
                            statusLineEnabled: Bool, now: Date) -> Quota {
        var freshness = QuotaFreshness.unavailable
        if statusLineEnabled, let window, let capturedAt,
           window.resetsAt.map({ $0 > now }) ?? true {
            let age = now.timeIntervalSince(capturedAt)
            if (-60...300).contains(age) { freshness = .current }
            else if age > 300, window.resetsAt != nil { freshness = .stale(observedAt: capturedAt) }
        }
        let available = freshness != .unavailable
        return .init(title: title, remainingPercent: available ? window?.remainingPercent : nil,
                     usedPercent: available ? window.map { 100 - $0.remainingPercent } : nil,
                     resetsAt: available ? window?.resetsAt : nil, freshness: freshness)
    }

    static func codex(quotaState: QuotaState, accountUsage: AccountUsageSnapshot?, usageCost: CostSnapshot,
                      resetCredits: QuotaResetCreditSummary?, now: Date = Date()) -> Self {
        let scope = usageCost.aggregate
        let ready = usageCost.updatedAt != .distantPast
        let bucket = quotaState.buckets.first { $0.id == "codex" }
        let windows = bucket?.windows ?? []
        let quotas = windows.isEmpty ? [Quota(title: "额度剩余", remainingPercent: nil, usedPercent: nil, resetsAt: nil, freshness: .unavailable)] : windows.map {
            Quota(title: $0.windowLabel, remainingPercent: $0.remainingPercent, usedPercent: $0.usedPercent,
                  resetsAt: $0.resetsAt, freshness: .current)
        }
        let chart = IslandDashboardCost(account: accountUsage, local: scope, now: now)
        var labelNow = now
        if accountUsage != nil {
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
            labelNow = Calendar.current.date(from: utc.dateComponents([.year, .month, .day], from: now)) ?? now
        }
        let recentDate = accountUsage != nil ? accountUsage?.days?.last?.date : scope.usage.activity.last?.date
        return Self(provider: .codex, quotas: quotas, metrics: [
            .init(title: "最近一天 Tokens", tokens: accountUsage.map { $0.recentTokens } ?? (ready ? scope.usage.day.tokens : nil), dateTag: dateTag(recentDate, now: labelNow)),
            .init(title: "30 天 Tokens", tokens: accountUsage.map { $0.monthlyTokens } ?? (ready ? scope.usage.month.tokens : nil), dateTag: nil),
            .init(title: "累计 Tokens", tokens: accountUsage.map { $0.lifetimeTokens } ?? scope.lifetimeTokens, dateTag: nil)
        ], cost: .init(title: chart.official ? "官方用量折算" : "本地模型计价", total: chart.total,
            totalIsLowerBound: false, note: "最近 30 天", days: chart.days, latest: chart.latest,
            latestDateTag: dateTag(chart.latest?.date, now: labelNow), maximum: chart.maximum,
            helpText: chart.official ? "与 QuotaView 相同：当前账号官方 UTC 每日 Token × $0.50／百万；统一折算，不是实际模型账单。" : "官方汇总不可用：回退本机全部账号日志，按模型输入／输出／缓存费率估算。",
            accessibilityHint: chart.official ? "当前账号官方 Token 按每百万 0.50 美元统一估算" : "本机全部账号模型计价估算"),
            source: .codex(planName: OpenAIPlanDisplayName.resolve(bucket?.planType) ?? "—", creditBalance: bucket?.creditBalance, resetCount: resetCredits?.availableCount),
            activity: accountUsage.map { ($0.days ?? []).map { DailyTokenActivity(date: $0.date, tokens: $0.tokens) } } ?? scope.usage.activity,
            lifetimeTokens: accountUsage.map { $0.lifetimeTokens } ?? scope.lifetimeTokens,
            activityHelp: accountUsage != nil ? "当前账号官方用量，按 UTC 日期统计。" : "官方汇总不可用，显示本机全部账号的近 180 天日志。",
            statusLine: IslandFloatingQuotaPeriods.current(quotaState) ? nil : bucket == nil ? "额度暂不可用，等待刷新" : "额度显示上次数据，等待刷新",
            updatedAt: ready ? usageCost.updatedAt : nil, supportsReset: true)
    }

    static func claude(usage: ClaudeCodeUsageSummary?, limits: ClaudeCodeRateLimits?, statusLineEnabled: Bool,
                       now: Date = Date(), calendar: Calendar = .current) -> Self {
        let value = IslandClaudeUsage(usage: usage, limits: limits, statusLineEnabled: statusLineEnabled, now: now, calendar: calendar)
        let quotas = [claudeQuota(title: "5 小时额度", window: limits?.fiveHour, capturedAt: limits?.capturedAt, statusLineEnabled: statusLineEnabled, now: now),
                      claudeQuota(title: "每周额度", window: limits?.sevenDay, capturedAt: limits?.capturedAt, statusLineEnabled: statusLineEnabled, now: now)]
        let chart = value.cost
        let recordedDates = Set(value.activity.map(\.date))
        let recorded = chart.days.filter { recordedDates.contains($0.date) }
        let known = recorded.compactMap(\.cost)
        let total: Double? = known.isEmpty ? (recorded.isEmpty && usage?.complete == true ? 0 : nil) : known.reduce(0, +)
        let lowerBound = chart.days.contains { $0.cost == nil }
        var status = !statusLineEnabled ? "Claude 官方额度采集未开启 · 历史为本机记录" : quotas.allSatisfy { $0.freshness == .unavailable } ? "Claude 额度等待状态栏数据 · 历史为本机记录" : "Claude 官方额度 · Token 与成本为本机全部记录"
        if usage?.complete == false { status += " · 正在增量扫描 · 当前为部分记录" }
        return Self(provider: .claude, quotas: quotas, metrics: [
            .init(title: "最近一天 Tokens", tokens: value.recentTokens, dateTag: dateTag(value.activity.last?.date, now: now, calendar: calendar)),
            .init(title: "30 天 Tokens", tokens: value.monthlyTokens, dateTag: nil),
            .init(title: "累计 Tokens", tokens: value.lifetimeTokens, dateTag: nil)
        ], cost: .init(title: "Claude 本地模型计价", total: total, totalIsLowerBound: lowerBound,
            note: usage?.complete == false ? "扫描中 · 部分记录" : lowerBound ? "含未定价模型" : "最近 30 天",
            days: chart.days, latest: chart.latest, latestDateTag: dateTag(chart.latest?.date, now: now, calendar: calendar), maximum: chart.maximum,
            helpText: "本机全部 Claude 记录，按模型公开标准费率估算；未知模型价格保留未知，非订阅账单。不含网页搜索等按次计费。",
            accessibilityHint: "Claude 本机模型计价，非账单"), source: .claude, activity: value.activity,
            lifetimeTokens: value.lifetimeTokens, activityHelp: "本机全部 Claude 会话，按日志所属的本地日期统计；累计模式包含可读取的历史。",
            statusLine: status, updatedAt: value.updatedAt, supportsReset: false)
    }
}
