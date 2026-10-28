import Foundation

@main enum AnalysisBarPresentationTests {
    static func main() {
        let calendar = Calendar(identifier: .gregorian)
        let date = ISO8601DateFormatter().date(from: "2026-10-27T01:00:00Z")!
        let samples = [AnalysisActivityBarSample(date: date, value: 16000, tokens: 16000),
                       .init(date: date.addingTimeInterval(3600), value: 32000, tokens: 32000)]
        func model(_ values: [AnalysisActivityBarSample], hourly: Bool = false, cost: Bool = false,
                   style: CountStyle = .chinese, zone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> AnalysisBarPresentation {
            .init(samples: values, hourly: hourly, isCost: cost, style: style,
                locale: Locale(identifier: "en_US_POSIX"), calendar: calendar, timeZone: zone)
        }
        let chinese = model(samples)
        precondition(chinese.rows.map(\.ratio) == [0.5, 1])
        precondition(chinese.rows[0].label == "10/27" && chinese.rows[0].detail == "10/27 · 1.6万 Token")
        precondition(chinese.peak == "峰值 3.2万 Token" && chinese.hasValues)
        let western = model(samples, style: .western)
        precondition(western.rows[0].detail == "10/27 · 16K Token" && western.peak == "峰值 32K Token")
        precondition(model(samples, hourly: true).rows.map(\.label) == ["01:00", "02:00"])
        precondition(model(samples, hourly: true, zone: TimeZone(secondsFromGMT: 8 * 3600)!).rows[0].label == "09:00")
        let money = model([.init(date: date, value: 0.5, tokens: 16000)], cost: true)
        precondition(money.peak == "峰值 $0.5000" && money.rows[0].detail == "10/27 · $0.5000 · 1.6万 Token")
        precondition(model([.init(date: date, value: 2, tokens: nil)], cost: true).rows[0].detail == "10/27 · $2.00")
        let empty = model([])
        precondition(empty.rows.isEmpty && !empty.hasValues && empty.peak == "峰值 0 Token")
        let invalid = model([.init(date: date, value: .nan, tokens: nil), .init(date: date, value: -1, tokens: nil)])
        precondition(invalid.rows.allSatisfy { $0.ratio == 0 && $0.ratio.isFinite })
        precondition(model(samples).rows.map(\.detail) == chinese.rows.map(\.detail))
        print("Analysis bar presentation: ratios, labels, styles, timezone, cost, missing tokens, empty and invalid input passed")
    }
}
