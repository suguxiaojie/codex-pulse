import Foundation

enum CostProvider: String, CaseIterable, Codable {
    case codex = "Codex"
}

struct CostTotals: Equatable {
    var dollars: Double = 0
    var tokens: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheTokens: Int = 0
    var series: [Double] = []
}

enum UsagePeriod: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"

    var id: String { rawValue }

    var activityDayCount: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    var emptyActivityTitle: String {
        switch self {
        case .day: return "今日暂无活动"
        case .week: return "近 7 日暂无活动"
        case .month: return "近 30 日暂无活动"
        }
    }
}

enum UsageTrendPeriod: String, CaseIterable, Identifiable {
    case week = "周"
    case month = "月"
    case quarter = "三月"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }

    var emptyHistoryTitle: String {
        switch self {
        case .week: return "近 7 日暂无活动"
        case .month: return "近 30 日暂无活动"
        case .quarter: return "近 90 日暂无活动"
        }
    }
}

enum ActivityPeriod: String, CaseIterable, Identifiable {
    case month = "30 日"
    case quarter = "90 日"
    case halfYear = "半年"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .halfYear: return 180
        }
    }
}

struct ProjectUsage: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    var tokens: Int
    var sessionCount: Int
}

struct UsageTotals: Equatable {
    var tokens: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheTokens: Int = 0
    var sessionCount: Int = 0
    var projectCount: Int = 0
    var series: [Double] = []
    var projects: [ProjectUsage] = []
}

struct DailyTokenActivity: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let tokens: Int
}

struct DailyCostActivity: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let dollars: Double
}

struct UsageSnapshot: Equatable {
    var day: UsageTotals
    var week: UsageTotals
    var month: UsageTotals
    var quarter: UsageTotals
    var activity: [DailyTokenActivity]
    var activityIsReady: Bool

    func totals(for period: UsagePeriod) -> UsageTotals {
        switch period {
        case .day: return day
        case .week: return week
        case .month: return month
        }
    }

    func totals(for period: UsageTrendPeriod) -> UsageTotals {
        switch period {
        case .week: return week
        case .month: return month
        case .quarter: return quarter
        }
    }

    static let empty = UsageSnapshot(
        day: UsageTotals(series: Array(repeating: 0, count: 24)),
        week: UsageTotals(series: Array(repeating: 0, count: 7)),
        month: UsageTotals(series: Array(repeating: 0, count: 30)),
        quarter: UsageTotals(series: Array(repeating: 0, count: 90)),
        activity: [],
        activityIsReady: false
    )
}

struct ProviderCostTotals: Identifiable, Equatable {
    var id: String { provider.rawValue }
    let provider: CostProvider
    var today: CostTotals
    var week: CostTotals
    var month: CostTotals

    func totals(for period: UsagePeriod) -> CostTotals {
        switch period {
        case .day: return today
        case .week: return week
        case .month: return month
        }
    }
}

struct CostScopeSnapshot: Equatable {
    var today: CostTotals
    var week: CostTotals
    var month: CostTotals
    var providers: [ProviderCostTotals]
    var unknownModels: [String]
    var estimatedModelAliases: [String: String]
    var usage: UsageSnapshot
    var costActivity: [DailyCostActivity]
    var lifetimeTokens: Int? = nil

    func totals(for period: UsagePeriod) -> CostTotals {
        switch period {
        case .day: return today
        case .week: return week
        case .month: return month
        }
    }

    static let empty = CostScopeSnapshot(
        today: CostTotals(series: Array(repeating: 0, count: 24)),
        week: CostTotals(series: Array(repeating: 0, count: 7)),
        month: CostTotals(series: Array(repeating: 0, count: 30)),
        providers: CostProvider.allCases.map {
            ProviderCostTotals(
                provider: $0,
                today: CostTotals(),
                week: CostTotals(),
                month: CostTotals()
            )
        },
        unknownModels: [],
        estimatedModelAliases: [:],
        usage: .empty,
        costActivity: []
    )
}

struct CostSnapshot: Equatable {
    var aggregate: CostScopeSnapshot
    var byAccount: [String: CostScopeSnapshot]
    var unknownAccount: CostScopeSnapshot
    var updatedAt: Date

    var today: CostTotals { aggregate.today }
    var week: CostTotals { aggregate.week }
    var month: CostTotals { aggregate.month }
    var providers: [ProviderCostTotals] { aggregate.providers }
    var unknownModels: [String] { aggregate.unknownModels }
    var estimatedModelAliases: [String: String] { aggregate.estimatedModelAliases }
    var usage: UsageSnapshot { aggregate.usage }
    var costActivity: [DailyCostActivity] { aggregate.costActivity }

    func scope(for id: String) -> CostScopeSnapshot {
        if id == UsageAccountScope.unknown { return unknownAccount }
        if id == UsageAccountScope.all { return aggregate }
        return byAccount[id] ?? .empty
    }

    func totals(for period: UsagePeriod) -> CostTotals {
        aggregate.totals(for: period)
    }

    static let empty = CostSnapshot(
        aggregate: .empty,
        byAccount: [:],
        unknownAccount: .empty,
        updatedAt: .distantPast
    )
}

struct TokenUsageEvent: Codable, Equatable {
    let provider: CostProvider
    let timestamp: Date
    let model: String
    let sessionID: String
    let projectPath: String
    let input: Int
    let output: Int
    let cacheCreate: Int
    let cacheRead: Int

    func withProjectPath(_ value: String) -> TokenUsageEvent {
        TokenUsageEvent(
            provider: provider,
            timestamp: timestamp,
            model: model,
            sessionID: sessionID,
            projectPath: URL(fileURLWithPath: value).standardizedFileURL.path,
            input: input,
            output: output,
            cacheCreate: cacheCreate,
            cacheRead: cacheRead
        )
    }
}

final class CostService {
    private let queue = DispatchQueue(label: "CodexNotchMonitor.Cost", qos: .utility)

    struct ParsedFileCacheEntry: Codable {
        var generation = UUID()
        let modificationDate: Date
        let fileSize: Int
        let events: [TokenUsageEvent]
        let identity: String?
        let offset: UInt64
        let state: ParseState
        var bytesRead: UInt64
        let usedRipgrep: Bool
    }

    struct ParseState: Codable {
        var model = "gpt-5.4"
        var sessionID: String
        var projectPath = "未归类"
    }

    // Internal diagnostics let regression tests verify actual incremental I/O.
    static func cachedReadProgress(at url: URL) -> (offset: UInt64, bytesRead: UInt64)? {
        parsedFileCacheLock.lock()
        defer { parsedFileCacheLock.unlock() }
        return parsedFileCache[url.path].map { ($0.offset, $0.bytesRead) }
    }

