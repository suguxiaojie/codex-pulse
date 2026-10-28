import Foundation

/// Strict common log format; callers retain their formatter fallback for other ISO 8601 forms.
enum FastTimestamp {
    static func parse(_ value: String) -> Date? {
        var bytes = value.utf8.makeIterator()
        func number(_ count: Int) -> Int? {
            var result = 0
            for _ in 0..<count {
                guard let byte = bytes.next(), byte >= 48, byte <= 57 else { return nil }
                result = result * 10 + Int(byte - 48)
            }
            return result
        }
        guard let year = number(4), year > 0, bytes.next() == 45,
              let month = number(2), (1...12).contains(month), bytes.next() == 45,
              let day = number(2), bytes.next() == 84,
              let hour = number(2), hour < 24, bytes.next() == 58,
              let minute = number(2), minute < 60, bytes.next() == 58,
              let second = number(2), second < 60 else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let daysInMonth: Int
        switch month {
        case 2: daysInMonth = leap ? 29 : 28
        case 4, 6, 9, 11: daysInMonth = 30
        default: daysInMonth = 31
        }
        guard day >= 1, day <= daysInMonth else { return nil }
        var suffix = bytes.next()
        var fraction = 0
        var scale = 1
        if suffix == 46 {
            suffix = bytes.next()
            while let byte = suffix, byte >= 48, byte <= 57 {
                guard scale < 1_000_000_000 else { return nil }
                fraction = fraction * 10 + Int(byte - 48)
                scale *= 10
                suffix = bytes.next()
            }
            guard scale > 1 else { return nil }
        }
        let zone: Int
        if suffix == 90 {
            zone = 0
        } else if suffix == 43 || suffix == 45 {
            guard let hours = number(2), hours < 24, bytes.next() == 58,
                  let minutes = number(2), minutes < 60 else { return nil }
            zone = (hours * 3600 + minutes * 60) * (suffix == 43 ? 1 : -1)
        } else { return nil }
        guard bytes.next() == nil else { return nil }
        // Gregorian civil date to days since 1970-01-01 (400-year eras).
        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = adjustedYear / 400
        let yearOfEra = adjustedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146097 + dayOfEra - 719468
        let seconds = days * 86400 + hour * 3600 + minute * 60 + second - zone
        // ISO8601DateFormatter's existing log path truncates fractions to milliseconds.
        // Preserve its event identity/deduplication semantics even for 6/9-digit input.
        let milliseconds = fraction * 1000 / scale
        return Date(timeIntervalSince1970: Double(seconds) + Double(milliseconds) / 1000)
    }
}
