import Foundation
import CryptoKit
import SQLite3

enum SessionEndReason: Equatable {
    case completed
    case cancelled
    case failed
    case ended

    var phase: TaskPhase {
        switch self {
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled, .ended: return .ended
        }
    }

    var title: String {
        switch self {
        case .completed: return "本轮工作已完成"
        case .cancelled: return "本轮工作已取消"
        case .failed: return "本轮工作失败"
        case .ended: return "会话已结束"
        }
    }
}

struct SessionActivityEvidence: Equatable {
    let lifecycleState: Bool?
    let hasRunningTool: Bool
    let fileModifiedAt: Date
    let endReason: SessionEndReason?
    let endedAt: Date?
}

struct LocalSessionSnapshot: Equatable {
    let sessionID: String
    let turnID: String?
    let cwd: String
    let model: String?
    var isActive: Bool
    let updatedAt: Date
    let activities: [SessionActivityItem]
    var turnTokenUsage: TurnTokenUsage? = nil
    var evidence: SessionActivityEvidence? = nil
    var reasoningEffort: String? = nil
    var startedAt: Date? = nil
    var sessionTotalTokens: Int? = nil
    var latestAssistantSummary: String? = nil
    var nativePhase: TaskPhase? = nil
    var sessionKind: CodexActivitySessionKind = .unknown
    var nativeWaitReason: CodexActivityWaitReason? = nil
    var nativeReplyRequestIDs: Set<String> = []
    var nativeSuppressCompletion = false
    var fastMode: Bool? = nil

    func evaluated(at now: Date) -> Self {
        guard let evidence else { return self }
        var result = self
        result.isActive = SessionActivityFreshnessPolicy.isActive(
            lifecycleState: evidence.lifecycleState,
            hasRunningTool: evidence.hasRunningTool,
            updatedAt: updatedAt,
            fileModifiedAt: evidence.fileModifiedAt,
            now: now
        )
        return result
    }
}

enum SessionActivityFreshnessPolicy {
    static let quietTurnGrace: TimeInterval = 10 * 60
    static let runningToolGrace: TimeInterval = 2 * 60 * 60
    static let discoveryGrace: TimeInterval = 15

    static func isActive(
        lifecycleState: Bool?,
        hasRunningTool: Bool,
        updatedAt: Date,
        fileModifiedAt: Date,
        now: Date = Date()
    ) -> Bool {
        switch lifecycleState {
        case false:
            return false
        case true:
            let grace = hasRunningTool ? runningToolGrace : quietTurnGrace
            return now.timeIntervalSince(updatedAt) < grace
        case nil:
            return now.timeIntervalSince(fileModifiedAt) < discoveryGrace
        }
    }
}

/// Reads only structural fields from Codex's local JSONL transcript. Prompt,
/// private reasoning and raw tool payloads are never retained. Only a bounded,
/// sanitized public assistant summary is retained for the task presentation.
final class SessionActivityService {
    private let queue = DispatchQueue(label: "CodexNotchMonitor.SessionActivity", qos: .utility)
    private let decoder = JSONDecoder()
    private let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let dateFormatter = ISO8601DateFormatter()
    var onChange: (() -> Void)?
    private var watchedFiles: [URL: DispatchSourceFileSystemObject] = [:]
    private var pendingChange: DispatchWorkItem?
    /// Recent activity and completion markers live at the transcript tail.
    /// Keeping this bounded prevents one growing Codex thread from producing a
    /// large JSON parse spike on every refresh. Desktop IPC and file changes
    /// provide native updates; local logs supply incremental detail.
    private let maximumTailBytes: UInt64 = 8 * 1_024 * 1_024
    private let maximumCandidateFiles = 24
    private let activeRecencyInterval: TimeInterval = 24 * 60 * 60
    private let discoveryInterval: TimeInterval = 5
    private var cache: [URL: CachedSnapshot] = [:]
    private var discoveredURLs: [URL] = []
    private var lastDiscoveryAt = Date.distantPast