    /// Test hook: zero the read counter so a later scan proves whether the file was re-read.
    static func resetReadCounters(at url: URL) {
        parsedFileCacheLock.lock()
        defer { parsedFileCacheLock.unlock() }
        parsedFileCache[url.path]?.bytesRead = 0
    }

    static func cachedUsedRipgrep(at url: URL) -> Bool {
        parsedFileCacheLock.lock()
        defer { parsedFileCacheLock.unlock() }
        return parsedFileCache[url.path]?.usedRipgrep ?? false
    }

    private static let parsedFileCacheLock = NSLock()
    private static var parsedFileCache: [String: ParsedFileCacheEntry] = [:]

    private let recentSummary = AggregationCache()
    private let historySummary = AggregationCache()

    init(preparePricing: Bool = true) {
        guard preparePricing else { return }
        PricingCatalog.prepare()
        OfficialPricingCatalog.prepare()
    }

    func snapshotForTesting(home: URL, now: Date) -> CostSnapshot {
        historySummary.update(files: Self.scanFiles(homeDirectory: home, lookbackDays: nil),
            context: UsageAccountContext(accounts: [], accountIDByThread: [:], accountTimeline: []), now: now)
    }

    func fetch(
        qos: DispatchQoS.QoSClass = .utility,
        sessionPathOverrides: [String: String] = [:],
        accountContext: UsageAccountContext = UsageAccountContext(
            accounts: [],
            accountIDByThread: [:],
            accountTimeline: []
        ),
        completion: @escaping (CostSnapshot) -> Void
    ) {
        queue.async(qos: DispatchQoS(qosClass: qos, relativePriority: 0), flags: .enforceQoS) {
            let catalog = CodexProjectCatalog.loadState()
            let snapshot = self.recentSummary.update(
                files: Self.scanFiles(lookbackDays: 30), overrides: sessionPathOverrides,
                catalog: catalog, context: accountContext, includeActivity: false
            )
            DispatchQueue.main.async { completion(snapshot) }
            let activitySnapshot = self.historySummary.update(
                files: Self.scanFiles(lookbackDays: nil), overrides: sessionPathOverrides,
                catalog: catalog, context: accountContext, includeActivity: true
            )
            DispatchQueue.main.async { completion(activitySnapshot) }

            // The first result is deliberately local and immediate. Refresh
            // public pricing in the background, then recalculate only when a
            // new catalog was actually installed.
            Task {
                async let official = OfficialPricingCatalog.refreshIfNeeded()
                async let community = PricingCatalog.refreshIfNeeded()
                let results = await (official, community)
                guard results.0 != .notNeeded || results.1 != .notNeeded else { return }
                self.queue.async {
                    let refreshed = self.historySummary.update(
                        files: Self.scanFiles(lookbackDays: nil), overrides: sessionPathOverrides,
                        catalog: catalog, context: accountContext, includeActivity: true
                    )
                    DispatchQueue.main.async { completion(refreshed) }
                }
            }
        }
    }

    static func remapEvents(
        _ scanned: [TokenUsageEvent],
        sessionPathOverrides: [String: String],
        catalog: CodexProjectCatalog.State
    ) -> [TokenUsageEvent] {
        var pathAliases: [String: String] = [:]
        for event in scanned {
            guard catalog.assignmentsByThread[event.sessionID] == nil,
                  let override = sessionPathOverrides[event.sessionID],
                  !override.isEmpty
            else { continue }
            let normalized = URL(fileURLWithPath: override).standardizedFileURL.path
            if normalized != event.projectPath { pathAliases[event.projectPath] = normalized }
        }
        return scanned.map { event in
            // Moving an existing thread to another Codex project updates
            // thread-project-assignments but does not rewrite historical
            // session_meta.cwd. The explicit assignment is the current
            // ownership truth and must beat live/path-history overrides.
            if let assignment = catalog.assignmentsByThread[event.sessionID] {
                return event.withProjectPath(assignment.path)
            }
            if let override = sessionPathOverrides[event.sessionID], !override.isEmpty {
                return event.withProjectPath(override)
            }
            if let alias = pathAliases[event.projectPath] {
                return event.withProjectPath(alias)
            }
            return event
        }
    }

    /// Reads both live and archived Codex rollouts. Codex moves a rollout from
    /// `sessions` to `archived_sessions` when the user archives a task, but the
    /// token history remains valid for Usage and Cost. Treating the live tree
    /// as the only source made historical totals shrink after archiving.
    static func scanCodex(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackDays: Int? = 180
    ) -> [TokenUsageEvent] {
        deduplicated(scanFiles(homeDirectory: homeDirectory, now: now,
                               calendar: calendar, lookbackDays: lookbackDays).flatMap { $0.entry.events })
    }

    static func scanFiles(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(), calendar: Calendar = .current, lookbackDays: Int? = 180
    ) -> [FileEvents] {
        loadDiskCache(homeDirectory: homeDirectory)
        let root = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        let todayStart = calendar.startOfDay(for: now)
        let activityStart = calendar.date(
            byAdding: .day,
            value: -(max(1, lookbackDays ?? 180) - 1),
            to: todayStart
        ) ?? todayStart
        let earliestRelevantDate = lookbackDays == nil ? Date.distantPast : activityStart
        // A thread can continue receiving token events long after the month in
        // which its rollout file was created. Filter the complete live tree by
        // modification time so rolling windows do not omit such long-running
        // sessions merely because their directory is older.
        let allLiveFiles = jsonlFiles(in: root)
        let liveFiles = allLiveFiles.filter {
            modificationDate(of: $0) >= earliestRelevantDate
        }
        let archiveRoot = homeDirectory.appendingPathComponent(
            ".codex/archived_sessions",
            isDirectory: true
        )
        // archived_sessions is normally flat. Filter by the rollout's last
        // content change so a large archive does not need to be parsed on every
        // refresh; any rollout containing a current 180-day activity event must
        // have been written during that same range.
        let allArchivedFiles = jsonlFiles(in: archiveRoot)
        let archivedFiles = allArchivedFiles.filter {
            modificationDate(of: $0) >= earliestRelevantDate
        }
        // A resumed plain file may contain newer events while a compressed
        // sibling retains older history. Merge records, not filename stems.
        let files: [FileEvents] = (liveFiles + archivedFiles).compactMap { url in
            // Release temporary Foundation read buffers before scanning the next file.
            autoreleasepool {
                _ = cachedParseCodexFile(url)
                parsedFileCacheLock.lock()
                defer { parsedFileCacheLock.unlock() }
                return parsedFileCache[url.path].map { FileEvents(path: url.path, entry: $0) }
            }
        }
        // Evict only rollouts that no longer exist. Each refresh scans 30 days and then the
        // full history; evicting by this call's window made the two scans wipe each other's
        // entries and re-parse every older (including compressed) rollout every 5 minutes.
        let existingPaths = Set((allLiveFiles + allArchivedFiles).map(\.path))
        parsedFileCacheLock.lock()
        let kept = parsedFileCache.filter { existingPaths.contains($0.key) }
        if kept.count != parsedFileCache.count { diskDirty = true }
        parsedFileCache = kept
        parsedFileCacheLock.unlock()
        scheduleDiskWrite()
        return files
    }

