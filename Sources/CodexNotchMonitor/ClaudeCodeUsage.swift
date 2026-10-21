// Adapted from QuotaView f7795311 (MIT), Copyright (c) 2026 Duoasa.
import Foundation
import Darwin
import CoreFoundation

/// Official Claude Code subscription windows captured by the QuotaView status line.
public struct ClaudeCodeRateLimits: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let usedPercent: Double
        public let resetsAt: Date?
        public var remainingPercent: Int { Int((100 - min(100, max(0, usedPercent))).rounded()) }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let capturedAt: Date

    public init(fiveHour: Window?, sevenDay: Window?, capturedAt: Date) {
        self.fiveHour = fiveHour; self.sevenDay = sevenDay; self.capturedAt = capturedAt
    }

    public static func decode(snapshot data: Data) -> Self? {
        guard data.count <= 65_536, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let capturedNumber = object["capturedAt"] as? NSNumber, CFGetTypeID(capturedNumber) != CFBooleanGetTypeID(),
              case let captured = capturedNumber.doubleValue, captured.isFinite, captured > 0,
              let limits = object["rate_limits"] as? [String: Any] else { return nil }
        let value = Self(fiveHour: window(limits["five_hour"]), sevenDay: window(limits["seven_day"]),
                         capturedAt: Date(timeIntervalSince1970: captured))
        return value.fiveHour == nil && value.sevenDay == nil ? nil : value
    }

    static func window(_ value: Any?) -> Window? {
        guard let object = value as? [String: Any] else { return nil }
        let used = ["used_percentage", "used_percent", "utilization"].lazy
            .compactMap { key -> Double? in
                guard let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
                return number.doubleValue
            }.first
        guard let used, used.isFinite, used >= 0, used <= 100 else { return nil }
        return Window(usedPercent: used, resetsAt: date(object["resets_at"] ?? object["reset_at"]))
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1_000 : raw)
        }
        return ClaudeCodeTranscriptDecoder.timestamp(value)
    }
}

/// Daily token totals and list-price estimates from local Claude Code transcripts.
public struct ClaudeCodeUsageSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        /// UTC midnight carrying the local calendar day, matching QuotaView's day charts.
        public let date: Date
        public let tokens: Int64
        /// Nil when any token on that day belongs to a model without a published price.
        public let estimatedCost: Double?
    }

    public let days: [Day]
    public let lifetimeTokens: Int64
    public let complete: Bool
    public let fileCount: Int
    public let updatedAt: Date
}

public actor ClaudeCodeUsageScanner {
    private struct Entry { let day: Date; let model: String; let usage: ClaudeCodeTokenUsage }
    private struct FileState {
        var size: UInt64
        var modified: Date
        var inode: UInt64 = 0
        var tail: ClaudeCodeTranscriptTail
        var entries: [String: Entry] = [:]
    }

    public static let maximumFiles = 20_000
    private let projectsURL: URL
    private let readBudgetBytes: Int
    private var files: [String: FileState] = [:]

    public init(projectsURL: URL, readBudgetBytes: Int = 67_108_864) {
        self.projectsURL = projectsURL
        self.readBudgetBytes = readBudgetBytes
    }

    public func scan(now: Date = Date()) -> ClaudeCodeUsageSummary {
        var budget = readBudgetBytes
        var seen = Set<String>()
        var complete = true
        let discovered = transcriptFiles()
        complete = discovered.count < Self.maximumFiles
        for (path, size, modified) in discovered {
            var metadata = stat()
            guard lstat(path, &metadata) == 0 else { complete = false; continue }
            let inode = UInt64(metadata.st_ino)
            seen.insert(path)
            var state = files[path] ?? FileState(size: 0, modified: .distantPast, tail: .init(path: path))
            guard state.size != size || state.modified != modified || state.inode != inode || state.tail.offset < size else { continue }
            if state.inode != inode || size < state.tail.offset || (size == state.size && modified != state.modified) { state = FileState(size: 0, modified: .distantPast, tail: .init(path: path)) }
            while budget > 0, state.tail.offset < size {
                let before = state.tail.offset
                for line in state.tail.readLines(maximumBytes: min(budget, 8_388_608)) {
                    for record in ClaudeCodeTranscriptDecoder.records(line, includeSidechain: true) {
                        guard case let .usage(key, model, usage, timestamp) = record else { continue }
                        if let previous = state.entries[key], previous.usage.total >= usage.total { continue }
                        state.entries[key] = Entry(day: Self.localDay(timestamp ?? modified), model: model, usage: usage)
                    }
                }
                let consumed = Int(state.tail.offset - before)
                guard consumed > 0 else { break }
                budget -= consumed
            }
            if state.tail.offset < size { complete = false }
            state.size = size; state.modified = modified; state.inode = inode
            files[path] = state
        }
        files = files.filter { seen.contains($0.key) }
        return summarize(complete: complete, now: now)
    }

    private func summarize(complete: Bool, now: Date) -> ClaudeCodeUsageSummary {
        var unique: [String: Entry] = [:]
        for path in files.keys.sorted() {
            for (key, entry) in files[path]!.entries {
                if unique[key].map({ $0.usage.total >= entry.usage.total }) != true { unique[key] = entry }
            }
        }
        var tokens: [Date: Int64] = [:], costs: [Date: Double] = [:], unpriced = Set<Date>()
        var lifetime: Int64 = 0
        for entry in unique.values {
            tokens[entry.day, default: 0] += entry.usage.total
            lifetime += entry.usage.total
            if let cost = ClaudeCodePricing.cost(model: entry.model, usage: entry.usage) { costs[entry.day, default: 0] += cost }
            else if entry.usage.total > 0 { unpriced.insert(entry.day) }
        }
        let days = tokens.keys.sorted().map {
            ClaudeCodeUsageSummary.Day(date: $0, tokens: tokens[$0] ?? 0,
                                       estimatedCost: unpriced.contains($0) ? nil : (costs[$0] ?? 0))
        }
        return .init(days: days, lifetimeTokens: lifetime, complete: complete, fileCount: files.count, updatedAt: now)
    }

    private func transcriptFiles() -> [(String, UInt64, Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: projectsURL, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [(String, UInt64, Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize else { continue }
            result.append((url.path, UInt64(size), values.contentModificationDate ?? .distantPast))
            if result.count >= Self.maximumFiles { break }
        }
        return result
    }

    public static func localDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: parts) ?? date
    }
}
