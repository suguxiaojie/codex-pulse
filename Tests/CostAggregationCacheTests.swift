import Foundation

enum CostAggregationCacheTests {
    private static let context = UsageAccountContext(
        accounts: [UsageAccountOption(id: "a", alias: "A", emailSummary: nil, isCurrent: true)],
        accountIDByThread: ["s0": "a"], accountTimeline: [])
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private static let now = Date(timeIntervalSince1970: 1_793_640_000)

    private static func event(_ index: Int, time: Date? = nil, model: String = "gpt-5.4", project: String? = nil) -> TokenUsageEvent {
        TokenUsageEvent(provider: .codex, timestamp: time ?? now.addingTimeInterval(Double(index - 100_000)),
            model: model, sessionID: "s\(index % 7)", projectPath: project ?? "/project\(index % 3)",
            input: index % 1000 + 10, output: index % 71 + 1, cacheCreate: index % 13, cacheRead: index % 17)
    }

    private static func file(_ path: String, _ events: [TokenUsageEvent], generation: UUID = UUID()) -> CostService.FileEvents {
        CostService.FileEvents(path: path, entry: CostService.ParsedFileCacheEntry(generation: generation,
            modificationDate: now, fileSize: 0, events: events, identity: "1:1", offset: 0,
            state: CostService.ParseState(sessionID: path), bytesRead: 0, usedRipgrep: false))
    }

    static func run() throws {
        setbuf(stdout, nil)
        try differential()
        boundaryCases()
        try disk()
        benchmark()
        print("Round 3 aggregation and disk-cache tests passed.")
    }