    private static func cachedParseCodexFile(_ url: URL) -> [TokenUsageEvent] {
        // Serialize cache reads and updates, including parsing across service instances.
        parsedFileCacheLock.lock()
        defer { parsedFileCacheLock.unlock() }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber
        else {
            if parsedFileCache.removeValue(forKey: url.path) != nil { diskDirty = true }
            return []
        }
        let fileSize = size.intValue
        let identity = (attributes[.systemNumber] as? NSNumber).flatMap { device in
            (attributes[.systemFileNumber] as? NSNumber).map { "\(device):\($0)" }
        }
        let compressed = RolloutReader.isCompressed(url)
        let cached = parsedFileCache[url.path]
        if let cached, cached.modificationDate == modificationDate,
           cached.fileSize == fileSize, (identity != nil && cached.identity == identity) {
            return cached.events
        }
        let append = !compressed && identity != nil && cached?.identity == identity &&
            fileSize > (cached?.fileSize ?? Int.max) &&
            modificationDate >= (cached?.modificationDate ?? .distantFuture)
        var state = append ? cached!.state : ParseState(sessionID: url.deletingPathExtension().lastPathComponent)
        var offset = append ? cached!.offset : 0
        var bytesRead: UInt64 = 0
        var usedRipgrep = false
        do {
            let added = try parseCodexFile(url, state: &state, offset: &offset,
                                          limit: UInt64(fileSize), bytesRead: &bytesRead,
                                          preferRipgrep: !append && !compressed, usedRipgrep: &usedRipgrep)
            let events = append ? cached!.events + added : added
            parsedFileCache[url.path] = ParsedFileCacheEntry(
                generation: append ? cached!.generation : UUID(),
                modificationDate: modificationDate, fileSize: fileSize, events: events,
                identity: identity, offset: offset, state: state, bytesRead: bytesRead, usedRipgrep: usedRipgrep
            )
            diskDirty = true
            return events
        } catch {
            // A failed append may retain its verified prefix. A replacement must never
            // resurrect events from the old inode or old, longer file.
            if append { return cached?.events ?? [] }
            if parsedFileCache.removeValue(forKey: url.path) != nil { diskDirty = true }
            return []
        }
    }

    struct TokenEventIdentity: Hashable {
        let sessionID: String
        let timestamp: Date
        let model: String
        let input: Int
        let output: Int
        let cacheCreate: Int
        let cacheRead: Int
    }

    /// Moving a rollout is usually atomic, but interrupted migrations or a
    /// copied archive can temporarily leave the same JSONL in both roots.
    /// De-duplicate structural token records without using projectPath, because
    /// the same session may legitimately carry a newer renamed project path.
    static func deduplicated(_ events: [TokenUsageEvent]) -> [TokenUsageEvent] {
        var seen = Set<TokenEventIdentity>()
        return events.filter { event in
            seen.insert(TokenEventIdentity(
                sessionID: event.sessionID,
                timestamp: event.timestamp,
                model: event.model,
                input: event.input,
                output: event.output,
                cacheCreate: event.cacheCreate,
                cacheRead: event.cacheRead
            )).inserted
        }
    }

    private static func parseCodexFile(
        _ url: URL, state: inout ParseState, offset: inout UInt64,
        limit: UInt64, bytesRead: inout UInt64, preferRipgrep: Bool, usedRipgrep: inout Bool
    ) throws -> [TokenUsageEvent] {
        var model = state.model
        var sessionID = state.sessionID
        var projectPath = state.projectPath
        var result: [TokenUsageEvent] = []
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let consume: (Data) -> Void = { row in
            guard let object = try? JSONSerialization.jsonObject(with: row) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { return }
            if type == "turn_context", let nextModel = payload["model"] as? String {
                model = nextModel
                return
            }
            if type == "session_meta" {
                sessionID = (payload["session_id"] as? String)
                    ?? (payload["id"] as? String)
                    ?? sessionID
                projectPath = (payload["cwd"] as? String) ?? projectPath
                return
            }
            guard type == "event_msg",
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usage = info["last_token_usage"] as? [String: Any],
                  let rawTimestamp = object["timestamp"] as? String,
                  let timestamp = FastTimestamp.parse(rawTimestamp) ?? fractional.date(from: rawTimestamp) ?? standard.date(from: rawTimestamp)
            else { return }
            let totalInput = integer(usage["input_tokens"])
            let cached = integer(usage["cached_input_tokens"])
            let output = integer(usage["output_tokens"])
            guard totalInput + output > 0 else { return }
            result.append(TokenUsageEvent(
                provider: .codex,
                timestamp: timestamp,
                model: model,
                sessionID: sessionID,
                projectPath: projectPath,
                input: max(0, totalInput - cached),
                output: output,
                cacheCreate: integer(usage["cache_write_input_tokens"]),
                cacheRead: cached
            ))
        }
        if RolloutReader.isCompressed(url) {
            let markers = ["session_meta", "turn_context", "token_count"].map { Data(("\"" + $0 + "\"").utf8) }
            try RolloutReader.forEachLine(at: url) { row in
                guard markers.contains(where: { row.range(of: $0) != nil }) else { return }
                consume(row)
            }
        } else if preferRipgrep, let filtered = try ripgrepRelevantLines(at: url, limit: limit) {
            usedRipgrep = true
            filtered.lines.forEach(consume)
            offset = filtered.offset
            // Logical source bytes scanned, including rg's input (not just its matching output).
            bytesRead = limit
        } else {
            try incrementalLines(at: url, offset: &offset, limit: limit,
                                 bytesRead: &bytesRead, body: consume)
        }
        state = ParseState(model: model, sessionID: sessionID, projectPath: projectPath)
        return result
    }

