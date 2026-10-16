// Adapted from QuotaView f779531 EstimatedCostChartModel (MIT), Copyright (c) 2026 Duoasa.
import Foundation

struct IslandDashboardCost {
    struct Day: Identifiable {
        let date: Date
        let tokens: Int?
        let cost: Double?
        var id: Date { date }
    }
    // QuotaView's aggregate-token proxy, NOT the model-specific API pricing table.
    static let usdPerMillionTokens = 0.50
    let days: [Day]
    let official: Bool
    var total: Double? {
        let known = days.compactMap(\.cost)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
    var latest: Day? { days.last { $0.tokens != nil } }
    var maximum: Double { max(0.001, days.compactMap(\.cost).max() ?? 0) }
    init(account: AccountUsageSnapshot?, local: CostScopeSnapshot, now: Date = Date()) {
        official = account != nil
        if let account {
            // AccountUsageSnapshot preserves UTC day labels on the local calendar.
            let utc = DateFormatter(); utc.locale = Locale(identifier: "en_US_POSIX"); utc.dateFormat = "yyyy-MM-dd"; utc.timeZone = TimeZone(secondsFromGMT: 0)
            let localDate = DateFormatter(); localDate.locale = utc.locale; localDate.dateFormat = "yyyy-MM-dd"
            let today = localDate.date(from: utc.string(from: now)) ?? Calendar.current.startOfDay(for: now)
            let counts = Dictionary((account.days ?? []).map { ($0.date, $0.tokens) }, uniquingKeysWith: max)
            days = (0..<30).compactMap { index in
                guard let date = Calendar.current.date(byAdding: .day, value: index - 29, to: today) else { return nil }
                let tokens = counts[date]
                return Day(date: date, tokens: tokens, cost: tokens.map { Double($0) / 1_000_000 * Self.usdPerMillionTokens })
            }
        } else {
            let counts = Dictionary(local.usage.activity.map { ($0.date, $0.tokens) }, uniquingKeysWith: max)
            days = local.costActivity.suffix(30).map { Day(date: $0.date, tokens: counts[$0.date], cost: $0.dollars) }
        }
    }
}
