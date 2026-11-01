import Foundation

extension IslandUsagePresentation {
    static func grok(usage: GrokUsageSummary?, quota: GrokQuotaSnapshot?, failed: Bool, status: String,
                     now: Date = Date(), calendar: Calendar = .current) -> Self {
        let available = quota?.isAvailable(at: now) == true
        let stale = failed || quota?.isStale(at: now) == true
        let freshness: QuotaFreshness = available ? (stale ? .stale(observedAt: quota!.capturedAt) : .current) : .unavailable
        let today = calendar.startOfDay(for: now)
        let lower = calendar.date(byAdding: .day, value: -29, to: today)!
        let byDate = Dictionary((usage?.days ?? []).map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        let days = (0..<30).map { index -> IslandDashboardCost.Day in
            let date = calendar.date(byAdding: .day, value: index - 29, to: today)!
            if let day = byDate[date] { return .init(date: date, tokens: day.tokens, cost: day.cost) }
            return .init(date: date, tokens: usage?.complete == true ? 0 : nil, cost: usage?.complete == true ? 0 : nil)
        }
        let recorded = (usage?.days ?? []).filter { $0.date >= lower && $0.date <= today }
        let known = recorded.compactMap(\.cost)
        let total = known.isEmpty ? (recorded.isEmpty && usage?.complete == true ? 0.0 : nil) : known.reduce(0, +)
        let incomplete = recorded.contains { $0.cost == nil } || usage?.complete != true
        let chart = IslandDashboardCost(claudeDays: days, latestRecordedDate: recorded.last?.date)
        return .init(provider: .grok,
            quotas: [.init(title: quota?.title ?? "订阅额度", remainingPercent: available ? quota?.remainingPercent : nil,
                usedPercent: available ? quota.map { Int($0.usedPercent.rounded()) } : nil,
                resetsAt: available ? quota?.resetsAt : nil, freshness: freshness)],
            metrics: [.init(title: "最近一天 Tokens", tokens: usage == nil ? nil : usage?.days.last?.tokens ?? 0, dateTag: dateTag(usage?.days.last?.date, now: now)),
                .init(title: "30 天 Tokens", tokens: usage == nil ? nil : recorded.reduce(0) { GrokJSON.add($0, $1.tokens) }, dateTag: nil),
                .init(title: "累计 Tokens", tokens: usage?.lifetimeTokens, dateTag: nil)],
            cost: .init(title: "Grok 本机报告成本", total: total, totalIsLowerBound: incomplete, note: incomplete ? "部分记录或金额未知" : "最近 30 天",
                days: days, latest: chart.latest, latestDateTag: dateTag(chart.latest?.date, now: now), maximum: chart.maximum,
                helpText: "本机已记录轮次的 CLI 报告成本，按原始 prompt ID 去重；不等于订阅账单，未知金额不算零。",
                accessibilityHint: "Grok 本机报告成本，非订阅账单"),
            source: .grok(plan: quota?.plan ?? "Grok CLI", shared: quota?.sharedPool, prepaidCents: available && !stale ? quota?.prepaidCents : nil),
            activity: (usage?.days ?? []).map { .init(date: $0.date, tokens: $0.tokens) }, lifetimeTokens: usage?.lifetimeTokens,
            activityHelp: "本机 Grok 轮次记录，按本地日期统计；fork 继承记录去重，子 Agent 汇总不重复相加。",
            statusLine: (failed || !available ? status + " · " : "") + "官方额度 · 本机历史不代表当前账号账单" + (usage?.complete == false ? " · 部分记录" : ""),
            updatedAt: quota?.capturedAt ?? usage?.updatedAt, supportsReset: false)
    }
}
