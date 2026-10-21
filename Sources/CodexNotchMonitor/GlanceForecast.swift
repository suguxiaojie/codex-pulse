import Foundation

enum QuotaPaceForecast: Equatable {
    case insufficient, lastsUntilReset, exhausts(at: Date), exhausted

    init(window: RateLimitWindow, now: Date) {
        guard (0...100).contains(window.usedPercent),
              let minutes = window.windowDurationMinutes, minutes > 0,
              let reset = window.resetsAt,
              now.timeIntervalSinceReferenceDate.isFinite,
              reset.timeIntervalSinceReferenceDate.isFinite, reset > now else {
            self = .insufficient
            return
        }
        if window.remainingPercent == 0 { self = .exhausted; return }
        let elapsed = now.timeIntervalSince(reset.addingTimeInterval(-Double(minutes) * 60))
        guard elapsed >= 3_600 else { self = .insufficient; return }
        if window.usedPercent == 0 { self = .lastsUntilReset; return }
        let exhaustion = now.addingTimeInterval(Double(window.remainingPercent) * elapsed / Double(window.usedPercent))
        self = exhaustion >= reset ? .lastsUntilReset : .exhausts(at: exhaustion)
    }

    func copy(resetsAt: Date?, now: Date) -> (primary: String, secondary: String) {
        let countdown = resetsAt.flatMap { $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil }
            .map { ChineseDisplayText.spacing(QuotaResetCountdown.text(until: $0, relativeTo: now)) }
            ?? "重置时间未知"
        switch self {
        case .insufficient: return ("数据不足，暂不预测", countdown)
        case .lastsUntilReset: return ("按当前速度，可用到重置", "估算 · " + countdown)
        case .exhausted: return ("额度已用完", countdown)
        case .exhausts(let date):
            let hours = max(1, Int(ceil(date.timeIntervalSince(now) / 3_600)))
            let duration = hours >= 24 ? "\(Int(ceil(Double(hours) / 24))) 天" : "\(hours) 小时"
            return ("按当前速度，约 \(duration)后用完", "估算 · " + countdown)
        }
    }
}

enum GlanceTone: Equatable {
    case calm, tight, critical

    init(window: RateLimitWindow, forecast: QuotaPaceForecast) {
        if window.remainingPercent < 20 || forecast == .exhausted { self = .critical }
        else if window.remainingPercent < 50 { self = .tight }
        else if case .exhausts = forecast { self = .tight }
        else { self = .calm }
    }
}

enum GlanceDayStrip {
    struct Sample { let date: Date; let value: Double }
    struct Bucket: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let label: String
        let value: Double
        let isPeak: Bool
    }

    static func buckets(samples: [Sample], now: Date, calendar: Calendar = .current) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        let days = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        var values: [Date: Double] = [:]
        for sample in samples where sample.date.timeIntervalSinceReferenceDate.isFinite && sample.value.isFinite && sample.value >= 0 {
            let day = calendar.startOfDay(for: sample.date)
            guard days.contains(day) else { continue }
            values[day, default: 0] += sample.value
        }
        let maximum = values.values.max() ?? 0
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return days.map { day in
            let value = values[day] ?? 0
            return Bucket(date: day, label: day == today ? "今" : weekdays[calendar.component(.weekday, from: day) - 1],
                          value: value, isPeak: maximum > 0 && value == maximum)
        }
    }

    static func summaryText(_ buckets: [Bucket], formatValue: (Double) -> String) -> String {
        guard let today = buckets.last, let peak = buckets.max(by: { $0.value < $1.value }), peak.value > 0 else {
            return "近 7 天暂无用量"
        }
        if today.value == peak.value { return "今日 \(formatValue(today.value)) · 峰值" }
        return "峰值 周\(peak.label) \(formatValue(peak.value)) · 今日 \(formatValue(today.value))"
    }

    static func costText(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        return "$" + compactCost(value)
    }

    static func costTotalText(_ buckets: [Bucket], unpricedDates: Set<Date>) -> String {
        let known = buckets.filter { !unpricedDates.contains($0.date) }
        let total = known.reduce(0) { $0 + $1.value }
        return (known.count < buckets.count ? "≥ " : "") + fullCostText(total)
    }

    static func costSummaryText(_ buckets: [Bucket], unpricedDates: Set<Date>) -> String {
        let known = buckets.filter { !unpricedDates.contains($0.date) }
        guard known.count < buckets.count else { return summaryText(buckets, formatValue: costText) }
        guard let today = buckets.last, let peak = known.max(by: { $0.value < $1.value }) else {
            return "近 7 天金额未知"
        }
        let todayText = unpricedDates.contains(today.date) ? "金额未知" : costText(today.value)
        guard peak.value > 0 else { return "已知成本 $0 · 今日 \(todayText)" }
        if !unpricedDates.contains(today.date) && today.value == peak.value {
            return "今日 \(todayText) · 峰值"
        }
        return "峰值 周\(peak.label) \(costText(peak.value)) · 今日 \(todayText)"
    }

    static func costDetailValue(_ bucket: Bucket, unpricedDates: Set<Date>) -> String {
        unpricedDates.contains(bucket.date) ? "金额未知（部分模型未计价）" : fullCostText(bucket.value)
    }

    static func fullCostText(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        if value == 0 { return "$0" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        guard let amount = formatter.string(from: NSNumber(value: value)) else { return "—" }
        return amount == "0.0" ? "$0" : "$" + amount
    }

    static func tokenText(_ value: Double) -> String {
        CountFormatter.chart(value)
    }

    private static func compactCost(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        for (scale, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] where value >= scale {
            let scaled = value / scale
            return String(format: scaled >= 100 ? "%.0f%@" : "%.1f%@", scaled, suffix)
        }
        return String(format: "%.0f", value)
    }
}

