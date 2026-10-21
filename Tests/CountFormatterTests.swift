import Foundation

@main
enum CountFormatterTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        let cases: [(Int64, String, String)] = [
            (0, "0", "0"), (9_999, "9,999", "10K"), (10_000, "1万", "10K"),
            (99_999, "10万", "100K"), (999_999, "100万", "1M"),
            (1_000_000, "100万", "1M"), (99_995_000, "1亿", "100M"),
            (99_999_999, "1亿", "100M"), (100_000_000, "1亿", "100M"),
            (999_999_999, "10亿", "1B"), (1_000_000_000, "10亿", "1B"),
            (9_995_000_000, "100亿", "10B"), (10_000_000_000, "100亿", "10B"),
            (12_345_678_901, "123亿", "12.3B"), (150_000_000, "1.5亿", "150M"),
            (20_000, "2万", "20K"), (184_000_000, "1.84亿", "184M"),
            (5_410_000, "541万", "5.4M"), (34_560_000, "3,456万", "34.6M"),
            (6_870_000_000, "68.7亿", "6.9B"), (-1, "—", "—"), (.min, "—", "—"),
            (.max, "92,233,720,369亿", "9223372037B"),
            (99_994_999, "9,999万", "100M"), (999_499, "99.9万", "999K"),
            (999_500, "100万", "1M"), (1_050, "1,050", "1.1K")
        ]
        for (value, chinese, western) in cases {
            check(CountFormatter.string(value, style: .chinese) == chinese, "Chinese \(value)")
            check(CountFormatter.string(value, style: .western) == western, "Western \(value)")
        }
        for style in CountStyle.allCases {
            for invalid in [Double.nan, .infinity, -.infinity, -1, Double(Int64.max)] {
                check(CountFormatter.chart(invalid, style: style) == "—", "invalid chart value")
            }
        }
        let suite = "CountFormatterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(CountStyle.load(from: defaults) == .chinese, "default")
        defaults.set("invalid", forKey: CountStyle.preferenceKey)
        check(CountStyle.load(from: defaults) == .chinese, "unknown preference")
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: CountStyle.didChange, object: nil, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for style in CountStyle.allCases {
            style.save(to: defaults)
            check(CountStyle.load(from: defaults) == style, "round trip")
            check(defaults.string(forKey: CountStyle.preferenceKey) == style.rawValue, "persisted raw value")
        }
        check(notifications == 2, "refresh notifications")
        print("CountFormatterTests: \(checks) checks passed")
    }
}
