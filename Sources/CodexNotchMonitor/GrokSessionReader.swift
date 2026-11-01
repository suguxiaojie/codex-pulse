import Foundation
import Darwin

struct GrokTurnState: Equatable {
    enum Phase { case idle, working, tool, completed, cancelled, failed, ended }
    var promptID: String?
    var phase = Phase.idle
    var startedAt: Date?
    var updatedAt = Date.distantPast
    var text = ""
    var tokens: Int?
    var steps: [Step] = []
    var retired: [String] = []
    struct Step: Equatable { let id: String; var title: String; var status: String }
    var active: Bool { phase == .working || phase == .tool }
    mutating func consume(_ object: [String: Any]) -> (String, Date, GrokSpend)? {
        guard let params = object["params"] as? [String: Any], let update = params["update"] as? [String: Any],
              let kind = update["sessionUpdate"] as? String else { return nil }
        let meta = params["_meta"] as? [String: Any] ?? [:]
        guard let date = GrokJSON.eventDate(object) else { return nil }
        let prompt = (meta["promptId"] ?? update["prompt_id"]) as? String
        if kind == "user_message_chunk" {
            guard date >= updatedAt else { return nil }
            if let id = promptID { retired.append(id); retired = Array(retired.suffix(128)) }
            promptID = nil; phase = .working; startedAt = date; updatedAt = date; text = ""; steps = []; tokens = nil
            return nil
        }
        if kind == "turn_completed", let prompt {
            // History is deduplicated by the original prompt ID, including inherited fork history.
            let spend = GrokSpend.decode(update["usage"])
            let history = spend.map { (prompt, date, $0) }
            guard !retired.contains(prompt), promptID == nil || promptID == prompt, date >= updatedAt else { return history }
            promptID = prompt; tokens = spend?.tokens; updatedAt = date
            switch update["stop_reason"] as? String {
            case "end_turn", "stop_sequence": phase = .completed
            case "cancelled", "canceled", "user_cancelled", "max_turns", "refusal": phase = .cancelled
            case "error", "failed": phase = .failed
            default: phase = .ended
            }
            for i in steps.indices where steps[i].status != "completed" && steps[i].status != "failed" { steps[i].status = "ended" }
            return history
        }
        if let prompt, retired.contains(prompt) { return nil }
        guard date >= updatedAt, active else { return nil }
        if let prompt {
            guard promptID == nil || promptID == prompt else { return nil }
            promptID = prompt
        }
        if kind == "agent_message_chunk", let content = update["content"] as? [String: Any], content["type"] as? String == "text",
           let value = content["text"] as? String {
            text = String((value.split(whereSeparator: \.isNewline).first.map(String.init) ?? "").prefix(500))
            phase = steps.contains { !["completed", "failed", "ended"].contains($0.status) } ? .tool : .working
        } else if kind == "tool_call" || kind == "tool_call_update", let id = update["toolCallId"] as? String {
            let evidence = meta["updateParams"] as? [String: Any] ?? [:]
            let status = ((update["status"] ?? evidence["status"]) as? String)?.lowercased().replacingOccurrences(of: "_", with: "")
            if let i = steps.firstIndex(where: { $0.id == id }) {
                if let status { steps[i].status = status }
            } else if kind == "tool_call", let title = update["title"] as? String {
                steps.append(.init(id: id, title: String(title.prefix(160)), status: status ?? "pending"))
                steps = Array(steps.suffix(128))
            }
            phase = steps.contains { !["completed", "failed", "ended"].contains($0.status) } ? .tool : .working
        } else if kind != "agent_thought_chunk" { return nil } // Thought content and raw tool input/output are never projected.
        updatedAt = date
        return nil
    }
}

struct GrokSessionScan {
    struct Session {
        let id: String; let cwd: String; let title: String; let model: String?; let turn: GrokTurnState; let caughtUp: Bool
        let totalTokens: Int
    }
    let sessions: [Session]
    let usage: GrokUsageSummary
    let liveIDs: Set<String>
    var registeredIDs: Set<String> = []
}

