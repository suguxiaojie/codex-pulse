import Foundation

enum CostIncrementalTests {
    static func check(_ value: Bool, _ message: String) {
        precondition(value, message)
    }

    static func run() throws {
        let manager = FileManager.default
        let home = URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent(".tmp/perf-cost-incremental/fixtures/\(UUID().uuidString)")
        defer { try? manager.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex/sessions")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rollout-test.jsonl")
        func token(_ input: Int) -> String {
            "{\"timestamp\":\"2026-11-01T06:30:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":2}}}}\n"
        }
        func scan() -> [TokenUsageEvent] {
            CostService.scanCodex(homeDirectory: home, lookbackDays: nil)
        }
        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
        let initial = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"session\",\"cwd\":\"/test\"}}\n" + token(10)
        try Data(initial.utf8).write(to: file)
        check(scan().count == 1, "initial parse")
        let usedRipgrep = CostService.cachedUsedRipgrep(at: file)
        print(usedRipgrep ? "Initial cost parse used ripgrep." : "SKIP ripgrep-specific path: unavailable; streaming fallback exercised.")
        let firstOffset = CostService.cachedReadProgress(at: file)!.offset
        let partial = String(token(30).dropLast(12))
        let addition = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-6\"}}\n" + token(20) + partial
        try append(addition)
        let second = scan()
        check(!CostService.cachedUsedRipgrep(at: file), "append always uses streaming incremental parser")
        check(second.count == 2 && second.last!.model == "gpt-6", "model state and incomplete line")
        let progress = CostService.cachedReadProgress(at: file)!
        check(progress.bytesRead == addition.utf8.count, "read only appended bytes")
        check(progress.offset == firstOffset + UInt64(addition.utf8.count - partial.utf8.count), "offset excludes tail")
        try append(String(token(30).suffix(12)))
        let incremental = scan()
        check(incremental.count == 3 && incremental.last!.sessionID == "session" && incremental.last!.projectPath == "/test", "state survives append")
        let complete = try Data(contentsOf: file)
        try complete.write(to: file, options: .atomic)
        let full = scan()
        check(signature(full) == signature(incremental), "incremental equals fresh full parse")
        check(!usedRipgrep || CostService.cachedUsedRipgrep(at: file), "replacement returns to ripgrep full parser")
        check(CostService.cachedReadProgress(at: file)!.bytesRead == complete.count, "replacement rereads full file")
        try Data(token(40).utf8).write(to: file)
        check(scan().map(\.input) == [40], "truncation resets events")
        try append(token(50))
        try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        check(scan().count == 2 && CostService.cachedReadProgress(at: file)!.bytesRead == token(40).utf8.count + token(50).utf8.count, "mtime rollback resets")
        // Oversized lines span multiple chunks and must never grow a retained line buffer.
        try append(String(repeating: "x", count: (4 << 20) + 10) + token(60) + token(70))
        check(scan().map(\.input) == [40, 50, 70], "oversized line skipped across chunks")
        try append(token(70))
        check(scan().count == 3, "deduplication retained")
        let unterminated = String(token(80).dropLast())
        try Data(unterminated.utf8).write(to: file)
        check(scan().isEmpty && CostService.cachedReadProgress(at: file)!.offset == 0,
              "valid JSON without newline remains pending on initial parse")
        try append("\n")
        check(scan().map(\.input) == [80], "pending initial line commits when newline arrives")
        let sameSizeDate = try manager.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
        try Data(token(90).utf8).write(to: file, options: .atomic)
        try manager.setAttributes([.modificationDate: sameSizeDate], ofItemAtPath: file.path)
        check(scan().map(\.input) == [90], "identity detects equal-size equal-mtime replacement")
        let ignored = "{\"type\":\"response_item\",\"payload\":{\"text\":\"ignored\"}}\n"
        let pendingModel = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-6\"}}"
        try Data((initial + ignored + pendingModel).utf8).write(to: file, options: .atomic)
        check(scan().count == 1, "initial rg parse excludes valid unterminated JSON")
        check(CostService.cachedReadProgress(at: file)!.offset == UInt64((initial + ignored).utf8.count),
              "offset includes final nonmatching newline, not just final rg match")
        try append("\n" + token(20))
        let afterPendingModel = scan()
        check(afterPendingModel.last!.model == "gpt-6", "pending initial model is applied when newline arrives")
        let withTail = try Data(contentsOf: file)
        try withTail.write(to: file, options: .atomic)
        check(signature(scan()) == signature(afterPendingModel), "rg to incremental tail state equals full parse")
        try Data((initial + String(repeating: "x", count: 70_000)).utf8).write(to: file, options: .atomic)
        check(scan().count == 1 && CostService.cachedReadProgress(at: file)!.offset == UInt64(initial.utf8.count),
              "tail search crosses a 64 KiB block without consuming incomplete line")
        try Data(initial.replacingOccurrences(of: "\n", with: "\r\n").utf8).write(to: file, options: .atomic)
        check(scan().count == 1, "rg preserves CRLF input")
        // Each refresh scans a 30-day window and then the full history. An old rollout outside
        // the window must stay cached across both scans instead of being re-parsed every time.
        let old = directory.appendingPathComponent("rollout-old.jsonl")
        try Data(("{\"type\":\"session_meta\",\"payload\":{\"id\":\"old\",\"cwd\":\"/old\"}}\n" + token(5)).utf8).write(to: old)
        try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -90 * 86_400)], ofItemAtPath: old.path)
        _ = scan()
        let oldEntry = CostService.cachedReadProgress(at: old)
        check(oldEntry != nil, "full-history scan caches old rollouts")
        _ = CostService.scanCodex(homeDirectory: home, lookbackDays: 30)
        check(CostService.cachedReadProgress(at: old) != nil, "a 30-day scan keeps older cached rollouts")
        CostService.resetReadCounters(at: old)
        _ = scan()
        check(CostService.cachedReadProgress(at: old)?.bytesRead == 0, "full-history scan reuses the cache instead of re-parsing")
        try manager.removeItem(at: old)
        try manager.removeItem(at: file)
        check(scan().isEmpty && CostService.cachedReadProgress(at: file) == nil, "removed files evicted")
        try verifyDates()
        print("Incremental cost parsing and differential date tests passed.")
    }

    private static func signature(_ events: [TokenUsageEvent]) -> [String] {
        events.map { "\($0.provider)|\($0.timestamp)|\($0.model)|\($0.sessionID)|\($0.projectPath)|\($0.input)|\($0.output)|\($0.cacheCreate)|\($0.cacheRead)" }
    }

    private static func verifyDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let context = UsageAccountContext(
            accounts: [UsageAccountOption(id: "a", alias: "A", emailSummary: nil, isCurrent: true)],
            accountIDByThread: ["s0": "a"], accountTimeline: [])
        let formatter = ISO8601DateFormatter()
        for raw in ["2026-03-08T17:00:00Z", "2026-11-01T17:00:00Z"] {
            let now = formatter.date(from: raw)!
            let today = calendar.startOfDay(for: now)
            var events: [TokenUsageEvent] = []
            for day in -181...2 {
                let start = calendar.date(byAdding: .day, value: day, to: today)!
                for seconds in [0, 3599, 3600, 5400, 7200, 9000, 10800, 86399] {
                    events.append(TokenUsageEvent(provider: .codex,
                        timestamp: start.addingTimeInterval(Double(seconds)), model: "gpt-5.4",
                        sessionID: "s\(abs(day) % 3)", projectPath: "/test",
                        input: abs(day) + seconds + 1, output: 3, cacheCreate: 2, cacheRead: 1))
                }
            }
            for activity in [false, true] {
                let old = CostSummaryReference.summarize(events, projectNames: [:], accountContext: context, now: now, calendar: calendar, includeActivity: activity)
                let new = CostService.summarize(events, projectNames: [:], accountContext: context, now: now, calendar: calendar, includeActivity: activity)
                check(old == new, "all summary fields match across DST, boundaries and future events: \(raw), \(activity)")
            }
            if raw.contains("11-01") {
                let large = (0..<100_000).map { events[$0 % events.count] }
                let start = Date()
                let old = CostSummaryReference.summarize(large, projectNames: [:], accountContext: context, now: now, calendar: calendar)
                let oldSeconds = Date().timeIntervalSince(start)
                let next = Date()
                let new = CostService.summarize(large, projectNames: [:], accountContext: context, now: now, calendar: calendar)
                let newSeconds = Date().timeIntervalSince(next)
                check(old == new, "100k summaries exactly equal")
                print(String(format: "100k summarize: old %.3fs, new %.3fs, speedup %.2fx", oldSeconds, newSeconds, oldSeconds / newSeconds))
            }
        }
    }
}