    // Incremental cursor and complete-line consumption adapted from QuotaView's
    // CodexLocalRolloutActivityClient (d16307f, MIT). Keep the existing public
    // summary/token decoder; never retain raw transcript history in the cursor.
    private struct RolloutCursor {
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        var modified = Date.distantPast
        var prefixCount = 0
        var prefixDigest = Data()
        var pending = Data()
        var discarding = false
        var sessionID: String = ""
        var turnID: String? = nil
        var cwd: String = ""
        var model: String? = nil
        var isActive: Bool? = nil
        var endReason: SessionEndReason? = nil
        var endedAt: Date? = nil
        var reasoningEffort: String? = nil
        var startedAt: Date? = nil
        var sessionTotalTokens: Int? = nil
        var latestAssistantSummary: String? = nil
        var latestTimestamp: Date = .distantPast
        var activities: [SessionActivityItem] = []
        var activityIndices: [String: Int] = [:]
        var tokenState: TurnTokenState = TurnTokenState()
        var sessionKind: CodexActivitySessionKind = .unknown
        var fastMode: Bool? = nil
        var threadFastMode: Bool? = nil
    }
    private var rolloutCursors: [URL: RolloutCursor] = [:]

    private struct CachedSnapshot {
        let modificationDate: Date
        let fileSize: UInt64
        let snapshot: LocalSessionSnapshot?
    }

    func fetch(preferredSessionIDs: [String] = [], completion: @escaping ([LocalSessionSnapshot], [String: String], CodexProjectCatalog.State) -> Void) {
        queue.async { [self] in
            var seen = Set<URL>()
            let urls = (Self.preferredSessionFiles(sessionIDs: preferredSessionIDs) + recentSessionFiles())
                .filter { seen.insert($0).inserted }
            updateWatchedFiles(urls)
            let now = Date()
            let snapshots = urls.compactMap { cachedSnapshot(for: $0, now: now) }.filter {
                now.timeIntervalSince($0.updatedAt) < activeRecencyInterval
            }
            let threadNames = CodexThreadNameCatalog.loadNames()
            let catalog = CodexProjectCatalog.loadState()
            let retained = Set(urls)
            cache = cache.filter { retained.contains($0.key) }
            rolloutCursors = rolloutCursors.filter { retained.contains($0.key) }
            DispatchQueue.main.async { completion(snapshots, threadNames, catalog) }
        }
    }