actor GrokSessionReader {
    private struct State {
        let id: String; let cwd: String; var title: String; var model: String?; let url: URL
        var inode: UInt64 = 0; var offset: UInt64 = 0; var pending = Data(); var skippingLine = false
        var modified = Date.distantPast; var size: UInt64 = 0
        var turn = GrokTurnState()
        var spends: [String: (Date, GrokSpend)] = [:]
        var caughtUp = false
        var corrupt = false
    }
    let home: URL
    private var states: [String: State] = [:]
    private var lastDiscovery = Date.distantPast
    private var lastHistory = Date.distantPast
    private var discoveryComplete = true
    init(home: URL) { self.home = home }

    /// Registry entries are accepted only for a current same-user Grok process with the same start time.
    static func liveIDs(home: URL, evidence: [String: (cwd: String, lastEvent: Date)]? = nil,
                        lookup: (Int32, Double) -> Bool = validProcess) -> Set<String> {
        guard let data = GrokJSON.read(home.appendingPathComponent("active_sessions.json"), maximum: 262_144),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], list.count <= 256 else { return [] }
        let valid = list.compactMap { item -> String? in
            guard let id = item["session_id"] as? String, UUID(uuidString: id) != nil,
                  let pid = GrokJSON.integer(item["pid"]), pid > 1, pid <= Int(Int32.max),
                  let start = GrokJSON.number(item["pid_start"]), start > 0,
                  lookup(Int32(pid), start / 1_000_000) else { return nil }
            if let evidence {
                guard let session = evidence[id], let cwd = item["cwd"] as? String, cwd == session.cwd,
                      session.lastEvent.timeIntervalSince1970 >= start / 1_000_000 - 1 else { return nil }
            }
            return id
        }
        let groups = Dictionary(grouping: valid, by: { $0 })
        return Set(groups.filter { $0.value.count == 1 }.map(\.key))
    }
    static func validProcess(_ pid: Int32, _ start: Double) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid], info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size,
              info.kp_eproc.e_ucred.cr_uid == getuid() else { return false }
        let stamp = info.kp_proc.p_un.__p_starttime
        guard abs(Double(stamp.tv_sec) + Double(stamp.tv_usec) / 1_000_000 - start) < 0.00001 else { return false }
        var bytes = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { return false }
        let name = URL(fileURLWithPath: String(cString: bytes)).lastPathComponent
        let path = String(cString: bytes)
        if name == "grok-native" && path.contains("/@xai-official/grok/bin/") { return true }
        let defaultBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/bin").resolvingSymlinksInPath()
        return (name == "grok" || name.hasPrefix("grok-1."))
            && URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath() == defaultBin
    }

    func scan(now: Date = Date()) -> GrokSessionScan {
        let live = Self.liveIDs(home: home)
        if now.timeIntervalSince(lastDiscovery) >= 30 || !live.isSubset(of: Set(states.keys)) { discover(); lastDiscovery = now }
        let historyDue = now.timeIntervalSince(lastHistory) >= 30
        if historyDue { lastHistory = now }
        var budget = 8_388_608
        for key in states.keys.sorted(by: { live.contains($0) != live.contains($1) ? live.contains($0) : $0 < $1 }) {
            guard var state = states[key], historyDue || live.contains(key) || !state.caughtUp else { continue }
            read(&state, budget: &budget); states[key] = state
        }
        var unique: [String: (Date, GrokSpend)] = [:]
        for state in states.values {
            for (id, value) in state.spends {
                // Conflicting duplicates are incomplete rather than counted twice.
                if let old = unique[id], old.1 != value.1 {
                    unique[id] = (old.0, .init(tokens: max(old.1.tokens, value.1.tokens), cost: nil))
                } else { unique[id] = value }
            }
        }
        var days: [Date: GrokUsageSummary.Day] = [:]
        for (date, spend) in unique.values {
            let day = Calendar.current.startOfDay(for: date)
            var value = days[day] ?? .init(date: day, tokens: 0, cost: 0)
            value.tokens = GrokJSON.add(value.tokens, spend.tokens)
            value.cost = value.cost.flatMap { sum in spend.cost.map { sum + $0 } }
            days[day] = value
        }
        let complete = discoveryComplete && states.values.allSatisfy { $0.caughtUp && !$0.corrupt }
        let sessions = states.values.map { s in GrokSessionScan.Session(id: s.id, cwd: s.cwd, title: s.title, model: s.model,
            turn: s.turn, caughtUp: s.caughtUp, totalTokens: s.spends.values.reduce(0) { GrokJSON.add($0, $1.1.tokens) }) }
        let evidence = states.mapValues { (cwd: $0.cwd, lastEvent: $0.turn.updatedAt) }
        let verifiedLive = Self.liveIDs(home: home, evidence: evidence)
        return .init(sessions: sessions, usage: .init(days: days.values.sorted { $0.date < $1.date }, complete: complete,
            sessionCount: states.count, updatedAt: now), liveIDs: verifiedLive, registeredIDs: live)
    }
    private func directories(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.filter {
            guard let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }.sorted { $0.path < $1.path } ?? []
    }
    private func discover() {
        let root = home.appendingPathComponent("sessions")
        var seen = Set<String>(); var duplicate = Set<String>(); var count = 0
        discoveryComplete = true
        let groups = directories(root)
        if groups.count > 512 { discoveryComplete = false }
        for group in groups.prefix(512) {
            for directory in directories(group) {
                count += 1
                guard count <= 5000 else { discoveryComplete = false; break }
                guard let data = GrokJSON.read(directory.appendingPathComponent("summary.json"), maximum: 262_144),
                      let object = GrokJSON.object(data), let info = object["info"] as? [String: Any],
                      let id = info["id"] as? String, UUID(uuidString: id) != nil, id == directory.lastPathComponent,
                      let cwd = info["cwd"] as? String, cwd.hasPrefix("/") else { discoveryComplete = false; continue }
                if [info["subagentType"], info["subagent_type"], object["subagent_type"], object["subagentType"]].contains(where: { ($0 as? String)?.isEmpty == false }) { continue }
                if !seen.insert(id).inserted { duplicate.insert(id); continue }
                let title = String(((object["generated_title"] as? String) ?? URL(fileURLWithPath: cwd).lastPathComponent).prefix(160))
                if states[id]?.url != directory { states[id] = .init(id: id, cwd: cwd, title: title, model: object["current_model_id"] as? String, url: directory) }
                else { states[id]?.title = title; states[id]?.model = object["current_model_id"] as? String }
            }
        }
        states = states.filter { seen.contains($0.key) && !duplicate.contains($0.key) }
        if !duplicate.isEmpty { discoveryComplete = false }
    }
    private func read(_ state: inout State, budget: inout Int) {
        let url = state.url.appendingPathComponent("updates.jsonl")
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { state.caughtUp = false; return }; defer { close(fd) }
        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0, statInfo.st_uid == getuid(), statInfo.st_mode & S_IFMT == S_IFREG, statInfo.st_size >= 0 else { state.caughtUp = false; return }
        let size = UInt64(statInfo.st_size), inode = UInt64(statInfo.st_ino)
        let modified = Date(timeIntervalSince1970: Double(statInfo.st_mtimespec.tv_sec) + Double(statInfo.st_mtimespec.tv_nsec) / 1e9)
        if state.inode != inode || size < state.offset || (size == state.size && state.modified != modified) {
            state.offset = 0; state.pending = Data(); state.skippingLine = false; state.turn = .init(); state.spends = [:]; state.corrupt = false
        }
        state.inode = inode; state.size = size; state.modified = modified
        while state.offset < size && budget > 0 {
            let length = min(262_144, min(budget, Int(min(size - state.offset, 262_144))))
            var buffer = Data(count: length)
            let readCount = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, length, off_t(state.offset)) }
            guard readCount > 0 else { break }
            buffer.count = readCount; state.offset += UInt64(readCount); budget -= readCount
            var cursor = buffer.startIndex
            while let end = buffer[cursor...].firstIndex(of: 10) {
                    let fragment = buffer[cursor..<end]
                    if !state.skippingLine && state.pending.count + fragment.count <= 1_048_576 { state.pending.append(fragment) }
                    else { state.skippingLine = true; state.corrupt = true }
                    if !state.skippingLine, !state.pending.isEmpty {
                        if let object = GrokJSON.object(state.pending) {
                            if let params = object["params"] as? [String: Any], let update = params["update"] as? [String: Any],
                               update["sessionUpdate"] as? String == "turn_completed",
                               GrokSpend.decode(update["usage"]) == nil || GrokJSON.eventDate(object) == nil {
                                state.corrupt = true
                            }
                            if let (id, date, spend) = state.turn.consume(object) { state.spends[id] = (date, spend) }
                        } else { state.corrupt = true }
                    }
                    state.pending.removeAll(keepingCapacity: true); state.skippingLine = false
                    cursor = buffer.index(after: end)
            }
            if !state.skippingLine {
                let fragment = buffer[cursor...]
                if state.pending.count + fragment.count <= 1_048_576 { state.pending.append(fragment) }
                else { state.pending.removeAll(keepingCapacity: true); state.skippingLine = true; state.corrupt = true }
            }
        }
        state.caughtUp = state.offset == size && state.pending.isEmpty && !state.skippingLine
    }
}
