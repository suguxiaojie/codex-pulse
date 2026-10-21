import Foundation

enum CountStyle: String, CaseIterable {
    case chinese, western

    static let preferenceKey = "display.countStyle"
    static let didChange = Notification.Name("CountStyleDidChange")

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .chinese
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

enum CountFormatter {
    static func string(_ value: Int64, style: CountStyle) -> String {
        guard value >= 0 else { return "—" }
        return format(Decimal(value), style: style)
    }

    static func display(_ value: Int64) -> String {
        string(value, style: CountStyle.load())
    }

    // Chart values arrive as Double; validate before any integer conversion.
    static func chart(_ value: Double, style: CountStyle = CountStyle.load()) -> String {
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { return "—" }
        return format(Decimal(value), style: style)
    }

    private static func format(_ value: Decimal, style: CountStyle) -> String {
        let scales: [Decimal] = style == .chinese ? [1, 10_000, 100_000_000] : [1, 1_000, 1_000_000, 1_000_000_000]
        let suffixes = style == .chinese ? ["", "万", "亿"] : ["", "K", "M", "B"]
        var index = scales.lastIndex(where: { value >= $0 }) ?? 0
        while true {
            var scaled = value / scales[index]
            let digits: Int
            if index == 0 { digits = 0 }
            else if style == .western { digits = scaled < 100 ? 1 : 0 }
            else if index == 1 { digits = scaled < 100 ? 1 : 0 }
            else { digits = scaled < 10 ? 2 : (scaled < 100 ? 1 : 0) }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &scaled, digits, .plain)
            if index + 1 < scales.count, rounded * scales[index] >= scales[index + 1] {
                index += 1
                continue
            }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = style == .chinese
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = digits
            return (formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "—") + suffixes[index]
        }
    }
}
