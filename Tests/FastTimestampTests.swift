import Foundation

@main
enum FastTimestampTests {
    static func main() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        var seed: UInt64 = 0xC0DE2026
        func random(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(bound))
        }
        var inputs: [String] = []
        for index in 0..<10_000 {
            var year = 1970 + random(120)
            var month = 1 + random(12)
            var day = 1 + random(28)
            if index % 10 == 0 { year = 2000 + 4 * random(23); month = 2; day = 29 }
            if index % 10 == 1 { month = 12; day = 31 }
            let digits = [0, 3, 6, 9][index % 4]
            let fraction = digits == 0 ? "" : "." + (0..<digits).map { _ in String(random(10)) }.joined()
            let zone = index % 3 == 0 ? "Z" : String(format: "%@%02d:%02d", index % 3 == 1 ? "+" : "-", random(15), random(4) * 15)
            inputs.append(String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, random(24), random(60), random(60)) + fraction + zone)
        }
        let start = Date()
        let reference = inputs.map { fractional.date(from: $0) ?? standard.date(from: $0) }
        let referenceSeconds = Date().timeIntervalSince(start)
        let fastStart = Date()
        let actual = inputs.map { FastTimestamp.parse($0) }
        let fastSeconds = Date().timeIntervalSince(fastStart)
        var maxError: Double = 0
        for index in inputs.indices {
            guard let old = reference[index], let new = actual[index] else { fatalError("parse failed: \(inputs[index])") }
            let error = abs(new.timeIntervalSince(old))
            maxError = max(maxError, error)
            precondition(error <= 0.000001, "mismatch \(inputs[index]): \(error)")
        }
        for digits in 1...9 {
            precondition(FastTimestamp.parse("2000-02-29T23:59:59." + String(repeating: "1", count: digits) + "Z") != nil)
        }
        for invalid in ["", "2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2026-04-31T00:00:00Z",
                        "0000-01-01T00:00:00Z", "2026-00-01T00:00:00Z", "2026-13-01T00:00:00Z",
                        "2026-01-00T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:60:00Z",
                        "2026-01-01T00:00:60Z", "2026-01-01T00:00:00.Z", "2026-01-01T00:00:00.1234567890Z",
                        "2026-01-01T00:00:00+24:00", "2026-01-01T00:00:00+01:60", "2026-01-01T00:00:00",
                        "2026-01-01T00:00:00Zx", "2026-01-01T00:00:00+0100", "２０２６-01-01T00:00:00Z"] {
            precondition(FastTimestamp.parse(invalid) == nil, "accepted invalid: \(invalid)")
        }
        precondition(FastTimestamp.parse("1970-01-01T00:00:00Z")!.timeIntervalSince1970 == 0)
        precondition(FastTimestamp.parse("1969-12-31T23:59:59Z")!.timeIntervalSince1970 == -1)
        print(String(format: "Timestamp 10000 comparisons passed, max error %.9fs; ISO8601 %.6fs, fast %.6fs, speedup %.2fx", maxError, referenceSeconds, fastSeconds, referenceSeconds / fastSeconds))
    }
}
