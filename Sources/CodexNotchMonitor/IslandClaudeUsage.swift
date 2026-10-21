import Foundation

/// Adapts Claude's UTC-encoded local day labels to the island's local calendar.
/// Codex's existing account/cost data never participates in this projection.
struct IslandClaudeUsage {
    let fiveHour: RateLimitWindow?
    let weekly: RateLimitWindow?
    let recentTokens: Int?
    let monthlyTokens: Int?
    let lifetimeTokens: Int?
    let activity: [DailyTokenActivity]
    let cost: IslandDashboardCost
    let updatedAt: Date?
    let complete: Bool

    init(usage: ClaudeCodeUsageSummary?, limits: ClaudeCodeRateLimits?,
         statusLineEnabled: Bool, now: Date = Date(), calendar: Calendar = .current) {
        func window(_ value: ClaudeCodeRateLimits.Window?, minutes: Int) -> RateLimitWindow? {
            let quota = IslandUsagePresentation.claudeQuota(title: "", window: value, capturedAt: limits?.capturedAt,
                statusLineEnabled: statusLineEnabled, now: now)
            guard let used = quota.usedPercent else { return nil }
            return .init(usedPercent: used, windowDurationMinutes: minutes, resetsAt: quota.resetsAt)
        }
        fiveHour = window(limits?.fiveHour, minutes: 300)
        weekly = window(limits?.sevenDay, minutes: 10_080)
        let today = calendar.startOfDay(for: now)
        let lower = calendar.date(byAdding: .day, value: -29, to: today)!
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = (usage?.days ?? []).compactMap { day -> IslandDashboardCost.Day? in
            guard let date = calendar.date(from: utc.dateComponents([.year, .month, .day], from: day.date)),
                  date <= today else { return nil }
            return .init(date: date, tokens: Int(clamping: day.tokens), cost: day.estimatedCost)
        }.sorted { $0.date < $1.date }
        func sum(_ values: [Int]) -> Int {
            values.reduce(0) { result, value in
                let added = result.addingReportingOverflow(value)
                return added.overflow ? Int.max : added.partialValue
            }
        }
        recentTokens = usage == nil ? nil : days.last?.tokens ?? 0
        monthlyTokens = usage == nil ? nil : sum(days.filter { $0.date >= lower }.compactMap(\.tokens))
        lifetimeTokens = usage == nil ? nil : sum(days.compactMap(\.tokens))
        activity = days.map { .init(date: $0.date, tokens: $0.tokens ?? 0) }
        updatedAt = usage?.updatedAt
        complete = usage?.complete == true
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        let fullMonth = (0..<30).compactMap { index -> IslandDashboardCost.Day? in
            guard let date = calendar.date(byAdding: .day, value: index - 29, to: today) else { return nil }
            if let day = byDate[date] { return day }
            return .init(date: date, tokens: usage?.complete == true ? 0 : nil,
                         cost: usage?.complete == true ? 0 : nil)
        }
        cost = .init(claudeDays: fullMonth, latestRecordedDate: days.last?.date)
    }
}