    private static func differential() throws {
        var seed: UInt64 = 0xC057
        func random(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        for activity in [false, true] {
            let cache = CostService.AggregationCache()
            var files = (0..<5).map { file("/file\($0)", []) }
            var next = 0
            var overrides: [String: String] = [:]
            var catalog = CodexProjectCatalog.State.empty
            var account = context
            var clock = now
            var revision: Date?
            func compare(_ label: String, incremental expected: Bool? = nil) {
                let actual = cache.update(files: files, overrides: overrides, catalog: catalog, context: account,
                    now: clock, calendar: calendar, includeActivity: activity, pricingRevision: revision)
                let events = CostService.remapEvents(CostService.deduplicated(files.flatMap { $0.entry.events }),
                    sessionPathOverrides: overrides, catalog: catalog)
                let reference = CostService.summarize(events, projectNames: catalog.namesByPath,
                    accountContext: account, now: clock, calendar: calendar, includeActivity: activity)
                precondition(actual == reference, "Differential mismatch: \(label), activity=\(activity)")
                if let expected { precondition(cache.lastUpdateWasIncremental == expected, "Expected incremental=\(expected): \(label), got \(cache.lastFallbackReason)") }
            }
            compare("initial", incremental: false)
            for round in 0..<90 {
                for _ in 0..<random(20)+1 {
                    let index = random(files.count)
                    let old = files[index]
                    let value = event(next, model: next % 11 == 0 ? "codex-auto-review" : (next % 7 == 0 ? "unpriced" : "gpt-5.4"))
                    files[index] = file(old.path, old.entry.events + [value], generation: old.entry.generation)
                    next += 1
                }
                compare("random append \(round)")
                switch round {
                case 3:
                    compare("unchanged", incremental: true)
                    precondition(cache.processedEvents == 0)
                case 8:
                    files[0] = file(files[0].path, [event(next)])
                    next += 1
                    compare("replace", incremental: false)
                case 15:
                    files[0] = file(files[0].path, [])
                    compare("truncate", incremental: false)
                case 22:
                    files.removeLast()
                    compare("delete", incremental: false)
                case 29:
                    overrides = ["s0": "/renamed"]
                    compare("override", incremental: false)
                case 36:
                    catalog = CodexProjectCatalog.State(namesByPath: ["/renamed": "Renamed"], assignmentsByThread: [
                        "s1": CodexProjectCatalog.Assignment(projectID: "p", projectName: "New", path: "/new")])
                    compare("catalog", incremental: false)
                case 43:
                    account = UsageAccountContext(accounts: context.accounts, accountIDByThread: [:],
                        accountTimeline: [UsageAccountObservation(accountID: "a", startsAt: now.addingTimeInterval(-99_500))])
                    compare("account", incremental: false)
                case 50:
                    clock = now.addingTimeInterval(86_400)
                    compare("day", incremental: false)
                case 57:
                    revision = clock
                    compare("pricing", incremental: false)
                case 64:
                    let old = files[0]
                    files[0] = file(old.path, old.entry.events + [files[1].entry.events[0]], generation: old.entry.generation)
                    compare("duplicate", incremental: false)
                case 71:
                    let old = files[0]
                    files[0] = file(old.path, old.entry.events + [event(next, time: now.addingTimeInterval(-200_000))], generation: old.entry.generation)
                    compare("out of order", incremental: false)
                default: break
                }
            }
        }
        // Strictly later events take the actual fast path, including internal billing-model changes.
        let cache = CostService.AggregationCache()
        var files = [file("/a", [event(0)])]
        _ = cache.update(files: files, context: context, now: now, calendar: calendar)
        for i in 1...30 {
            let old = files[0]
            files[0] = file(old.path, old.entry.events + [event(i, model: i % 2 == 0 ? "codex-auto-review" : "gpt-6-astra")], generation: old.entry.generation)
            let actual = cache.update(files: files, context: context, now: now, calendar: calendar)
            precondition(cache.lastUpdateWasIncremental && cache.processedEvents == 1)
            precondition(actual == CostService.summarize(files[0].entry.events, projectNames: [:], accountContext: context, now: now, calendar: calendar))
        }
        // Equal names and token totals must not expose dictionary iteration order.
        let ties = [event(0, project: "/a/same"), event(0, project: "/b/same")]
        let tieCache = CostService.AggregationCache()
        let tieFiles = [file("/ties", ties)]
        let result = tieCache.update(files: tieFiles, context: context, now: now, calendar: calendar)
        precondition(result == CostService.summarize(CostService.deduplicated(ties), projectNames: [:], accountContext: context, now: now, calendar: calendar))
        print("Random multi-file differential: 2 windows × 90 rounds, required invalidations passed.")
    }

    private static func boundaryCases() {
        for raw in ["2026-03-08T17:00:00Z", "2026-11-01T17:00:00Z"] {
            let clock = ISO8601DateFormatter().date(from: raw)!
            for activity in [false, true] {
                let cache = CostService.AggregationCache()
                let events = (-181...0).flatMap { day in
                    [0, 3599, 5400, 9000, 86399].map { seconds in
                        event(abs(day) + seconds, time: calendar.startOfDay(for: clock).addingTimeInterval(Double(day * 86400 + seconds)))
                    }
                }
                var files = [file("/dst", events)]
                func compare(_ now: Date) {
                    let actual = cache.update(files: files, context: context, now: now, calendar: calendar, includeActivity: activity)
                    let expected = CostService.summarize(CostService.deduplicated(files.flatMap { $0.entry.events }),
                        projectNames: [:], accountContext: context, now: now, calendar: calendar, includeActivity: activity)
                    precondition(actual == expected, "DST/180-day/future boundary \(raw)")
                }
                compare(clock)
                compare(clock.addingTimeInterval(3600))
                precondition(cache.lastFallbackReason == "future event clock")
                let old = files[0]
                files[0] = file(old.path, old.entry.events + [event(999, time: clock.addingTimeInterval(-86400))], generation: old.entry.generation)
                compare(clock.addingTimeInterval(3600))
                precondition(cache.lastFallbackReason == "out-of-order event")
            }
        }
        // A new override alias may change old events from another session.
        let cache = CostService.AggregationCache()
        let overrides = ["s1": "/new"]
        let first = event(0, project: "/old")
        var files = [file("/aliases", [first])]
        _ = cache.update(files: files, overrides: overrides, context: context, now: now, calendar: calendar)
        files = [file("/aliases", [first, event(1, project: "/old")], generation: files[0].entry.generation)]
        let actual = cache.update(files: files, overrides: overrides, context: context, now: now, calendar: calendar)
        precondition(cache.lastFallbackReason == "retroactive path alias")
        precondition(actual == CostService.summarize(CostService.remapEvents(files[0].entry.events,
            sessionPathOverrides: overrides, catalog: .empty), projectNames: [:], accountContext: context, now: now, calendar: calendar))
        // Exercise deterministic project ties without deduplicating the two sessions.
        let tieEvents = [event(0, project: "/a/same"), TokenUsageEvent(provider: .codex,
            timestamp: first.timestamp, model: first.model, sessionID: "other", projectPath: "/b/same",
            input: first.input, output: first.output, cacheCreate: first.cacheCreate, cacheRead: first.cacheRead)]
        let tieResult = CostService.AggregationCache().update(files: [file("/ties", tieEvents)], context: context, now: now, calendar: calendar)
        precondition(tieResult == CostService.summarize(tieEvents, projectNames: [:], accountContext: context, now: now, calendar: calendar))
        print("DST, 180-day boundaries, future-clock, late events, retroactive aliases and project ties passed.")
    }

    static func verifyPricing() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let cache = CostService.AggregationCache()
            let files = [file("/prices", [event(0, model: "round3-custom"), event(1, model: "gpt-6-astra")])]
            let before = cache.update(files: files, context: context, now: now, calendar: calendar)
            let rate = CatalogRates(displayName: nil, inputPerMillion: 3, outputPerMillion: 7,
                cacheCreationPerMillion: 2, cacheReadPerMillion: 1)
            let payload = CatalogPayload(schemaVersion: 1, generatedAt: "2026-10-27T00:00:00Z", models: ["round3-custom": rate])
            let community = await PricingCatalog.refreshIfNeeded(now: now, cache: nil, fetch: { _ in
                (try JSONEncoder().encode(payload), HTTPURLResponse(url: PricingCatalog.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            precondition(community == .updated)
            let after = cache.update(files: files, context: context, now: now, calendar: calendar)
            precondition(cache.lastFallbackReason == "pricing" && after.month.dollars != before.month.dollars)
            precondition(after == CostService.summarize(files[0].entry.events, projectNames: [:], accountContext: context, now: now, calendar: calendar))
            let header = "| Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |"
            let rows = OfficialPricingCatalog.requiredModels.sorted().map { "| \($0) | $20 | $1 | $25 | $100 | $40 | $2 | $50 | $150 |" }.joined(separator: "\n")
            let document = "Short context: ≤272K input tokens. Long context: >272K input tokens.\n### Standard pricing data\n" + header + "\n" + rows + "\n### Batch\n"
            let official = await OfficialPricingCatalog.refreshIfNeeded(now: now, cache: nil, fetch: { _ in
                (Data(document.utf8), HTTPURLResponse(url: OfficialPricingCatalog.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            precondition(official == .updated)
            let final = cache.update(files: files, context: context, now: now, calendar: calendar)
            precondition(cache.lastFallbackReason == "pricing" && final.month.dollars != after.month.dollars)
            precondition(final == CostService.summarize(files[0].entry.events, projectNames: [:], accountContext: context, now: now, calendar: calendar))
            print("Both real catalog installation paths invalidate aggregation (injected responses, no network/cache writes).")
            done.signal()
        }
        precondition(done.wait(timeout: .now() + 30) == .success)
    }

    private static func disk() throws {
        let manager = FileManager.default
        let home = URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent(".tmp/perf-round3/fixtures-\(UUID().uuidString)")
        try manager.createDirectory(at: home.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
        defer { CostService.resetCacheForTesting(diskURL: nil); try? manager.removeItem(at: home) }
        let url = home.appendingPathComponent(".codex/sessions/test.jsonl")
        let diskURL = home.appendingPathComponent("cache/entries.plist")
        let first = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"s0\",\"cwd\":\"/test\",\"message\":\"PRIVATE_CONVERSATION_SENTINEL\"}}\n" +
            "{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-6-astra\"}}\n"
        func token(_ i: Int) -> String {
            "{\"timestamp\":\"2026-10-27T01:00:\(String(format: "%02d", i))Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":\(i + 10),\"output_tokens\":2}}}}\n"
        }
        try Data((first + token(0)).utf8).write(to: url)
        CostService.resetCacheForTesting(diskURL: diskURL)
        let service = CostService(preparePricing: false)
        let cold = service.snapshotForTesting(home: home, now: now)
        precondition(CostService.cachedReadProgress(at: url)!.bytesRead > 0)
        CostService.flushDiskCache()
        let data = try Data(contentsOf: diskURL)
        let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        precondition(!String(describing: decoded).contains("PRIVATE_CONVERSATION_SENTINEL"))
        print("Synthetic disk cache: \(data.count) bytes for one event (includes envelope and parse state).")
        CostService.resetCacheForTesting(diskURL: diskURL)
        let restarted = CostService(preparePricing: false)
        let warm = restarted.snapshotForTesting(home: home, now: now)
        precondition(cold == warm && CostService.cachedReadProgress(at: url)!.bytesRead == 0)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(token(1).utf8))
        try handle.close()
        _ = restarted.snapshotForTesting(home: home, now: now)
        precondition(CostService.cachedReadProgress(at: url)!.bytesRead == token(1).utf8.count)
        let appended = CostService.scanCodex(homeDirectory: home, lookbackDays: nil)
        precondition(appended.last!.model == "gpt-6-astra" && appended.last!.sessionID == "s0" && appended.last!.projectPath == "/test")
        let partial = String(token(2).dropLast(8))
        let tail = try FileHandle(forWritingTo: url)
        try tail.seekToEnd()
        try tail.write(contentsOf: Data(partial.utf8))
        try tail.close()
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil).count == 2)
        CostService.flushDiskCache()
        CostService.resetCacheForTesting(diskURL: diskURL)
        let completion = try FileHandle(forWritingTo: url)
        try completion.seekToEnd()
        try completion.write(contentsOf: Data(token(2).suffix(8).utf8))
        try completion.close()
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil).count == 3)
        precondition(CostService.cachedReadProgress(at: url)!.bytesRead == token(2).utf8.count)
        CostService.flushDiskCache()
        CostService.resetCacheForTesting(diskURL: diskURL)
        try Data((first + token(9)).utf8).write(to: url, options: .atomic)
        let replaced = CostService.scanCodex(homeDirectory: home, lookbackDays: nil)
        precondition(replaced.count == 1 && replaced[0].input == 19 && CostService.cachedReadProgress(at: url)!.bytesRead > 0)
        CostService.flushDiskCache()
        var wrong = try PropertyListSerialization.propertyList(from: Data(contentsOf: diskURL), format: nil) as! [String: Any]
        wrong["version"] = 999
        try PropertyListSerialization.data(fromPropertyList: wrong, format: .binary, options: 0).write(to: diskURL, options: .atomic)
        CostService.resetCacheForTesting(diskURL: diskURL)
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil) == replaced)
        precondition(CostService.cachedReadProgress(at: url)!.bytesRead > 0)
        CostService.flushDiskCache()
        try Data("corrupt cache".utf8).write(to: diskURL, options: .atomic)
        CostService.resetCacheForTesting(diskURL: diskURL)
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil) == replaced)
        precondition(CostService.cachedReadProgress(at: url)!.bytesRead > 0)
        CostService.flushDiskCache()
        try manager.removeItem(at: url)
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil).isEmpty)
        CostService.flushDiskCache()
        let empty = try PropertyListSerialization.propertyList(from: Data(contentsOf: diskURL), format: nil) as! [String: Any]
        precondition((empty["entries"] as! [String: Any]).isEmpty)
        let compressed = home.appendingPathComponent(".codex/sessions/fixture.jsonl.zst")
        try manager.copyItem(at: URL(fileURLWithPath: "Tests/Fixtures/CompressedRollouts/user.jsonl.zst"), to: compressed)
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil).count == 1)
        CostService.flushDiskCache()
        CostService.resetCacheForTesting(diskURL: diskURL)
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil).count == 1)
        try Data("corrupt replacement".utf8).write(to: compressed, options: .atomic)
        precondition(CostService.scanCodex(homeDirectory: home, lookbackDays: nil).isEmpty)
        precondition(CostService.cachedReadProgress(at: compressed) == nil)
        print("Disk restart, zero reads, append bytes, persisted partial tail/state, replacement, corrupt/version fallback, deletion, compressed read failure and privacy passed.")
    }

    private static func benchmark() {
        for count in [100_000, 1_000_000] {
            let events = (0..<count).map { event($0, time: now.addingTimeInterval(Double($0 - count))) }
            let files = [file("/benchmark", events)]
            let start = Date()
            let full = CostService.summarize(events, projectNames: [:], accountContext: context, now: now, calendar: calendar)
            let fullTime = Date().timeIntervalSince(start)
            let cache = CostService.AggregationCache()
            let seeded = cache.update(files: files, context: context, now: now, calendar: calendar)
            precondition(seeded == full)
            let extra = (0..<100).map { event($0, time: now.addingTimeInterval(Double($0) / 1000)) }
            let updated = [file("/benchmark", events + extra, generation: files[0].entry.generation)]
            let next = Date()
            let incremental = cache.update(files: updated, context: context, now: now, calendar: calendar)
            let incrementalTime = Date().timeIntervalSince(next)
            print(String(format: "Project ranking + snapshot materialization: %.6fs", cache.lastMaterializationSeconds))
            precondition(cache.lastUpdateWasIncremental && cache.processedEvents == 100)
            let comparisonStart = Date()
            let reference = CostService.summarize(events + extra, projectNames: [:], accountContext: context, now: now, calendar: calendar)
            let comparisonTime = Date().timeIntervalSince(comparisonStart)
            precondition(incremental == reference)
            print(String(format: "Round3 %d events: full %.6fs; full+100 %.6fs; incremental+100 %.6fs; ratio %.2fx", count, fullTime, comparisonTime, incrementalTime, comparisonTime / incrementalTime))
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let bytes = try! encoder.encode(files[0].entry).count
            print("Synthetic parse entry \(count) events: \(bytes) bytes, \(Double(bytes) / Double(count)) bytes/event.")
        }
    }
}