enum GlanceStripMetric: String, CaseIterable {
    case cost, token

    var title: String { self == .cost ? "成本" : "Token" }

    func subtitle(tokenSourceLabel: String = "当前账号本地用量") -> String {
        "近 7 天 · " + (self == .cost ? "估算，非账单" : tokenSourceLabel)
    }
}

enum GlanceProvider: String, CaseIterable {
    case codex, claude

    static func resolve(_ saved: String, claudeEnabled: Bool) -> Self {
        claudeEnabled && saved == Self.claude.rawValue ? .claude : .codex
    }
}

/// Read-only projection of Claude snapshots. Never falls back to Codex data.
struct GlanceClaudeSnapshot {
    let windows: [RateLimitWindow]
    let isStale: Bool
    let observedAt: Date?
    let quotaPlaceholder: String?
    let usageReady: Bool
    let tokenSamples: [GlanceDayStrip.Sample]
    let costSamples: [GlanceDayStrip.Sample]
    let unpricedDates: Set<Date>
    let todayTokens: Int64
    let monthlyTokens: Int64
    let lifetimeTokens: Int64?
    let updatedAt: Date?

    var limitingWindow: RateLimitWindow? { windows.min { $0.remainingPercent < $1.remainingPercent } }
    var glowMultiplier: Double { isStale ? 0.5 : 1 }

    static func localDate(_ encodedDay: Date, calendar: Calendar = .current) -> Date? {
        guard encodedDay.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: utc.dateComponents([.year, .month, .day], from: encodedDay))
    }

    init(limits: ClaudeCodeRateLimits?, usage: ClaudeCodeUsageSummary?, statusLineEnabled: Bool,
         now: Date, calendar: Calendar = .current) {
        let captured = limits?.capturedAt
        let validCapture = captured.map { $0.timeIntervalSinceReferenceDate.isFinite && $0.timeIntervalSince(now) <= 60 } ?? false
        observedAt = statusLineEnabled && validCapture ? captured : nil
        isStale = observedAt.map { now.timeIntervalSince($0) > 600 } ?? false
        func convert(_ window: ClaudeCodeRateLimits.Window?, minutes: Int) -> RateLimitWindow? {
            guard statusLineEnabled, validCapture, let window, window.usedPercent.isFinite,
                  (0...100).contains(window.usedPercent) else { return nil }
            if let reset = window.resetsAt {
                guard reset.timeIntervalSinceReferenceDate.isFinite, reset > now else { return nil }
            } else if captured.map({ now.timeIntervalSince($0) > 600 }) == true { return nil }
            return .init(usedPercent: Int(window.usedPercent.rounded()), windowDurationMinutes: minutes, resetsAt: window.resetsAt)
        }
        windows = [convert(limits?.fiveHour, minutes: 300), convert(limits?.sevenDay, minutes: 10_080)].compactMap { $0 }
        quotaPlaceholder = !statusLineEnabled ? "开启 Claude 状态栏后可显示额度"
            : windows.isEmpty ? "等待 Claude Code 下一次回复后同步额度" : nil
        usageReady = usage?.complete == true
        let today = calendar.startOfDay(for: now)
        let lower = calendar.date(byAdding: .day, value: -29, to: today)!
        let days = (usage?.days ?? []).compactMap { day -> (Date, Int64, Double?)? in
            guard let date = Self.localDate(day.date, calendar: calendar), date <= today else { return nil }
            let cost = day.estimatedCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            return (date, max(0, day.tokens), cost)
        }
        tokenSamples = days.map { .init(date: $0.0, value: Double($0.1)) }
        costSamples = days.map { .init(date: $0.0, value: $0.2 ?? 0) }
        unpricedDates = Set(days.filter { $0.2 == nil }.map { $0.0 })
        func sum(_ values: [Int64]) -> Int64 {
            values.reduce(0) { total, value in
                let result = total.addingReportingOverflow(value)
                return result.overflow ? Int64.max : result.partialValue
            }
        }
        todayTokens = sum(days.filter { $0.0 == today }.map { $0.1 })
        monthlyTokens = sum(days.filter { $0.0 >= lower }.map { $0.1 })
        lifetimeTokens = usage.map { max(0, $0.lifetimeTokens) }
        updatedAt = [usage?.updatedAt, statusLineEnabled ? limits?.capturedAt : nil].compactMap { $0 }.max()
    }

    func observationSuffix() -> String {
        guard isStale, let observedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return " · 数据于 " + formatter.string(from: observedAt)
    }
}
