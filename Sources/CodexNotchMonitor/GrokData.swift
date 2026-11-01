import Foundation
import CoreFoundation
import Darwin

enum GrokDisplayClock {
    /// A retained/hidden view's sampled time must not predate a new successful response.
    static func now(sampled: Date, current: Date = Date()) -> Date { max(sampled, current) }
}

enum GrokJSON {
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func integer(_ value: Any?) -> Int? {
        guard let n = number(value), n >= 0, n < Double(Int.max), n.rounded() == n else { return nil }
        return Int(n)
    }
    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return FastTimestamp.parse(s)
    }
    static func object(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
    static func eventDate(_ object: [String: Any]) -> Date? {
        let upper = Date().timeIntervalSince1970 + 60
        guard let seconds = number(object["timestamp"]), seconds > 0, seconds <= upper else { return nil }
        let params = object["params"] as? [String: Any]
        let meta = params?["_meta"] as? [String: Any]
        if let value = meta?["agentTimestampMs"] {
            guard let ms = number(value), ms > 0, ms / 1000 <= upper else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }
        return Date(timeIntervalSince1970: seconds)
    }
    static func read(_ url: URL, maximum: Int = 2_097_152) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_size >= 0, info.st_size <= maximum else { return nil }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == data.count else { return nil }; return data
    }
    static func add(_ a: Int, _ b: Int) -> Int {
        let sum = a.addingReportingOverflow(b); return sum.overflow ? Int.max : sum.partialValue
    }
}

struct GrokQuotaSnapshot: Equatable {
    let usedPercent: Double
    let startsAt: Date?
    let resetsAt: Date?
    let periodType: String?
    let plan: String?
    let prepaidCents: Int?
    let sharedPool: Bool?
    let capturedAt: Date
    var remainingPercent: Int { Int((100 - usedPercent).rounded()) }
    var title: String { periodType == "USAGE_PERIOD_TYPE_WEEKLY" ? "每周额度" : periodType == "USAGE_PERIOD_TYPE_MONTHLY" ? "每月额度" : "订阅额度" }
    func isAvailable(at now: Date) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age >= -60 && (startsAt.map { $0 <= now.addingTimeInterval(60) } ?? true)
            && (resetsAt.map { $0 > now } ?? (age <= 300))
    }
    func isStale(at now: Date) -> Bool { now.timeIntervalSince(capturedAt) > 300 }
    static func decode(_ result: [String: Any], now: Date) -> Self? {
        guard let c = result["config"] as? [String: Any] else { return nil }
        let used: Double?
        if c.keys.contains("creditUsagePercent") { used = GrokJSON.number(c["creditUsagePercent"]) }
        else if let budget = (c["monthlyLimit"] as? [String: Any]).flatMap({ GrokJSON.number($0["val"] ?? 0) }), budget > 0,
                let spent = (c["used"] as? [String: Any]).flatMap({ GrokJSON.number($0["val"] ?? 0) }), spent >= 0 {
            used = spent / budget * 100
        } else { used = nil }
        guard let used, (0...100).contains(used) else { return nil }
        let period = c["currentPeriod"] as? [String: Any]
        if c["currentPeriod"] != nil && period == nil { return nil }
        let start = GrokJSON.date(period?["start"] ?? c["billingPeriodStart"])
        let end = GrokJSON.date(period?["end"] ?? c["billingPeriodEnd"])
        if (period?["start"] ?? c["billingPeriodStart"]) != nil && start == nil { return nil }
        if (period?["end"] ?? c["billingPeriodEnd"]) != nil && end == nil { return nil }
        if let start, let end, start >= end { return nil }
        let shared = c["isUnifiedBillingUser"] as? NSNumber
        return .init(usedPercent: used, startsAt: start, resetsAt: end, periodType: period?["type"] as? String,
            plan: (result["subscription_tier"] as? String).map { String($0.prefix(80)) },
            prepaidCents: (c["prepaidBalance"] as? [String: Any]).flatMap { GrokJSON.integer($0["val"] ?? 0) },
            sharedPool: shared.flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }, capturedAt: now)
    }
}

struct GrokUsageSummary: Equatable {
    struct Day: Equatable { let date: Date; var tokens: Int; var cost: Double? }
    let days: [Day]
    let complete: Bool
    let sessionCount: Int
    let updatedAt: Date
    var lifetimeTokens: Int { days.reduce(0) { GrokJSON.add($0, $1.tokens) } }
}

struct GrokSpend: Equatable {
    let tokens: Int
    let cost: Double?
    static func decode(_ value: Any?) -> Self? {
        guard let u = value as? [String: Any], let total = GrokJSON.integer(u["totalTokens"]) else { return nil }
        let incomplete = (u["costIsPartial"] as? Bool) == true || (u["usageIsIncomplete"] as? Bool) == true
        let ticks = GrokJSON.integer(u["costUsdTicks"])
        return .init(tokens: total, cost: !incomplete ? ticks.map { Double($0) / 10_000_000_000 } : nil)
    }
}