    /// Byte offsets keep rg results bounded to the original snapshot even if a writer appends.
    private static func ripgrepRelevantLines(at url: URL, limit: UInt64) throws -> (lines: [Data], offset: UInt64)? {
        let candidates = ["/Applications/ChatGPT.app/Contents/Resources/rg",
                          "/Applications/Codex.app/Contents/Resources/rg",
                          "/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var end = limit
        var completeEnd: UInt64 = 0
        while end > 0 {
            let start = end > 65536 ? end - 65536 : 0
            try handle.seek(toOffset: start)
            let tail = try handle.read(upToCount: Int(end - start)) ?? Data()
            guard tail.count == Int(end - start) else { return nil }
            if let newline = tail.lastIndex(of: 10) {
                completeEnd = start + UInt64(newline + 1)
                break
            }
            end = start
        }
        guard completeEnd > 0 else { return ([], 0) }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--no-config", "-a", "--no-messages", "--no-heading", "--no-filename",
                             "--color", "never", "--byte-offset", "--max-columns", "1048576",
                             #""type":"(session_meta|turn_context|token_count)""#, url.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else { return nil }
        let lines = data.split(separator: 10).compactMap { row -> Data? in
            guard let colon = row.firstIndex(of: 58),
                  let start = UInt64(String(decoding: row[..<colon], as: UTF8.self)) else { return nil }
            let line = row[(colon + 1)...]
            guard start < completeEnd, UInt64(line.count) < completeEnd - start,
                  line.count <= 1 << 20 else { return nil }
            return Data(line)
        }
        return (lines, completeEnd)
    }

    private static func incrementalLines(
        at url: URL, offset: inout UInt64, limit: UInt64,
        bytesRead: inout UInt64, body: (Data) -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var position = offset
        var pending = Data()
        var oversized = false
        let maximumLineBytes = 1 << 20
        // Match the existing plain-file filter exactly (including its JSON spacing).
        let markers = ["session_meta", "turn_context", "token_count"].map {
            Data(("\"type\":\"" + $0 + "\"").utf8)
        }
        while position < limit {
            let chunk = try handle.read(upToCount: Int(min(4 << 20, limit - position))) ?? Data()
            if chunk.isEmpty { break }
            bytesRead += UInt64(chunk.count)
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 0x0A)
                let end = newline ?? chunk.endIndex
                if !oversized {
                    if pending.count + end - start <= maximumLineBytes {
                        pending.append(contentsOf: chunk[start..<end])
                    } else {
                        oversized = true
                        pending.removeAll(keepingCapacity: true)
                    }
                }
                guard let newline else { break }
                if !oversized, markers.contains(where: { pending.range(of: $0) != nil }) {
                    body(pending)
                }
                pending.removeAll(keepingCapacity: true)
                oversized = false
                offset = position + UInt64(newline + 1)
                start = newline + 1
            }
            position += UInt64(chunk.count)
        }
        // An unterminated tail is intentionally reread from the last committed newline.
    }

    private static func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, RolloutReader.isRollout(url),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { return nil }
            return url
        }
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    struct DayBuckets {
        let boundaries: [Date]
        let calendar: Calendar

        init(now: Date, calendar: Calendar) {
            self.calendar = calendar
            let today = calendar.startOfDay(for: now)
            boundaries = (-179...1).map { calendar.date(byAdding: .day, value: $0, to: today)! }
        }

        func index(_ date: Date) -> Int {
            var low = 0
            var high = boundaries.count
            while low < high {
                let middle = (low + high) / 2
                if boundaries[middle] <= date { low = middle + 1 } else { high = middle }
            }
            return low - 1
        }

        func hour(_ date: Date) -> Int {
            let day = index(date)
            // Preserve future-event behavior and DST repeated/missing local hours.
            guard day >= 0, day < 180,
                  boundaries[day + 1].timeIntervalSince(boundaries[day]) == 86_400 else {
                return calendar.component(.hour, from: date)
            }
            return Int(date.timeIntervalSince(boundaries[day]) / 3_600)
        }
    }

    static func summarize(
        _ events: [TokenUsageEvent],
        projectNames: [String: String],
        accountContext: UsageAccountContext,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeActivity: Bool = true
    ) -> CostSnapshot {
        let buckets = DayBuckets(now: now, calendar: calendar)
        let knownAccountIDs = Set(accountContext.accounts.map(\.id))
        let aggregate = summarizeScope(
            events,
            projectNames: projectNames,
            now: now,
            calendar: calendar,
            buckets: buckets,
            includeActivity: includeActivity,
            include: { _ in true }
        )
        let byAccount = Dictionary(uniqueKeysWithValues: accountContext.accounts.map { account in
            (account.id, summarizeScope(
                events,
                projectNames: projectNames,
                now: now,
                calendar: calendar,
                buckets: buckets,
                includeActivity: includeActivity,
                include: { event in
                    accountContext.accountID(for: event.sessionID, at: event.timestamp) == account.id
                }
            ))
        })
        let unknownAccount = summarizeScope(
            events,
            projectNames: projectNames,
            now: now,
            calendar: calendar,
            buckets: buckets,
            includeActivity: includeActivity,
            include: { event in
                guard let accountID = accountContext.accountID(
                    for: event.sessionID,
                    at: event.timestamp
                ) else { return true }
                return !knownAccountIDs.contains(accountID)
            }
        )
        return CostSnapshot(
            aggregate: aggregate,
            byAccount: byAccount,
            unknownAccount: unknownAccount,
            updatedAt: now
        )
    }

    private static func summarizeScope(
        _ events: [TokenUsageEvent],
        projectNames: [String: String],
        now: Date,
        calendar: Calendar,
        buckets: DayBuckets,
        includeActivity: Bool,
        include: (TokenUsageEvent) -> Bool
    ) -> CostScopeSnapshot {
        let todayStart = buckets.boundaries[179]
        let weekStart = buckets.boundaries[173]
        let monthStart = buckets.boundaries[150]
        let activityStart = buckets.boundaries[0]
        let earliestRelevantDate = includeActivity ? activityStart : monthStart
        var today = CostTotals(series: Array(repeating: 0, count: 24))
        var week = CostTotals(series: Array(repeating: 0, count: 7))
        var month = CostTotals(series: Array(repeating: 0, count: 30))
        var providerTotals = Dictionary(uniqueKeysWithValues: CostProvider.allCases.map {
            ($0, ProviderCostTotals(
                provider: $0,
                today: CostTotals(),
                week: CostTotals(),
                month: CostTotals()
            ))
        })
        var unknown = Set<String>()
        var estimatedAliases: [String: String] = [:]
        var costByDay: [Date: Double] = [:]
        let orderedEvents = events.sorted { $0.timestamp < $1.timestamp }
        // If the month begins with an internal task, the first normal model is
        // still a better fallback than pretending the internal route has its
        // own public price.
        var currentPrimaryModel = orderedEvents.first(where: {
            !ModelPricing.isInternalAutomaticModel($0.model) &&
            ModelPricing.resolvedRates(for: $0.model) != nil
        })?.model

        for event in orderedEvents where event.timestamp >= earliestRelevantDate {
            if !ModelPricing.isInternalAutomaticModel(event.model),
               ModelPricing.resolvedRates(for: event.model) != nil {
                currentPrimaryModel = event.model
            }
            let billingModel = ModelPricing.billingModel(
                for: event.model,
                currentPrimaryModel: currentPrimaryModel
            )
            guard include(event) else { continue }
            if billingModel != event.model {
                estimatedAliases[event.model] = billingModel
            }
            let cost = estimatedCost(event, billingModel: billingModel)
            if cost == nil { unknown.insert(event.model) }
            if includeActivity {
                let day = buckets.index(event.timestamp)
                if (0..<180).contains(day) {
                    costByDay[buckets.boundaries[day], default: 0] += cost ?? 0
                }
            }

            if event.timestamp >= monthStart {
                add(event, cost: cost ?? 0, to: &month)
                let day = buckets.index(event.timestamp) - 150
                if month.series.indices.contains(day) { month.series[day] += cost ?? 0 }
            }

            if event.timestamp >= weekStart {
                add(event, cost: cost ?? 0, to: &week)
                let day = buckets.index(event.timestamp) - 173
                if week.series.indices.contains(day) { week.series[day] += cost ?? 0 }
            }

            if var item = providerTotals[event.provider] {
                if event.timestamp >= monthStart { add(event, cost: cost ?? 0, to: &item.month) }
                if event.timestamp >= weekStart { add(event, cost: cost ?? 0, to: &item.week) }
                if event.timestamp >= todayStart { add(event, cost: cost ?? 0, to: &item.today) }
                providerTotals[event.provider] = item
            }
            if event.timestamp >= todayStart {
                add(event, cost: cost ?? 0, to: &today)
                let hour = buckets.hour(event.timestamp)
                if today.series.indices.contains(hour) { today.series[hour] += cost ?? 0 }
            }
        }
        return CostScopeSnapshot(
            today: today,
            week: week,
            month: month,
            providers: CostProvider.allCases.compactMap { providerTotals[$0] },
            unknownModels: unknown.sorted(),
            estimatedModelAliases: estimatedAliases,
            usage: summarizeUsage(
                events.filter(include),
                now: now,
                buckets: buckets,
                projectNames: projectNames,
                includeActivity: includeActivity
            ),
            costActivity: includeActivity
                ? dailyCostActivity(costByDay, buckets: buckets)
                : [],
            lifetimeTokens: includeActivity ? events.filter { include($0) && $0.timestamp <= now }.reduce(0) { total, event in
                [event.input, event.output, event.cacheCreate, event.cacheRead].reduce(total) { sum, count in
                    let next = sum.addingReportingOverflow(max(0, count))
                    return next.overflow ? Int.max : next.partialValue
                }
            } : nil
        )
    }

    private static func dailyCostActivity(
        _ dollarsByDay: [Date: Double], buckets: DayBuckets
    ) -> [DailyCostActivity] {
        buckets.boundaries.prefix(180).map { date in
            DailyCostActivity(date: date, dollars: dollarsByDay[date, default: 0])
        }
    }

    private static func summarizeUsage(
        _ events: [TokenUsageEvent],
        now: Date,
        buckets: DayBuckets,
        projectNames: [String: String],
        includeActivity: Bool
    ) -> UsageSnapshot {
        let todayStart = buckets.boundaries[179]
        let weekStart = buckets.boundaries[173]
        let monthStart = buckets.boundaries[150]
        let quarterStart = buckets.boundaries[90]
        return UsageSnapshot(
            day: usageTotals(events, from: todayStart, seriesCount: 24, projectNames: projectNames) { event in
                buckets.hour(event.timestamp)
            },
            week: usageTotals(events, from: weekStart, seriesCount: 7, projectNames: projectNames) { event in
                max(0, min(6, buckets.index(event.timestamp) - 173))
            },
            month: usageTotals(events, from: monthStart, seriesCount: 30, projectNames: projectNames) { event in
                max(0, min(29, buckets.index(event.timestamp) - 150))
            },
            quarter: usageTotals(events, from: quarterStart, seriesCount: 90, projectNames: projectNames) { event in
                max(0, min(89, buckets.index(event.timestamp) - 90))
            },
            activity: includeActivity
                ? dailyTokenActivity(events, buckets: buckets)
                : [],
            activityIsReady: includeActivity
        )
    }

    private static func dailyTokenActivity(
        _ events: [TokenUsageEvent], buckets: DayBuckets
    ) -> [DailyTokenActivity] {
        var totals = Array(repeating: 0, count: 180)
        for event in events {
            let day = buckets.index(event.timestamp)
            guard totals.indices.contains(day) else { continue }
            totals[day] += event.input + event.output + event.cacheCreate + event.cacheRead
        }
        return totals.indices.map {
            DailyTokenActivity(date: buckets.boundaries[$0], tokens: totals[$0])
        }
    }

    private static func usageTotals(
        _ events: [TokenUsageEvent],
        from start: Date,
        seriesCount: Int,
        projectNames: [String: String],
        bucket: (TokenUsageEvent) -> Int
    ) -> UsageTotals {
        let filtered = events.filter { $0.timestamp >= start }
        var result = UsageTotals(series: Array(repeating: 0, count: seriesCount))
        var sessions = Set<String>()
        var projectSessions: [String: Set<String>] = [:]
        var projectTokens: [String: Int] = [:]
        for event in filtered {
            let cache = event.cacheCreate + event.cacheRead
            let total = event.input + event.output + cache
            result.tokens += total
            result.inputTokens += event.input
            result.outputTokens += event.output
            result.cacheTokens += cache
            sessions.insert(event.sessionID)
            projectSessions[event.projectPath, default: []].insert(event.sessionID)
            projectTokens[event.projectPath, default: 0] += total
            let index = bucket(event)
            if result.series.indices.contains(index) { result.series[index] += Double(total) }
        }
        result.sessionCount = sessions.count
        result.projectCount = projectTokens.count
        result.projects = projectTokens.map { path, tokens in
            let url = URL(fileURLWithPath: path)
            let fallbackName = path == "未归类" ? path : (url.lastPathComponent.isEmpty ? path : url.lastPathComponent)
            return ProjectUsage(
                name: projectNames[path] ?? fallbackName,
                path: path,
                tokens: tokens,
                sessionCount: projectSessions[path]?.count ?? 0
            )
        }.sorted {
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
        return result
    }

    static func add(_ event: TokenUsageEvent, cost: Double, to total: inout CostTotals) {
        total.dollars += cost
        total.inputTokens += event.input
        total.outputTokens += event.output
        total.cacheTokens += event.cacheCreate + event.cacheRead
        total.tokens += event.input + event.output + event.cacheCreate + event.cacheRead
    }

    static func estimatedCost(_ event: TokenUsageEvent, billingModel: String) -> Double? {
        guard let rate = ModelPricing.resolvedRates(for: billingModel) else { return nil }
        let multipliers = ModelPricing.multipliers(
            for: billingModel,
            totalInputTokens: event.input + event.cacheRead
        )
        return (Double(event.input) * rate.inputPerMillion * multipliers.inputAndCache +
                Double(event.output) * rate.outputPerMillion * multipliers.output +
                Double(event.cacheCreate) * rate.cacheCreationPerMillion * multipliers.inputAndCache +
                Double(event.cacheRead) * rate.cacheReadPerMillion * multipliers.inputAndCache) / 1_000_000
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

}

extension CostService {
    struct FileEvents {
        let path: String
        let entry: ParsedFileCacheEntry
    }

    private struct DiskEnvelope: Codable {
        let version: Int
        let entries: [String: ParsedFileCacheEntry]
    }

    private static let diskQueue = DispatchQueue(label: "CodexNotchMonitor.CostDiskCache", qos: .utility)
    private static var diskURL: URL?
    private static var diskLoaded = false
    private static var diskDirty = false
    private static var diskScheduled = false
    private static var lastDiskWrite = Date.distantPast
    private static let terminationObserver = NotificationCenter.default.addObserver(
        forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: nil
    ) { _ in flushDiskCache() }

    /// Explicit cache destination and process restart simulation for isolated fixtures.
    static func resetCacheForTesting(diskURL url: URL?) {
        diskQueue.sync {
            parsedFileCacheLock.lock()
            defer { parsedFileCacheLock.unlock() }
            parsedFileCache = [:]
            diskURL = url
            diskLoaded = false
            diskDirty = false
            lastDiskWrite = .distantPast
        }
    }

    private static func loadDiskCache(homeDirectory: URL) {
        parsedFileCacheLock.lock()
        defer { parsedFileCacheLock.unlock() }
        guard !diskLoaded else { return }
        // Synthetic homes never read or write the user's actual cache.
        if diskURL == nil, homeDirectory == FileManager.default.homeDirectoryForCurrentUser,
           ProcessInfo.processInfo.environment["COST_SYNTHETIC_ONLY"] != "1" {
            diskURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("CodexNotchMonitor/cost-parse-cache-v1/entries.plist")
        }
        diskLoaded = true
        _ = terminationObserver
        guard let url = diskURL, let data = try? Data(contentsOf: url),
              let envelope = try? PropertyListDecoder().decode(DiskEnvelope.self, from: data),
              envelope.version == 1,
              envelope.entries.allSatisfy({ path, entry in
                  path.hasPrefix("/") && entry.fileSize >= 0 && entry.offset <= UInt64(entry.fileSize)
                    && entry.modificationDate.timeIntervalSince1970.isFinite
                    && entry.events.allSatisfy { $0.timestamp.timeIntervalSince1970.isFinite }
              }) else { return }
        parsedFileCache = envelope.entries.mapValues { entry in
            var restored = entry
            restored.bytesRead = 0
            return restored
        }
    }

    private static func scheduleDiskWrite() {
        parsedFileCacheLock.lock()
        guard diskURL != nil, diskDirty, !diskScheduled else {
            parsedFileCacheLock.unlock()
            return
        }
        diskScheduled = true
        let delay = max(0, 60 - Date().timeIntervalSince(lastDiskWrite))
        parsedFileCacheLock.unlock()
        diskQueue.asyncAfter(deadline: .now() + delay) { writeDiskCache() }
    }

    static func flushDiskCache() {
        diskQueue.sync { writeDiskCache() }
    }

    private static func writeDiskCache() {
        parsedFileCacheLock.lock()
        diskScheduled = false
        guard diskDirty, let url = diskURL else { parsedFileCacheLock.unlock(); return }
        let entries = parsedFileCache
        lastDiskWrite = Date()
        diskDirty = false
        parsedFileCacheLock.unlock()
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(DiskEnvelope(version: 1, entries: entries))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
        } catch {
            parsedFileCacheLock.lock()
            diskDirty = true
            parsedFileCacheLock.unlock()
        }
    }
}


