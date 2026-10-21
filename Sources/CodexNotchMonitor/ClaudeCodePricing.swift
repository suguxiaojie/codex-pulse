// Adapted from QuotaView f7795311 (MIT), Copyright (c) 2026 Duoasa.
import Foundation
import CoreFoundation

/// Token counts reported by one Claude API response in a Claude Code transcript.
public struct ClaudeCodeTokenUsage: Equatable, Sendable {
    public var input: Int64
    public var output: Int64
    public var cacheWrite5m: Int64
    public var cacheWrite1h: Int64
    public var cacheRead: Int64
    public var speed: String?
    public var inferenceGeo: String?

    public init(input: Int64 = 0, output: Int64 = 0, cacheWrite5m: Int64 = 0,
                cacheWrite1h: Int64 = 0, cacheRead: Int64 = 0, speed: String? = nil, inferenceGeo: String? = nil) {
        self.speed = speed; self.inferenceGeo = inferenceGeo
        self.input = input; self.output = output
        self.cacheWrite5m = cacheWrite5m; self.cacheWrite1h = cacheWrite1h; self.cacheRead = cacheRead
    }

    public var total: Int64 { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    public static func + (lhs: Self, rhs: Self) -> Self {
        .init(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
              cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
              cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h, cacheRead: lhs.cacheRead + rhs.cacheRead)
    }

    /// Decodes an Anthropic `usage` object. Missing counters are zero; a
    /// malformed or negative counter rejects the whole record.
    public init?(usage: [String: Any]) {
        func count(_ key: String, in object: [String: Any] = usage) -> Int64?? {
            guard let value = object[key] else { return .some(nil) }
            guard let number = ClaudeCodeNumeric.nonnegativeInteger(value) else { return nil }
            return .some(number)
        }
        guard let input = count("input_tokens"), let output = count("output_tokens"),
              let creation = count("cache_creation_input_tokens"), let read = count("cache_read_input_tokens") else { return nil }
        var write5m = creation ?? 0, write1h: Int64 = 0
        if let raw = usage["cache_creation"] {
            guard let split = raw as? [String: Any],
                  let short = count("ephemeral_5m_input_tokens", in: split),
                  let long = count("ephemeral_1h_input_tokens", in: split) else { return nil }
            if short != nil || long != nil {
                write5m = short ?? 0; write1h = long ?? 0
                if let creation, creation != write5m + write1h {
                    write1h = min(write1h, creation)
                    write5m = creation - write1h
                }
            }
        }
        self.init(input: input ?? 0, output: output ?? 0, cacheWrite5m: write5m, cacheWrite1h: write1h, cacheRead: read ?? 0,
                  speed: usage["speed"] as? String, inferenceGeo: usage["inference_geo"] as? String)
    }
}

/// Published Anthropic list prices in USD per million tokens. An unknown model
/// has no estimate rather than a guessed price.
public enum ClaudeCodePricing {
    public struct Rates: Equatable, Sendable {
        public let input: Double, output: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double
        public init(_ input: Double, _ output: Double, _ cacheWrite5m: Double, _ cacheWrite1h: Double, _ cacheRead: Double) {
            self.input = input; self.output = output; self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h; self.cacheRead = cacheRead
        }
    }

    public static func rates(for model: String) -> Rates? {
        guard let model = ModelIdentity(model) else { return nil }
        let version = model.version
        // Official standard list-price snapshot checked 2026-10-21.
        // Explicit versions only: never assign today's prices to a future model.
        switch (model.family, version) {
        case ("fable", [5, 1]), ("mythos", [5, 1]): return .init(10, 50, 12.5, 20, 0.25)
        case ("fable", [5]), ("mythos", [5]): return .init(10, 50, 12.5, 20, 1)
        case ("opus", [5, 5]): return .init(4, 20, 5, 8, 0.20)
        case ("opus", [5]), ("opus", [4, 5]), ("opus", [4, 6]), ("opus", [4, 7]), ("opus", [4, 8]): return .init(5, 25, 6.25, 10, 0.5)
        case ("opus", [4]), ("opus", [4, 1]), ("opus", [3]): return .init(15, 75, 18.75, 30, 1.5)
        case ("sonnet", [5, 5]): return .init(2, 10, 2.5, 4, 0.1)
        case ("sonnet", [5]): return .init(2, 10, 2.5, 4, 0.2)
        case ("sonnet", [4]), ("sonnet", [4, 5]), ("sonnet", [4, 6]), ("sonnet", [3, 5]), ("sonnet", [3, 7]): return .init(3, 15, 3.75, 6, 0.3)
        case ("haiku", [5, 5]): return .init(0.1, 0.5, 0.125, 0.2, 0.01)
        case ("haiku", [4, 5]): return .init(1, 5, 1.25, 2, 0.1)
        case ("haiku", [3, 5]): return .init(0.8, 4, 1, 1.6, 0.08)
        case ("haiku", [3]): return .init(0.25, 1.25, 0.3, 0.5, 0.03)
        default: break
        }
        return nil
    }

