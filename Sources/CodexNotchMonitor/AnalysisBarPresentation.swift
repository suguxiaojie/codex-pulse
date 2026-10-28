import Foundation

struct AnalysisActivityBarSample: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let value: Double
    let tokens: Int?
}

/// Values shared by drawing, tooltips and accessibility; no formatting during layout measurement.
struct AnalysisBarPresentation {
    struct Row {
        let ratio: Double
        let label: String
        let detail: String
    }
    let rows: [Row]
    let peak: String
    let hasValues: Bool

    init(samples: [AnalysisActivityBarSample], hourly: Bool, isCost: Bool, style: CountStyle,
         locale: Locale, calendar: Calendar, timeZone: TimeZone) {
        let maximum = samples.map(\.value).filter(\.isFinite).max() ?? 0
        let denominator = max(0.000001, maximum)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = hourly ? "HH:00" : "M/d"
        func value(_ number: Double) -> String {
            isCost ? Self.dollars(number) : CountFormatter.chart(number, style: style) + " Token"
        }
        peak = "峰值 " + value(maximum)
        hasValues = samples.contains { $0.value > 0 }
        rows = samples.map { sample in
            let label = formatter.string(from: sample.date)
            var detail = label + " · " + value(sample.value)
            if isCost, let tokens = sample.tokens { detail += " · " + CountFormatter.string(Int64(tokens), style: style) + " Token" }
            return Row(ratio: sample.value.isFinite ? max(0, sample.value) / denominator : 0,
                label: label, detail: detail)
        }
    }

    static func dollars(_ value: Double) -> String {
        String(format: value > 0 && value < 1 ? "$%.4f" : "$%.2f", value)
    }
}