extension CostService {
    /// One state per window/account. Dollar additions retain the full summary's time order.
    private final class ScopeAccumulator {
        var today = CostTotals(series: Array(repeating: 0, count: 24))
        var week = CostTotals(series: Array(repeating: 0, count: 7))
        var month = CostTotals(series: Array(repeating: 0, count: 30))
        var providerTotals = Dictionary(uniqueKeysWithValues: CostProvider.allCases.map {
            ($0, ProviderCostTotals(provider: $0, today: CostTotals(), week: CostTotals(), month: CostTotals()))
        })
        var unknown = Set<String>()
        var estimatedAliases: [String: String] = [:]
        var costByDay: [Date: Double] = [:]
        var currentPrimaryModel: String?
        let usage = [UsageAccumulator(24), UsageAccumulator(7), UsageAccumulator(30), UsageAccumulator(90)]
        var activity = Array(repeating: 0, count: 180)
        var lifetime = 0

        func consume(_ orderedEvents: [TokenUsageEvent], buckets: DayBuckets,
                     now: Date, includeActivity: Bool, include: (TokenUsageEvent) -> Bool) {
            let todayStart = buckets.boundaries[179]
            let weekStart = buckets.boundaries[173]
            let monthStart = buckets.boundaries[150]
            let earliestRelevantDate = buckets.boundaries[includeActivity ? 0 : 150]
            for event in orderedEvents where event.timestamp >= earliestRelevantDate {
                if !ModelPricing.isInternalAutomaticModel(event.model),
                   ModelPricing.resolvedRates(for: event.model) != nil {
                    currentPrimaryModel = event.model
                }
                let billingModel = ModelPricing.billingModel(
                    for: event.model,
                    currentPrimaryModel: currentPrimaryModel
                )
                guard include(event) else { continue }
                if billingModel != event.model {
                    estimatedAliases[event.model] = billingModel
                }
                let cost = CostService.estimatedCost(event, billingModel: billingModel)
                if cost == nil { unknown.insert(event.model) }
                if includeActivity {
                    let day = buckets.index(event.timestamp)
                    if (0..<180).contains(day) {
                        costByDay[buckets.boundaries[day], default: 0] += cost ?? 0
                    }
                }

                if event.timestamp >= monthStart {
                    CostService.add(event, cost: cost ?? 0, to: &month)
                    let day = buckets.index(event.timestamp) - 150
                    if month.series.indices.contains(day) { month.series[day] += cost ?? 0 }
                }

                if event.timestamp >= weekStart {
                    CostService.add(event, cost: cost ?? 0, to: &week)
                    let day = buckets.index(event.timestamp) - 173
                    if week.series.indices.contains(day) { week.series[day] += cost ?? 0 }
                }

                if var item = providerTotals[event.provider] {
                    if event.timestamp >= monthStart { CostService.add(event, cost: cost ?? 0, to: &item.month) }
                    if event.timestamp >= weekStart { CostService.add(event, cost: cost ?? 0, to: &item.week) }
                    if event.timestamp >= todayStart { CostService.add(event, cost: cost ?? 0, to: &item.today) }
                    providerTotals[event.provider] = item
                }
                if event.timestamp >= todayStart {
                    CostService.add(event, cost: cost ?? 0, to: &today)
                    let hour = buckets.hour(event.timestamp)
                    if today.series.indices.contains(hour) { today.series[hour] += cost ?? 0 }
                }
            }

            for event in orderedEvents where include(event) {
                let day = buckets.index(event.timestamp)
                if event.timestamp >= todayStart { usage[0].consume(event, bucket: buckets.hour(event.timestamp)) }
                if event.timestamp >= weekStart { usage[1].consume(event, bucket: max(0, min(6, day - 173))) }
                if event.timestamp >= monthStart { usage[2].consume(event, bucket: max(0, min(29, day - 150))) }
                if event.timestamp >= buckets.boundaries[90] { usage[3].consume(event, bucket: max(0, min(89, day - 90))) }
                if includeActivity {
                    if activity.indices.contains(day) {
                        activity[day] += event.input + event.output + event.cacheCreate + event.cacheRead
                    }
                    if event.timestamp <= now {
                        for count in [event.input, event.output, event.cacheCreate, event.cacheRead] {
                            let next = lifetime.addingReportingOverflow(max(0, count))
                            lifetime = next.overflow ? Int.max : next.partialValue
                        }
                    }
                }
            }
        }

