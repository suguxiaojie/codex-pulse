import Foundation

enum SettingsSummaryText {
    static func countPreview(day: Int64?, month: Int64?, style: CountStyle) -> String {
        guard let day, let month, day >= 0, month >= 0 else {
            return "示例 \(CountFormatter.string(184_000_000, style: style)) · \(CountFormatter.string(5_410_000, style: style))"
        }
        return "今日 \(CountFormatter.string(day, style: style)) · 30日 \(CountFormatter.string(month, style: style))"
    }

    static func notifications(signals: Bool, recovery: Bool) -> String {
        switch (signals, recovery) {
        case (true, true): return "信号与额度提醒已开启"
        case (false, false): return "信号与额度提醒已关闭"
        case (true, false): return "仅开启信号提醒"
        case (false, true): return "仅开启额度提醒"
        }
    }
}
