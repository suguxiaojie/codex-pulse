// Adapted from QuotaView f779531 AccountUsageResponse / CurrentCodexPresentationProjector (MIT).
// Copyright (c) 2026 Duoasa. Retain only aggregate counts, never threadUsage content.
import Foundation
import CoreFoundation

struct AccountUsageSnapshot: Equatable {
    struct Day: Equatable { let date: Date; let tokens: Int }
    let lifetimeTokens: Int?
    let days: [Day]?
    let updatedAt: Date

    static func parse(_ response: [String: Any], now: Date = Date()) -> Self? {
        guard let summary = response["summary"] as? [String: Any] else { return nil }
        func count(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            guard double.isFinite, double >= 0, double < Double(Int.max), double.rounded() == double else { return nil }
            return number.intValue
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        // Preserve the server's UTC date label on the local calendar grid.
        let utc = DateFormatter(); utc.locale = formatter.locale; utc.timeZone = TimeZone(secondsFromGMT: 0); utc.dateFormat = "yyyy-MM-dd"
        let today = formatter.date(from: utc.string(from: now)) ?? now
        let rawDays = response["dailyUsageBuckets"] as? [[String: Any]]
        var byDate: [Date: Int] = [:]
        for item in rawDays ?? [] {
            guard let label = item["startDate"] as? String, let date = formatter.date(from: label),
                  formatter.string(from: date) == label, date <= today, let tokens = count(item["tokens"]) else { continue }
            byDate[date] = max(byDate[date] ?? 0, tokens)
        }
        let lifetime = count(summary["lifetimeTokens"])
        guard lifetime != nil || rawDays != nil else { return nil }
        return .init(lifetimeTokens: lifetime, days: rawDays.map { _ in byDate.map { Day(date: $0.key, tokens: $0.value) }.sorted { $0.date < $1.date } }, updatedAt: now)
    }
    var recentTokens: Int? { days?.last?.tokens }
    var monthlyTokens: Int? {
        guard let days else { return nil }
        let utc = DateFormatter(); utc.locale = Locale(identifier: "en_US_POSIX"); utc.timeZone = TimeZone(secondsFromGMT: 0); utc.dateFormat = "yyyy-MM-dd"
        let local = DateFormatter(); local.locale = utc.locale; local.dateFormat = "yyyy-MM-dd"
        let today = local.date(from: utc.string(from: updatedAt)) ?? updatedAt
        let start = Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today
        return days.filter { $0.date >= start && $0.date <= today }.reduce(0) { total, day in
            let sum = total.addingReportingOverflow(day.tokens)
            return sum.overflow ? Int.max : sum.partialValue
        }
    }
}