        func snapshot(buckets: DayBuckets, names: [String: String], activity ready: Bool) -> CostScopeSnapshot {
            CostScopeSnapshot(today: today, week: week, month: month,
                providers: CostProvider.allCases.compactMap { providerTotals[$0] },
                unknownModels: unknown.sorted(), estimatedModelAliases: estimatedAliases,
                usage: UsageSnapshot(day: usage[0].snapshot(names), week: usage[1].snapshot(names),
                    month: usage[2].snapshot(names), quarter: usage[3].snapshot(names),
                    activity: ready ? activity.indices.map { DailyTokenActivity(date: buckets.boundaries[$0], tokens: activity[$0]) } : [],
                    activityIsReady: ready),
                costActivity: ready ? CostService.dailyCostActivity(costByDay, buckets: buckets) : [],
                lifetimeTokens: ready ? lifetime : nil)
        }
    }

    private final class UsageAccumulator {
        var totals: UsageTotals
        var sessions = Set<String>()
        var projectSessions: [String: Set<String>] = [:]
        var projectTokens: [String: Int] = [:]

        init(_ count: Int) { totals = UsageTotals(series: Array(repeating: 0, count: count)) }

        func consume(_ event: TokenUsageEvent, bucket: Int) {
            let cache = event.cacheCreate + event.cacheRead
            let total = event.input + event.output + cache
            totals.tokens += total
            totals.inputTokens += event.input
            totals.outputTokens += event.output
            totals.cacheTokens += cache
            if totals.series.indices.contains(bucket) { totals.series[bucket] += Double(total) }
            sessions.insert(event.sessionID)
            projectSessions[event.projectPath, default: []].insert(event.sessionID)
            projectTokens[event.projectPath, default: 0] += total
        }