    public static func cost(model: String, usage: ClaudeCodeTokenUsage) -> Double? {
        guard var rates = rates(for: model), let identity = ModelIdentity(model) else { return nil }
        let speedMultiplier: Double
        switch usage.speed {
        case nil, "standard": speedMultiplier = 1
        case "fast" where identity.family == "opus" && [[5, 5], [5], [4, 8]].contains(identity.version): speedMultiplier = 2
        default: return nil
        }
        let geoMultiplier: Double
        switch usage.inferenceGeo {
        case nil, "global": geoMultiplier = 1
        case "us" where identity.version[0] >= 5 ||
            (["opus", "sonnet"].contains(identity.family) && identity.version.lexicographicallyPrecedes([4, 6]) == false):
            geoMultiplier = 1.1
        default: return nil
        }
        let prompt = usage.input + usage.cacheWrite5m + usage.cacheWrite1h + usage.cacheRead
        if let identity = ModelIdentity(model), identity.family == "haiku", identity.version == [5, 5], prompt > 100_000 {
            rates = .init(0.5, 2.5, 0.625, 1, 0.05)
        }
        // Legacy long-context premium is not inferable from all transcript versions.
        if prompt > 200_000, let identity = ModelIdentity(model), identity.family == "sonnet",
           [[4], [4, 5]].contains(identity.version) { return nil }
        let total = Double(usage.input) * rates.input + Double(usage.output) * rates.output
            + Double(usage.cacheWrite5m) * rates.cacheWrite5m + Double(usage.cacheWrite1h) * rates.cacheWrite1h
            + Double(usage.cacheRead) * rates.cacheRead
        return total / 1_000_000 * speedMultiplier * geoMultiplier
    }

    /// `claude-opus-5-5-20260101` → `Opus 5.5`; unrecognized identifiers stay verbatim.
    public static func displayName(for model: String) -> String {
        guard let identity = ModelIdentity(model) else { return model }
        return identity.family.capitalized + " " + identity.version.map(String.init).joined(separator: ".")
    }

    /// `claude-opus-5-5-20260101`,`claude-3-5-haiku-latest` and
    /// `us.anthropic.claude-sonnet-4-5-v1:0` all name a family and version.
    struct ModelIdentity {
        let family: String
        let version: [Int]

        init?(_ raw: String) {
            let lowered = raw.lowercased()
            let tokens = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            guard let index = tokens.firstIndex(where: { ["fable", "mythos", "opus", "sonnet", "haiku"].contains($0) }) else { return nil }
            func numbers(_ slice: ArraySlice<String>) -> [Int] {
                var result: [Int] = []
                for token in slice {
                    // Dates and provider revisions end the version.
                    guard token.count <= 2, let value = Int(token) else { break }
                    result.append(value)
                }
                return result
            }
            var version = numbers(tokens[(index + 1)...])
            if version.isEmpty {
                // Legacy `claude-3-5-haiku` places the version before the family.
                let before = tokens[..<index].reversed().prefix { $0.count <= 2 && Int($0) != nil }
                version = before.reversed().compactMap { Int($0) }
            }
            guard !version.isEmpty else { return nil }
            family = tokens[index]
            self.version = version
        }
    }
}


/// Reject booleans, fractions, negatives and unreasonably large counters.
enum ClaudeCodeNumeric {
    static func nonnegativeInteger(_ value: Any) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let decimal = Decimal(string: number.stringValue),
              decimal >= 0, decimal <= Decimal(1_000_000_000_000) else { return nil }
        let result = number.int64Value
        return Decimal(result) == decimal ? result : nil
    }
}