    // QuotaView CodexLocalRolloutDiscovery prioritizes exact SQLite identities
    // before directory discovery. Only existing, confined rollout files qualify.
    static func preferredSessionFiles(sessionIDs: [String], codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) -> [URL] {
        guard !sessionIDs.isEmpty else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(codexHome.appendingPathComponent("state_5.sqlite").path, &database,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }; return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 20)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT rollout_path FROM threads WHERE id = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        let root = codexHome.appendingPathComponent("sessions").resolvingSymlinksInPath().path + "/"
        var result: [URL] = []
        for id in Set(sessionIDs.prefix(8)) where !id.isEmpty && id.utf8.count <= 128 {
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard sqlite3_step(statement) == SQLITE_ROW, let path = sqlite3_column_text(statement, 0) else { continue }
            let url = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
            guard url.path.hasPrefix(root), url.pathExtension == "jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let header = try? handle.read(upToCount: 65536)
            try? handle.close()
            guard let header, let line = header.split(separator: 0x0A).first,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let metadata = object["payload"] as? [String: Any], metadata["id"] as? String == id else { continue }
            result.append(url)
        }
        return result
    }

    private func recentSessionFiles() -> [URL] {
        let now = Date()
        if now.timeIntervalSince(lastDiscoveryAt) < discoveryInterval {
            return discoveredURLs
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return discoveredURLs }
        let candidates = enumerator.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) < activeRecencyInterval
            else { return nil }
            return (url, modified)
        }
        discoveredURLs = candidates.sorted { $0.1 > $1.1 }
            .prefix(maximumCandidateFiles)
            .map(\.0)
        lastDiscoveryAt = now
        return discoveredURLs
    }

    func cachedSnapshot(for url: URL, now: Date = Date()) -> LocalSessionSnapshot? {
        // URL resource values can cache metadata across refreshes, including
        // after deletion. A fresh stat must gate reuse of parsed evidence.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            cache.removeValue(forKey: url)
            rolloutCursors.removeValue(forKey: url)
            return nil
        }
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if let cached = cache[url], cached.modificationDate == modified, cached.fileSize == size {
            return cached.snapshot?.evaluated(at: now)
        }
        var snapshot = readSnapshot(from: url)
        if let old = cache[url]?.snapshot, var current = snapshot, old.sessionID == current.sessionID {
            current.sessionTotalTokens = [old.sessionTotalTokens, current.sessionTotalTokens].compactMap { $0 }.max()
            snapshot = current
        }
        cache[url] = CachedSnapshot(
            modificationDate: modified,
            fileSize: size,
            snapshot: snapshot
        )
        return snapshot?.evaluated(at: now)
    }

    private func modificationDate(of url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    func readSnapshot(from url: URL) -> LocalSessionSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let end = (try? handle.seekToEnd()) ?? 0
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        var cursor = rolloutCursors[url] ?? RolloutCursor()
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        try? handle.seek(toOffset: 0)
        let prefix = (try? handle.read(upToCount: cursor.prefixCount)) ?? Data()
        let rewritten = cursor.prefixCount > 0 && Data(SHA256.hash(data: prefix)) != cursor.prefixDigest
        if cursor.inode != inode || end < cursor.offset || end - cursor.offset > maximumTailBytes
            || rewritten || (end == cursor.offset && cursor.modified != modified) {
            cursor = RolloutCursor()
        }
        if cursor.offset == 0 {
            cursor.sessionID = Self.sessionIDFromFilename(url)
            cursor.latestTimestamp = modificationDate(of: url)
            // Recover only structural session metadata when the bounded tail
            // no longer contains the header.
            try? handle.seek(toOffset: 0)
            if let header = try? handle.read(upToCount: 65536), let line = header.split(separator: 0x0A).first,
               let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               object["type"] as? String == "session_meta", let payload = object["payload"] as? [String: Any] {
                cursor.sessionID = payload["id"] as? String ?? cursor.sessionID
                cursor.cwd = payload["cwd"] as? String ?? ""
                cursor.sessionKind = CodexActivitySessionKind.classify(metadata: payload)
            }
            cursor.offset = end > maximumTailBytes ? end - maximumTailBytes : 0
            cursor.discarding = cursor.offset > 0
        }
        cursor.inode = inode
        cursor.modified = modified
        if cursor.prefixCount == 0 {
            cursor.prefixCount = min(256, Int(end))
            try? handle.seek(toOffset: 0)
            cursor.prefixDigest = Data(SHA256.hash(data: (try? handle.read(upToCount: cursor.prefixCount)) ?? Data()))
        }
        try? handle.seek(toOffset: cursor.offset)
        let incoming: Data
        do { incoming = try handle.read(upToCount: Int(maximumTailBytes)) ?? Data() }
        catch { return nil }
        cursor.offset += UInt64(incoming.count)
        cursor.pending.append(incoming)
        var lines: [Data] = []
        consumeCompleteLines(from: &cursor.pending, discarding: &cursor.discarding) { lines.append($0) }
        // Some compatible writers omit the final newline. Accept only a whole
        // JSON object; incomplete writes remain buffered for the next read.
        if !cursor.discarding, !cursor.pending.isEmpty,
           (try? JSONSerialization.jsonObject(with: cursor.pending)) is [String: Any] {
            lines.append(cursor.pending); cursor.pending.removeAll(keepingCapacity: true)
        }
        var sessionID = cursor.sessionID
        var turnID = cursor.turnID
        var cwd = cursor.cwd
        var model = cursor.model
        var isActive = cursor.isActive
        var endReason = cursor.endReason
        var endedAt = cursor.endedAt
        var reasoningEffort = cursor.reasoningEffort
        var startedAt = cursor.startedAt
        var sessionTotalTokens = cursor.sessionTotalTokens
        var latestAssistantSummary = cursor.latestAssistantSummary
        var latestTimestamp = cursor.latestTimestamp
        var activities = cursor.activities
        var activityIndices = cursor.activityIndices
        var tokenState = cursor.tokenState
        var sessionKind = cursor.sessionKind

        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { continue }

            var eventTimestamp = latestTimestamp
            if let timestamp = object["timestamp"] as? String,
               let parsed = parseDate(timestamp) {
                eventTimestamp = parsed
            }

            if let value = Self.cumulativeTokens(type: type, payload: payload, sessionID: sessionID) {
                sessionTotalTokens = max(sessionTotalTokens ?? 0, value)
            }
            let previousTurn = tokenState.turnID
            let incomingTurn = payload["turn_id"] as? String
            let eventType = payload["type"] as? String
            // Forked/imported history can contain another thread's checkpoint.
            if type == "event_msg", eventType == "thread_settings_applied",
               payload["thread_id"] as? String != sessionID { continue }
            let beginsTurn = type == "turn_context" || (type == "event_msg" && eventType == "task_started")
            if tokenState.pendingStart, type == "event_msg",
               ["task_complete", "turn_aborted"].contains(eventType ?? "") { continue }
            if !beginsTurn, let incomingTurn, let turnID, incomingTurn != turnID { continue }
            let followsLegacyStart = tokenState.pendingStart
            tokenState.consume(type: type, payload: payload)
            if beginsTurn, let incomingTurn, tokenState.turnID != incomingTurn { continue }
            if tokenState.turnID != previousTurn {
                cursor.fastMode = cursor.threadFastMode
                turnID = tokenState.turnID
                isActive = followsLegacyStart ? true : nil
                endReason = nil
                endedAt = nil
                if !followsLegacyStart { startedAt = nil }
                latestAssistantSummary = nil
                activities.removeAll()
                activityIndices.removeAll()
            }
            latestTimestamp = max(latestTimestamp, eventTimestamp)

            switch type {
            case "session_meta":
                sessionKind = CodexActivitySessionKind.classify(metadata: payload)
                sessionID = (payload["id"] as? String) ?? (payload["session_id"] as? String) ?? sessionID
                if let value = payload["cwd"] as? String { cwd = value }
            case "turn_context":
                // A missing per-turn field does not clear an owned session setting.
                if payload.keys.contains("service_tier") {
                    switch payload["service_tier"] as? String {
                    case "fast", "priority": cursor.fastMode = true
                    case "default", "standard", "flex": cursor.fastMode = false
                    default: cursor.fastMode = nil
                    }
                }
                if let value = payload["cwd"] as? String { cwd = value }
                if let value = payload["model"] as? String { model = value }
                reasoningEffort = (payload["effort"] as? String) ?? (payload["reasoning_effort"] as? String)
            case "event_msg":
                switch payload["type"] as? String {
                case "thread_settings_applied":
                    let settings = payload["thread_settings"] as? [String: Any]
                    switch settings?["service_tier"] as? String {
                    case "fast", "priority": cursor.threadFastMode = true
                    case "default", "standard", "flex": cursor.threadFastMode = false
                    default: cursor.threadFastMode = settings?["service_tier"] is NSNull ? false : nil
                    }
                    cursor.fastMode = cursor.threadFastMode
                case "task_started":
                    if !tokenState.isTerminated {
                        isActive = true
                        endReason = nil
                        endedAt = nil
                        if startedAt == nil { startedAt = eventTimestamp }
                    }
                case "task_complete", "turn_aborted":
                    let completedTurn = payload["turn_id"] as? String
                    if turnID == nil || completedTurn == nil || completedTurn == turnID {
                        isActive = false
                        if endReason == nil {
                            endReason = eventType == "task_complete" ? .completed : .cancelled
                            endedAt = eventTimestamp
                        }
                    }
                case "agent_message":
                    guard ["commentary", "final"].contains(payload["phase"] as? String ?? "commentary"),
                          let message = payload["message"] as? String,
                          let summary = Self.progressSummary(message)
                    else { break }
                    latestAssistantSummary = summary
                    for index in activities.indices where activities[index].kind == .progress {
                        activities[index].isRunning = false
                    }
                    activities.append(SessionActivityItem(
                        id: "progress-\(eventTimestamp.timeIntervalSince1970)",
                        kind: .progress,
                        title: summary,
                        isRunning: true,
                        updatedAt: eventTimestamp
                    ))
                default: break
                }
            case "response_item":
                switch payload["type"] as? String {
                case "message":
                    guard payload["role"] as? String == "assistant",
                          ["commentary", "final"].contains((payload["channel"] as? String) ?? (payload["phase"] as? String) ?? "final") else { break }
                    let text = (payload["content"] as? [[String: Any]] ?? []).compactMap { part -> String? in
                        ["output_text", "text"].contains(part["type"] as? String ?? "") ? part["text"] as? String : nil
                    }.joined(separator: "\n")
                    if let summary = Self.progressSummary(text) { latestAssistantSummary = summary }
                case "custom_tool_call", "function_call":
                    let callID = (payload["call_id"] as? String) ?? "tool-\(eventTimestamp.timeIntervalSince1970)"
                    if payload["call_id"] as? String != nil, activityIndices[callID] != nil { break }
                    let name = payload["name"] as? String ?? "tool"
                    let input = (payload["input"] as? String) ?? (payload["arguments"] as? String) ?? ""
                    if let last = activities.indices.last, activities[last].kind == .progress {
                        activities[last].isRunning = false
                    }
                    activities.append(SessionActivityItem(
                        id: callID,
                        kind: Self.activityKind(for: name, input: input),
                        title: Self.toolSummary(name: name, input: input),
                        isRunning: true,
                        updatedAt: eventTimestamp
                    ))
                    activityIndices[callID] = activities.count - 1
                case "custom_tool_call_output", "function_call_output":
                    guard let callID = payload["call_id"] as? String,
                          let index = activityIndices[callID],
                          activities.indices.contains(index)
                    else { break }
                    activities[index].isRunning = false
                    activities[index].failed = activities[index].failed || Self.toolOutputFailed(payload)
                    activities[index].updatedAt = eventTimestamp
                default:
                    break
                }
            default:
                break
            }
        }

        if activities.count > 128 {
            activities = Array(activities.suffix(128))
            activityIndices = Dictionary(activities.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { _, new in new })
        }
        cursor.sessionID = sessionID
        cursor.turnID = turnID
        cursor.cwd = cwd
        cursor.model = model
        cursor.isActive = isActive
        cursor.endReason = endReason
        cursor.endedAt = endedAt
        cursor.reasoningEffort = reasoningEffort
        cursor.startedAt = startedAt
        cursor.sessionTotalTokens = sessionTotalTokens
        cursor.latestAssistantSummary = latestAssistantSummary
        cursor.latestTimestamp = latestTimestamp
        cursor.activities = activities
        cursor.activityIndices = activityIndices
        cursor.tokenState = tokenState
        cursor.sessionKind = sessionKind
        rolloutCursors[url] = cursor
        // If a very large transcript tail no longer contains task_started, recent
        // writes are still a useful startup fallback. An explicit completion marker
        // always wins and prevents a recently completed turn appearing active.
        let fileModifiedAt = modificationDate(of: url)
        let hasRunningTool = activities.contains { $0.kind != .progress && $0.isRunning }
        let active = SessionActivityFreshnessPolicy.isActive(
            lifecycleState: isActive,
            hasRunningTool: hasRunningTool,
            updatedAt: latestTimestamp,
            fileModifiedAt: fileModifiedAt
        )
        guard !sessionID.isEmpty else { return nil }
        return LocalSessionSnapshot(
            sessionID: sessionID,
            turnID: turnID,
            cwd: cwd,
            model: model,
            isActive: active,
            updatedAt: latestTimestamp,
            activities: Array(activities.suffix(6)).sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.isRunning && !$1.isRunning
            },
            turnTokenUsage: tokenState.turnID.map {
                TurnTokenUsage(sessionID: sessionID, turnID: $0, total: tokenState.total,
                               isCompleted: tokenState.isCompleted)
            },
            evidence: SessionActivityEvidence(
                lifecycleState: isActive, hasRunningTool: hasRunningTool,
                fileModifiedAt: fileModifiedAt, endReason: endReason, endedAt: endedAt
            ), reasoningEffort: reasoningEffort, startedAt: startedAt,
            sessionTotalTokens: sessionTotalTokens, latestAssistantSummary: latestAssistantSummary, sessionKind: sessionKind,
            fastMode: cursor.fastMode
        )
    }

    /// Only explicit tool-error flags or structured execution envelopes prove failure.
    /// Text mentioning an error (for example a searched document) is not execution evidence.
    static func toolOutputFailed(_ payload: [String: Any]) -> Bool {
        func failed(_ object: [String: Any]) -> Bool {
            for key in ["is_error", "isError"] {
                if let value = object[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID(), value.boolValue { return true }
            }
            guard object["output"] != nil || object["stdout"] != nil || object["stderr"] != nil,
                  object["wall_time_seconds"] != nil || object["chunk_id"] != nil,
                  let code = object["exit_code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(),
                  code.doubleValue.isFinite, code.doubleValue.rounded() == code.doubleValue else { return false }
            return code.doubleValue != 0
        }
        func textFailed(_ text: String) -> Bool {
            guard text.utf8.count <= 262_144, text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
                  ["\"is_error\"", "\"isError\"", "\"exit_code\""].contains(where: { text.contains($0) }),
                  let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return false }
            return failed(object)
        }
        if failed(payload) { return true }
        if let object = payload["output"] as? [String: Any] { return failed(object) }
        if let text = payload["output"] as? String { return textFailed(text) }
        if let parts = payload["output"] as? [[String: Any]] {
            return parts.prefix(64).contains { part in
                if failed(part) { return true }
                guard ["input_text", "text"].contains(part["type"] as? String ?? ""),
                      let text = part["text"] as? String else { return false }
                return textFailed(text)
            }
        }
        return false
    }

    private func consumeCompleteLines(from data: inout Data, discarding: inout Bool, body: (Data) -> Void) {
        var remainder = Data()
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            var start = 0
            for index in bytes.indices where bytes[index] == 0x0A {
                let count = index - start
                if !discarding, count <= 1_048_576 {
                    // Each retained line must own its bytes. Mutating the source
                    // while slices share it copies the whole remaining tail per line.
                    body(Data(bytes: base.advanced(by: start), count: count))
                }
                discarding = false
                start = index + 1
            }
            let count = bytes.count - start
            if count > 1_048_576 { discarding = true }
            else if count > 0 { remainder = Data(bytes: base.advanced(by: start), count: count) }
        }
        data = remainder
    }

    static func sessionIDFromFilename(_ url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let pattern = #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#
        if let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = expression.firstMatch(
                in: stem,
                range: NSRange(stem.startIndex..., in: stem)
           ),
           let range = Range(match.range, in: stem) {
            return String(stem[range])
        }
        return stem.split(separator: "-").suffix(5).joined(separator: "-")
    }

    private func parseDate(_ value: String) -> Date? {
        FastTimestamp.parse(value) ?? fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
    }

    func observeChanges(at urls: [URL], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.updateWatchedFiles(urls)
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }
    private func updateWatchedFiles(_ urls: [URL]) {
        let retained = Set(urls.prefix(maximumCandidateFiles))
        for url in Array(watchedFiles.keys) where !retained.contains(url) {
            watchedFiles.removeValue(forKey: url)?.cancel()
        }
        for url in retained where watchedFiles[url] == nil {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete], queue: queue)
            source.setCancelHandler { close(descriptor) }
            source.setEventHandler { [weak self, weak source] in
                guard let self else { return }
                if source?.data.intersection([.rename, .delete]).isEmpty == false {
                    self.watchedFiles.removeValue(forKey: url)?.cancel()
                }
                self.pendingChange?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    DispatchQueue.main.async { [weak self] in self?.onChange?() }
                }
                self.pendingChange = work
                self.queue.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
            watchedFiles[url] = source; source.resume()
        }
    }
    deinit {
        pendingChange?.cancel()
        watchedFiles.values.forEach { $0.cancel() }
    }

    // Field guards match QuotaView's pinned CodexLocalRolloutLineDecoder.
    // Cumulative totals already include cached input and reasoning output.
    static func cumulativeTokens(type: String, payload: [String: Any], sessionID: String) -> Int? {
        if type == "event_msg", payload["type"] as? String == "token_count",
           let info = payload["info"] as? [String: Any],
           let usage = info["total_token_usage"] as? [String: Any],
           let total = TurnTokenState.count(usage["total_tokens"]) {
            if let last = info["last_token_usage"] as? [String: Any] {
                guard let count = TurnTokenState.count(last["total_tokens"]), total >= count else { return nil }
            }
            return total
        }
        if type == "token_usage_record", payload["thread_id"] as? String == sessionID,
           let thread = payload["thread_token_usage"] as? [String: Any],
           let turn = payload["turn_token_usage"] as? [String: Any],
           let usage = payload["usage"] as? [String: Any],
           let total = TurnTokenState.count(thread["total_tokens"]),
           let direct = TurnTokenState.count(turn["total_tokens"]),
           let last = TurnTokenState.count(usage["total_tokens"]), total >= direct, direct >= last {
            return total
        }
        return nil
    }

    private static func progressSummary(_ message: String) -> String? {
        let cleaned = message
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return cleaned.map { sanitize($0, limit: 512) }
    }

    private static func activityKind(for toolName: String, input: String) -> SessionActivityKind {
        switch toolName {
        case "exec":
            if input.contains("tools.apply_patch") { return .fileChange }
            if input.contains("tools.view_image") { return .read }
            guard extractTitle(from: input) == nil, let command = extractCommand(from: input) else { return .tool }
            if isReadCommand(command) { return .read }
            if isSearchCommand(command) { return .search }
            return .command
        case "apply_patch": return .fileChange
        default: return .tool
        }
    }

    static func toolSummary(name: String, input: String) -> String {
        if name != "exec", let data = input.data(using: .utf8),
           let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = arguments["title"] as? String, !title.isEmpty {
            return sanitize(title)
        }
        switch name {
        case "exec":
            if let title = extractTitle(from: input) {
                return sanitize(title)
            }
            if input.contains("tools.apply_patch") {
                return "修改 · \(extractPatchedFileLabel(from: input) ?? "项目文件")"
            }
            if input.contains("tools.view_image") {
                return "检查图片 · \(fileLabel(from: input) ?? "本地图片")"
            }
            if input.contains("tools.web__run") {
                return "查询网页资料"
            }
            if input.contains("tools.update_plan") {
                return "更新任务计划"
            }
            if input.contains("tools.write_stdin") {
                return "等待构建或测试结果"
            }
            if let command = extractCommand(from: input) {
                if isReadCommand(command) {
                    return "读取 \(fileLabel(from: command) ?? "项目文件")"
                }
                if isSearchCommand(command) {
                    return "搜索 \(fileLabel(from: command) ?? "项目内容")"
                }
                return "运行命令 · \(sanitize(command))"
            }
            return "运行命令"
        case "apply_patch": return "修改项目文件"
        case "view_image": return "检查图片"
        case "web__run": return "查询网页资料"
        default:
            let readable = name.replacingOccurrences(of: "_", with: " ")
            return "调用工具 · \(truncate(readable, limit: 64))"
        }
    }

    private static func extractTitle(from input: String) -> String? {
        extractJSONString(after: #"(?:[\"']?title[\"']?)\s*:"#, from: input)
    }

    private static func extractCommand(from input: String) -> String? {
        extractJSONString(after: #"(?:[\"']?cmd[\"']?)\s*:"#, from: input)
    }

    private static func extractPatchedFileLabel(from input: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"\*\*\*\s+(?:Update|Add)\s+File:\s+([^\r\n]+)"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = expression.firstMatch(in: input, range: range),
              let valueRange = Range(match.range(at: 1), in: input)
        else { return nil }
        let rawPath = String(input[valueRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: rawPath).lastPathComponent
    }

    private static func extractJSONString(after labelPattern: String, from input: String) -> String? {
        guard let label = input.range(of: labelPattern, options: .regularExpression) else { return nil }
        let remainder = input[label.upperBound...]
        guard let openingQuote = remainder.firstIndex(of: "\"") else { return nil }
        var index = remainder.index(after: openingQuote)
        var escaped = false
        while index < remainder.endIndex {
            let character = remainder[index]
            if character == "\"", !escaped {
                let literal = String(remainder[openingQuote...index])
                guard let data = literal.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
            }
            if character == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
            index = remainder.index(after: index)
        }
        return nil
    }

    private static func isReadCommand(_ command: String) -> Bool {
        command.range(
            of: #"(^|[;&|]\s*)(sed\s+-n|cat\s|head\s|tail\s|less\s|bat\s)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isSearchCommand(_ command: String) -> Bool {
        command.range(
            of: #"(^|[;&|]\s*)(rg|grep|find)\s"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func fileLabel(from command: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:^|[\s\"'])([^\s\"']+\.(?:swift|jsonl|json|md|plist|py|sh|js|ts|tsx|jsx|html|css|yml|yaml|toml|txt))(?=$|[\s\"';|])"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(command.startIndex..., in: command)
        let matches = expression.matches(in: command, range: range)
        guard let match = matches.last,
              let valueRange = Range(match.range(at: 1), in: command)
        else { return nil }
        return URL(fileURLWithPath: String(command[valueRange])).lastPathComponent
    }

    private static func sanitize(_ value: String, limit: Int = 88) -> String {
        var output = value
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if let secretPattern = try? NSRegularExpression(
            pattern: #"(?i)(token|api[_-]?key|password|secret)\s*[=:]\s*[^\s,;]+"#
        ) {
            let range = NSRange(output.startIndex..., in: output)
            output = secretPattern.stringByReplacingMatches(in: output, range: range, withTemplate: "$1=••••")
        }
        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return truncate(output.trimmingCharacters(in: .whitespacesAndNewlines), limit: limit)
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }
}

/// Reads user-assigned Codex task names from the local state database. The
/// query is read-only and intentionally ignores prompt-derived fallback titles.
enum CodexThreadNameCatalog {
    private static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
    }

    static func loadNames(from databaseURL: URL? = nil) -> [String: String] {
        let url = databaseURL ?? defaultDatabaseURL
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)

        var statement: OpaquePointer?
        let sql = "SELECT id, name FROM threads WHERE name IS NOT NULL AND trim(name) <> ''"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return [:] }
        defer { sqlite3_finalize(statement) }

        var names: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let nameText = sqlite3_column_text(statement, 1)
            else { continue }
            let id = String(cString: idText)
            let name = String(cString: nameText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, !name.isEmpty { names[id] = name }
        }
        return names
    }
}

enum ProjectActivityAggregator {
    static func projects(
        snapshots: [LocalSessionSnapshot],
        now: Date = Date(),
        catalog: CodexProjectCatalog.State? = nil,
        threadNames: [String: String] = [:]
    ) -> [ActiveProjectState] {
        let catalog = catalog ?? CodexProjectCatalog.loadState()
        let projectNames = catalog.namesByPath
        var sessions: [String: ActiveSessionState] = [:]

        for snapshot in snapshots where snapshot.isActive && [.user, .unknown].contains(snapshot.sessionKind) {
            let runningTool = snapshot.activities.contains { $0.kind != .progress && $0.isRunning }
            let phase: TaskPhase = snapshot.nativePhase ?? (runningTool ? .usingTool : .working)
            let assigned = catalog.assignmentsByThread[snapshot.sessionID]
            let path = normalizedPath(assigned?.path ?? snapshot.cwd, sessionID: snapshot.sessionID)
            let name = assigned?.projectName ?? projectName(path: path, projectNames: projectNames)
            let task = MonitoredTask(
                id: snapshot.sessionID,
                turnID: snapshot.turnID,
                threadName: threadNames[snapshot.sessionID],
                projectName: name,
                projectPath: path,
                model: snapshot.model,
                toolName: nil,
                phase: phase,
                updatedAt: snapshot.updatedAt,
                reasoningEffort: snapshot.reasoningEffort, startedAt: snapshot.startedAt
            )
            sessions[snapshot.sessionID] = ActiveSessionState(task: task, activities: snapshot.activities)
        }

        let grouped = Dictionary(grouping: sessions.values) { session in
            normalizedPath(session.task.projectPath, sessionID: session.id)
        }
        return grouped.map { path, group in
            let orderedSessions = group.sorted(by: sessionComesFirst)
            var representative = orderedSessions[0].task
            representative.projectName = projectName(path: path, projectNames: projectNames)
            let mergedActivities = orderedSessions.flatMap { session in
                session.activities.map { activity in
                    SessionActivityItem(
                        id: "\(session.id)-\(activity.id)",
                        kind: activity.kind,
                        title: activity.title,
                        isRunning: activity.isRunning,
                        updatedAt: activity.updatedAt, failed: activity.failed
                    )
                }
            }.sorted { $0.updatedAt > $1.updatedAt }
            let projectTask = MonitoredTask(
                id: path,
                turnID: representative.turnID,
                threadName: representative.threadName,
                projectName: representative.projectName,
                projectPath: path,
                model: representative.model,
                toolName: representative.toolName,
                phase: representative.phase,
                updatedAt: orderedSessions.map(\.task.updatedAt).max() ?? representative.updatedAt
            )
            return ActiveProjectState(
                id: path,
                name: representative.projectName,
                path: path,
                sessions: orderedSessions,
                task: projectTask,
                activities: mergedActivities
            )
        }.sorted(by: projectComesFirst)
    }

    private static func sessionComesFirst(_ lhs: ActiveSessionState, _ rhs: ActiveSessionState) -> Bool {
        if lhs.task.phase.attentionPriority != rhs.task.phase.attentionPriority {
            return lhs.task.phase.attentionPriority < rhs.task.phase.attentionPriority
        }
        return lhs.task.updatedAt > rhs.task.updatedAt
    }

    private static func projectComesFirst(_ lhs: ActiveProjectState, _ rhs: ActiveProjectState) -> Bool {
        if lhs.task.phase.attentionPriority != rhs.task.phase.attentionPriority {
            return lhs.task.phase.attentionPriority < rhs.task.phase.attentionPriority
        }
        if lhs.task.updatedAt != rhs.task.updatedAt { return lhs.task.updatedAt > rhs.task.updatedAt }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func normalizedPath(_ raw: String, sessionID: String) -> String {
        guard !raw.isEmpty else { return "session://\(sessionID)" }
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }

    private static func projectName(path: String, projectNames: [String: String]) -> String {
        if let savedName = CodexProjectCatalog.displayName(for: path, namesByPath: projectNames) {
            return savedName
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Codex 任务" : name
    }
}