        func snapshot(_ names: [String: String]) -> UsageTotals {
            var result = totals
            result.sessionCount = sessions.count
            result.projectCount = projectTokens.count
            result.projects = projectTokens.map { path, tokens in
                let component = URL(fileURLWithPath: path).lastPathComponent
                return ProjectUsage(name: names[path] ?? (path == "未归类" || component.isEmpty ? path : component),
                    path: path, tokens: tokens, sessionCount: projectSessions[path]?.count ?? 0)
            }.sorted {
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            }
            return result
        }
    }
}

extension CostService {
    /// Owned by the service queue, independently for the recent and full-history scans.
    final class AggregationCache {
        private struct Count {
            let generation: UUID
            let events: Int
        }
        private var counts: [String: Count] = [:]
        private var paths: [String] = []
        private var overrides: [String: String] = [:]
        private var catalog = CodexProjectCatalog.State.empty
        private var context: UsageAccountContext?
        private var calendar: Calendar?
        private var day: Date?
        private var includeActivity = false
        private var pricingDates: [Date?] = []
        private var aliases: [String: String] = [:]
        private var seen = Set<TokenEventIdentity>()
        private var maximumDate = Date.distantPast
        private var lastNow = Date.distantPast
        private var hadDuplicates = false
        private var exactIntegerBudget: Double = 0
        private var scopes: [String: ScopeAccumulator] = [:]
        private(set) var lastUpdateWasIncremental = false
        private(set) var lastFallbackReason = "initial"
        private(set) var processedEvents = 0
        private(set) var lastMaterializationSeconds: TimeInterval = 0

