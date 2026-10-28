import Foundation

// Frozen pre-incremental summary implementation for differential regression tests.
enum CostSummaryReference {
    static func summarize(
        _ events: [TokenUsageEvent],
        projectNames: [String: String],
        accountContext: UsageAccountContext,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeActivity: Bool = true
    ) -> CostSnapshot {
        let knownAccountIDs = Set(accountContext.accounts.map(\.id))
        let aggregate = summarizeScope(
            events,
            projectNames: projectNames,
            now: now,
            calendar: calendar,
            includeActivity: includeActivity,
            include: { _ in true }
        )
        let byAccount = Dictionary(uniqueKeysWithValues: accountContext.accounts.map { account in
            (account.id, summarizeScope(
                events,
                projectNames: projectNames,
                now: now,
                calendar: calendar,
                includeActivity: includeActivity,
                include: { event in
                    accountContext.accountID(for: event.sessionID, at: event.timestamp) == account.id
                }
            ))
        })
        let unknownAccount = summarizeScope(
            events,
            projectNames: projectNames,
            now: now,
            calendar: calendar,
            includeActivity: includeActivity,
            include: { event in
                guard let accountID = accountContext.accountID(
                    for: event.sessionID,
                    at: event.timestamp
                ) else { return true }
                return !knownAccountIDs.contains(accountID)
            }
        )
        return CostSnapshot(
            aggregate: aggregate,
            byAccount: byAccount,
            unknownAccount: unknownAccount,
            updatedAt: now
        )
    }

    private static func summarizeScope(
        _ events: [TokenUsageEvent],
        projectNames: [String: String],
        now: Date,
        calendar: Calendar,
        includeActivity: Bool,
        include: (TokenUsageEvent) -> Bool
    ) -> CostScopeSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let monthStart = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        let activityStart = calendar.date(byAdding: .day, value: -179, to: todayStart)
            ?? monthStart
        let earliestRelevantDate = includeActivity ? activityStart : monthStart
        var today = CostTotals(series: Array(repeating: 0, count: 24))
        var week = CostTotals(series: Array(repeating: 0, count: 7))
        var month = CostTotals(series: Array(repeating: 0, count: 30))
        var providerTotals = Dictionary(uniqueKeysWithValues: CostProvider.allCases.map {
            ($0, ProviderCostTotals(
                provider: $0,
                today: CostTotals(),
                week: CostTotals(),
                month: CostTotals()
            ))
        })
        var unknown = Set<String>()
        var estimatedAliases: [String: String] = [:]
        var costByDay: [Date: Double] = [:]
        let orderedEvents = events.sorted { $0.timestamp < $1.timestamp }
        // If the month begins with an internal task, the first normal model is
        // still a better fallback than pretending the internal route has its
        // own public price.
        var currentPrimaryModel = orderedEvents.first(where: {
            !ModelPricing.isInternalAutomaticModel($0.model) &&
            ModelPricing.resolvedRates(for: $0.model) != nil
        })?.model

