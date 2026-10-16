// Adapted from QuotaView f779531 (MIT), Copyright (c) 2026 Duoasa.
// Calendar follows the existing local usage aggregation.
import SwiftUI

struct IslandDashboardHeatmap {
    enum Mode: CaseIterable { case daily, weekly, cumulative }
    struct Cell { let date: Date; let tokens: Int?; let future: Bool }
    struct Month { let column: Int; let date: Date }
    static let gap: CGFloat = 3
    static func cellSize(width: CGFloat) -> CGFloat { max(1, (width - gap * 52) / 53) }
    static func chartHeight(width: CGFloat) -> CGFloat { cellSize(width: width) * 7 + gap * 6 + 21 }
    let cells: [Cell]
    let months: [Month]
    let maximum: Int
    let rows = 7
    let mode: Mode
    func cellIndex(column: Int, row: Int) -> Int { mode == .daily ? column * 7 + row : column }
    func isFilled(column: Int, row: Int) -> Bool {
        guard let value = cells[cellIndex(column: column, row: row)].tokens, value > 0, maximum > 0 else { return false }
        let count = max(1, min(7, Int(ceil(Double(value) / Double(maximum) * 7))))
        return row >= 7 - count
    }
    init(activity: [DailyTokenActivity], endingAt: Date, mode: Mode, lifetimeTokens: Int? = nil) {
        self.mode = mode
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        let today = calendar.startOfDay(for: endingAt)
        let weekStart = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today)!
        let start = calendar.date(byAdding: .day, value: -52 * 7, to: weekStart)!
        var values: [Date: Int] = [:]
        for item in activity where item.tokens >= 0 { values[calendar.startOfDay(for: item.date)] = item.tokens }
        func sum(_ values: [Int]) -> Int {
            values.reduce(0) { result, value in
                let added = result.addingReportingOverflow(value)
                return added.overflow ? Int.max : added.partialValue
            }
        }
        var daily: [Cell] = []
        for index in 0..<371 {
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            daily.append(.init(date: date, tokens: date > today ? nil : values[date], future: date > today))
        }
        if mode == .daily { cells = daily }
        else {
            // Carry pre-window usage into the cumulative series; never add daily cumulative values together.
            let windowTotal = sum(daily.compactMap(\.tokens))
            let earlier = values.filter { $0.key < start }.map(\.value)
            var running = lifetimeTokens.map { max(0, $0 - windowTotal) } ?? sum(earlier)
            var hasData = running > 0 || !earlier.isEmpty
            cells = (0..<53).map { column in
                let week = Array(daily[(column * 7)..<(column * 7 + 7)])
                let known = week.compactMap(\.tokens)
                let total = sum(known)
                if !known.isEmpty { hasData = true }
                running = sum([running, total])
                return .init(date: week[0].date,
                    tokens: mode == .weekly ? (known.isEmpty ? nil : total) : (hasData ? running : nil),
                    future: false)
            }
        }
        maximum = cells.compactMap(\.tokens).max() ?? 0
        var labels: [Month] = []
        for column in 0..<53 {
            let date = daily[column * 7].date
            if column == 0 || calendar.component(.month, from: date) != calendar.component(.month, from: daily[(column - 1) * 7].date) {
                if let last = labels.last, column - last.column < 3 { labels.removeLast() }
                labels.append(.init(column: column, date: date))
            }
        }
        months = labels
    }
}