        func update(files: [FileEvents], overrides newOverrides: [String: String] = [:],
                    catalog newCatalog: CodexProjectCatalog.State = .empty,
                    context newContext: UsageAccountContext,
                    now: Date = Date(), calendar newCalendar: Calendar = .current,
                    includeActivity activity: Bool = true, pricingRevision: Date? = nil) -> CostSnapshot {
            let dates = [PricingCatalog.lastFetched, OfficialPricingCatalog.syncStatus.date, pricingRevision]
            let newPaths = files.map(\.path)
            let newPathSet = Set(newPaths)
            var reason: String?
            if context == nil { reason = "initial" }
            else if newOverrides != overrides || newCatalog != catalog { reason = "project mapping" }
            else if newContext != context { reason = "account context" }
            else if calendar != newCalendar || day != newCalendar.startOfDay(for: now) || activity != includeActivity { reason = "calendar/window" }
            else if dates != pricingDates { reason = "pricing" }
            else if paths.contains(where: { !newPathSet.contains($0) }) { reason = "deleted file" }
            else if newPaths.filter({ counts[$0] != nil }) != paths { reason = "file order" }
            else if maximumDate > lastNow && now != lastNow { reason = "future event clock" }
            var delta: [TokenUsageEvent] = []
            if reason == nil {
                for file in files {
                    let previous = counts[file.path]
                    if let previous, previous.generation != file.entry.generation || previous.events > file.entry.events.count {
                        reason = "rebuilt file"
                        break
                    }
                    delta.append(contentsOf: file.entry.events.dropFirst(previous?.events ?? 0))
                }
            }
            if reason == nil, !delta.isEmpty {
                if hadDuplicates { reason = "existing duplicates" }
                var addedIdentities = Set<TokenEventIdentity>()
                for event in delta {
                    let identity = Self.identity(event)
                    if seen.contains(identity) || !addedIdentities.insert(identity).inserted { reason = "duplicate event"; break }
                    if event.timestamp <= maximumDate { reason = "out-of-order event"; break }
                }
                let nextAliases = Self.pathAliases(delta, overrides: newOverrides, catalog: newCatalog)
                if nextAliases.contains(where: { aliases[$0.key] != $0.value }) { reason = "retroactive path alias" }
                if scopes[UsageAccountScope.all]?.currentPrimaryModel == nil,
                   delta.contains(where: Self.isPrimary) { reason = "initial billing model" }
            }
            // Integer series may be summed in a different order from the file traversal.
            // Beyond the exact Double integer range (or with negatives), use the original reducer.
            let addedBudget = Self.integerBudget(delta)
            if reason == nil && exactIntegerBudget + addedBudget >= 9_007_199_254_740_992 {
                reason = "numeric range"
            }
            let buckets = DayBuckets(now: now, calendar: newCalendar)
            let known = Set(newContext.accounts.map(\.id))
            if reason != nil {
                let raw = files.flatMap { $0.entry.events }
                let unique = CostService.deduplicated(raw)
                hadDuplicates = unique.count != raw.count
                seen = Set(unique.map(Self.identity))
                aliases = Self.pathAliases(unique, overrides: newOverrides, catalog: newCatalog)
                delta = CostService.remapEvents(unique, sessionPathOverrides: newOverrides, catalog: newCatalog)
                exactIntegerBudget = Self.integerBudget(delta)
                scopes = [:]
                for key in [UsageAccountScope.all, UsageAccountScope.unknown] + newContext.accounts.map(\.id) {
                    scopes[key] = ScopeAccumulator()
                }
                maximumDate = delta.map(\.timestamp).max() ?? .distantPast
            } else {
                exactIntegerBudget += addedBudget
                for event in delta { seen.insert(Self.identity(event)) }
                delta = delta.map { event in
                    if let assignment = newCatalog.assignmentsByThread[event.sessionID] { return event.withProjectPath(assignment.path) }
                    if let path = newOverrides[event.sessionID], !path.isEmpty { return event.withProjectPath(path) }
                    return aliases[event.projectPath].map { event.withProjectPath($0) } ?? event
                }
                maximumDate = max(maximumDate, delta.map(\.timestamp).max() ?? .distantPast)
            }
            counts = Dictionary(uniqueKeysWithValues: files.map { ($0.path, Count(generation: $0.entry.generation, events: $0.entry.events.count)) })
            paths = newPaths
            overrides = newOverrides
            catalog = newCatalog
            context = newContext
            calendar = newCalendar
            day = newCalendar.startOfDay(for: now)
            includeActivity = activity
            pricingDates = dates
            lastNow = now
            lastUpdateWasIncremental = reason == nil
            lastFallbackReason = reason ?? "none"
            processedEvents = delta.count
            if exactIntegerBudget >= 9_007_199_254_740_992 {
                // This path is intentionally rare and never seeds incremental state.
                return CostService.summarize(CostService.remapEvents(CostService.deduplicated(files.flatMap { $0.entry.events }),
                    sessionPathOverrides: newOverrides, catalog: newCatalog), projectNames: newCatalog.namesByPath,
                    accountContext: newContext, now: now, calendar: newCalendar, includeActivity: activity)
            }
            let ordered = delta.sorted { $0.timestamp < $1.timestamp }
            for (key, scope) in scopes {
                if reason != nil { scope.currentPrimaryModel = ordered.first(where: Self.isPrimary)?.model }
                scope.consume(ordered, buckets: buckets, now: now, includeActivity: activity) { event in
                    if key == UsageAccountScope.all { return true }
                    let account = newContext.accountID(for: event.sessionID, at: event.timestamp)
                    return key == UsageAccountScope.unknown ? account.map { !known.contains($0) } ?? true : account == key
                }
            }
            let materializationStart = Date()
            func snapshot(_ key: String) -> CostScopeSnapshot {
                scopes[key]!.snapshot(buckets: buckets, names: newCatalog.namesByPath, activity: activity)
            }
            let result = CostSnapshot(aggregate: snapshot(UsageAccountScope.all),
                byAccount: Dictionary(uniqueKeysWithValues: newContext.accounts.map { ($0.id, snapshot($0.id)) }),
                unknownAccount: snapshot(UsageAccountScope.unknown), updatedAt: now)
            lastMaterializationSeconds = Date().timeIntervalSince(materializationStart)
            return result
        }

        private static func isPrimary(_ event: TokenUsageEvent) -> Bool {
            !ModelPricing.isInternalAutomaticModel(event.model) && ModelPricing.resolvedRates(for: event.model) != nil
        }

        private static func integerBudget(_ events: [TokenUsageEvent]) -> Double {
            var sum = 0.0
            for event in events {
                for value in [event.input, event.output, event.cacheCreate, event.cacheRead] {
                    if value < 0 { return .infinity }
                    sum += Double(value)
                }
            }
            return sum
        }

        private static func identity(_ event: TokenUsageEvent) -> TokenEventIdentity {
            TokenEventIdentity(sessionID: event.sessionID, timestamp: event.timestamp, model: event.model,
                input: event.input, output: event.output, cacheCreate: event.cacheCreate, cacheRead: event.cacheRead)
        }

        private static func pathAliases(_ events: [TokenUsageEvent], overrides: [String: String],
                                        catalog: CodexProjectCatalog.State) -> [String: String] {
            var result: [String: String] = [:]
            for event in events {
                guard catalog.assignmentsByThread[event.sessionID] == nil,
                      let path = overrides[event.sessionID], !path.isEmpty else { continue }
                let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
                if normalized != event.projectPath { result[event.projectPath] = normalized }
            }
            return result
        }
    }
}