        for event in orderedEvents where event.timestamp >= earliestRelevantDate {
            if !ModelPricing.isInternalAutomaticModel(event.model),
               ModelPricing.resolvedRates(for: event.model) != nil {
                currentPrimaryModel = event.model
            }
            let billingModel = ModelPricing.billingModel(
                for: event.model,
                currentPrimaryModel: currentPrimaryModel
            )
            guard include(event) else { continue }
            if billingModel != event.model {
                estimatedAliases[event.model] = billingModel
            }
            let cost = estimatedCost(event, billingModel: billingModel)
            if cost == nil { unknown.insert(event.model) }
            if includeActivity {
                let day = calendar.startOfDay(for: event.timestamp)
                costByDay[day, default: 0] += cost ?? 0
            }

            if event.timestamp >= monthStart {
                add(event, cost: cost ?? 0, to: &month)
                let day = calendar.dateComponents([.day], from: monthStart, to: event.timestamp).day ?? 0
                if month.series.indices.contains(day) { month.series[day] += cost ?? 0 }
            }

            if event.timestamp >= weekStart {
                add(event, cost: cost ?? 0, to: &week)
                let day = calendar.dateComponents([.day], from: weekStart, to: event.timestamp).day ?? 0
                if week.series.indices.contains(day) { week.series[day] += cost ?? 0 }
            }

            if var item = providerTotals[event.provider] {
                if event.timestamp >= monthStart { add(event, cost: cost ?? 0, to: &item.month) }
                if event.timestamp >= weekStart { add(event, cost: cost ?? 0, to: &item.week) }
                if event.timestamp >= todayStart { add(event, cost: cost ?? 0, to: &item.today) }
                providerTotals[event.provider] = item
            }
            if event.timestamp >= todayStart {
                add(event, cost: cost ?? 0, to: &today)
                let hour = calendar.component(.hour, from: event.timestamp)
                if today.series.indices.contains(hour) { today.series[hour] += cost ?? 0 }
            }
        }
        return CostScopeSnapshot(
            today: today,
            week: week,
            month: month,
            providers: CostProvider.allCases.compactMap { providerTotals[$0] },
            unknownModels: unknown.sorted(),
            estimatedModelAliases: estimatedAliases,
            usage: summarizeUsage(
                events.filter(include),
                now: now,
                calendar: calendar,
                projectNames: projectNames,
                includeActivity: includeActivity
            ),
            costActivity: includeActivity
                ? dailyCostActivity(costByDay, now: now, calendar: calendar)
                : [],
            lifetimeTokens: includeActivity ? events.filter { include($0) && $0.timestamp <= now }.reduce(0) { total, event in
                [event.input, event.output, event.cacheCreate, event.cacheRead].reduce(total) { sum, count in
                    let next = sum.addingReportingOverflow(max(0, count))
                    return next.overflow ? Int.max : next.partialValue
                }
            } : nil
        )
    }

    private static func dailyCostActivity(
        _ dollarsByDay: [Date: Double],
        now: Date,
        calendar: Calendar
    ) -> [DailyCostActivity] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -179, to: today) ?? today
        return (0..<180).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return DailyCostActivity(
                date: date,
                dollars: dollarsByDay[date, default: 0]
            )
        }
    }

    private static func summarizeUsage(
        _ events: [TokenUsageEvent],
        now: Date,
        calendar: Calendar,
        projectNames: [String: String],
        includeActivity: Bool
    ) -> UsageSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let monthStart = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        let quarterStart = calendar.date(byAdding: .day, value: -89, to: todayStart) ?? todayStart
        return UsageSnapshot(
            day: usageTotals(events, from: todayStart, seriesCount: 24, projectNames: projectNames) { event in
                calendar.component(.hour, from: event.timestamp)
            },
            week: usageTotals(events, from: weekStart, seriesCount: 7, projectNames: projectNames) { event in
                max(0, min(6, calendar.dateComponents([.day], from: weekStart, to: event.timestamp).day ?? 0))
            },
            month: usageTotals(events, from: monthStart, seriesCount: 30, projectNames: projectNames) { event in
                max(0, min(29, calendar.dateComponents([.day], from: monthStart, to: event.timestamp).day ?? 0))
            },
            quarter: usageTotals(events, from: quarterStart, seriesCount: 90, projectNames: projectNames) { event in
                max(0, min(89, calendar.dateComponents([.day], from: quarterStart, to: event.timestamp).day ?? 0))
            },
            activity: includeActivity
                ? dailyTokenActivity(events, now: now, calendar: calendar)
                : [],
            activityIsReady: includeActivity
        )
    }

    private static func dailyTokenActivity(
        _ events: [TokenUsageEvent],
        now: Date,
        calendar: Calendar
    ) -> [DailyTokenActivity] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -179, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var tokensByDay: [Date: Int] = [:]
        for event in events where event.timestamp >= start && event.timestamp < end {
            let day = calendar.startOfDay(for: event.timestamp)
            tokensByDay[day, default: 0] += event.input
                + event.output
                + event.cacheCreate
                + event.cacheRead
        }
        return (0..<180).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return DailyTokenActivity(date: date, tokens: tokensByDay[date, default: 0])
        }
    }

    private static func usageTotals(
        _ events: [TokenUsageEvent],
        from start: Date,
        seriesCount: Int,
        projectNames: [String: String],
        bucket: (TokenUsageEvent) -> Int
    ) -> UsageTotals {
        let filtered = events.filter { $0.timestamp >= start }
        var result = UsageTotals(series: Array(repeating: 0, count: seriesCount))
        var sessions = Set<String>()
        var projectSessions: [String: Set<String>] = [:]
        var projectTokens: [String: Int] = [:]
        for event in filtered {
            let cache = event.cacheCreate + event.cacheRead
            let total = event.input + event.output + cache
            result.tokens += total
            result.inputTokens += event.input
            result.outputTokens += event.output
            result.cacheTokens += cache
            sessions.insert(event.sessionID)
            projectSessions[event.projectPath, default: []].insert(event.sessionID)
            projectTokens[event.projectPath, default: 0] += total
            let index = bucket(event)
            if result.series.indices.contains(index) { result.series[index] += Double(total) }
        }
        result.sessionCount = sessions.count
        result.projectCount = projectTokens.count
        result.projects = projectTokens.map { path, tokens in
            let url = URL(fileURLWithPath: path)
            let fallbackName = path == "未归类" ? path : (url.lastPathComponent.isEmpty ? path : url.lastPathComponent)
            return ProjectUsage(
                name: projectNames[path] ?? fallbackName,
                path: path,
                tokens: tokens,
                sessionCount: projectSessions[path]?.count ?? 0
            )
        }.sorted {
            $0.tokens == $1.tokens ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.tokens > $1.tokens
        }
        return result
    }

    private static func add(_ event: TokenUsageEvent, cost: Double, to total: inout CostTotals) {
        total.dollars += cost
        total.inputTokens += event.input
        total.outputTokens += event.output
        total.cacheTokens += event.cacheCreate + event.cacheRead
        total.tokens += event.input + event.output + event.cacheCreate + event.cacheRead
    }

    private static func estimatedCost(_ event: TokenUsageEvent, billingModel: String) -> Double? {
        guard let rate = ModelPricing.resolvedRates(for: billingModel) else { return nil }
        let multipliers = ModelPricing.multipliers(
            for: billingModel,
            totalInputTokens: event.input + event.cacheRead
        )
        return (Double(event.input) * rate.inputPerMillion * multipliers.inputAndCache +
                Double(event.output) * rate.outputPerMillion * multipliers.output +
                Double(event.cacheCreate) * rate.cacheCreationPerMillion * multipliers.inputAndCache +
                Double(event.cacheRead) * rate.cacheReadPerMillion * multipliers.inputAndCache) / 1_000_000
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

}
