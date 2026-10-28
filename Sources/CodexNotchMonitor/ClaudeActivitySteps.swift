import Foundation

/// Bounded, per-turn tool evidence shared by Hook and transcript projections.
/// An end-only record stays hidden until its matching start supplies a real tool name.
struct ClaudeActivitySteps {
    private struct Entry {
        let id: String
        var title: String?
        var startedAt: Date
        var state: IslandStep.State
        var liveStart = false
        var hasSummary = false
    }
    private var entries: [Entry] = []
    private var retiredIDs: [String] = []
    private(set) var boundary: Date?
    private var promptID: String?
    var retainedCount: Int { entries.count + retiredIDs.count }
    func knows(_ id: String) -> Bool { retiredIDs.contains(id) || entries.contains { $0.id == id } }

    mutating func reset(at date: Date?, promptID: String? = nil) {
        retire(entries.map(\.id))
        entries.removeAll(keepingCapacity: true); boundary = date; self.promptID = promptID
    }
    mutating func advanceBoundary(to date: Date) {
        guard boundary == nil || date > boundary! else { return }
        retire(entries.filter { $0.startedAt < date }.map(\.id))
        boundary = date
        entries.removeAll { $0.startedAt < date }
    }
    private mutating func retire(_ ids: [String]) {
        retiredIDs.append(contentsOf: ids)
        if retiredIDs.count > 256 { retiredIDs.removeFirst(retiredIDs.count - 256) }
    }
    private func accepts(_ id: String, at date: Date) -> Bool {
        !id.isEmpty && id.utf8.count <= 256 && !retiredIDs.contains(id) && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (boundary == nil || date >= boundary!)
    }
    private func active(_ state: IslandStep.State) -> Bool { state.isActive }
    private mutating func trim() {
        guard entries.count > 128 else { return }
        let candidates = entries.indices.filter { !active(entries[$0].state) }
        if let index = (candidates.isEmpty ? Array(entries.indices) : candidates).min(by: { entries[$0].startedAt < entries[$1].startedAt }) {
            entries.remove(at: index)
        }
    }
    mutating func start(id: String, name: String, at date: Date, waiting: Bool = false, liveHook: Bool = false,
                        summary: String? = nil) {
        guard accepts(id, at: date) else { return }
        let base = Self.title(for: name)
        guard !base.isEmpty else { return }
        let detail = name.lowercased() == "bash" ? summary.flatMap {
            String($0.prefix(512)).replacingOccurrences(of: "`", with: "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }).map { String($0.prefix(160)) }
        } : nil
        let title = detail.map { base + " · " + $0 } ?? base
        if let index = entries.firstIndex(where: { $0.id == id }) {
            if detail != nil || !entries[index].hasSummary {
                entries[index].title = title
                entries[index].hasSummary = detail != nil
            }
            entries[index].liveStart = entries[index].liveStart || liveHook
            entries[index].startedAt = min(entries[index].startedAt, date)
            guard active(entries[index].state) else { return }
            if waiting { entries[index].state = .waiting }
            else if liveHook || entries[index].state != .waiting { entries[index].state = .running }
        } else {
            entries.append(.init(id: id, title: title, startedAt: date, state: waiting ? .waiting : .running,
                liveStart: liveHook, hasSummary: detail != nil)); trim()
        }
    }
    mutating func finish(id: String, at date: Date, failed: Bool, interrupted: Bool = false) {
        guard accepts(id, at: date) else { return }
        let state: IslandStep.State = interrupted ? .ended : failed ? .failed : .done
        if let index = entries.firstIndex(where: { $0.id == id }) {
            guard entries[index].state != .failed,
                  state != .ended || active(entries[index].state) else { return }
            entries[index].state = state
        } else {
            entries.append(.init(id: id, title: nil, startedAt: date, state: state)); trim()
        }
    }
    mutating func endUnfinished() {
        for index in entries.indices { entries[index].state = entries[index].state.afterTaskEnds }
    }
    mutating func hook(_ object: [String: Any], at date: Date, awaitsDecision: Bool, pending: Bool) {
        guard (object["agent_id"] as? String ?? "").isEmpty,
              let id = object["tool_use_id"] as? String else { return }
        if let current = promptID, let incoming = object["prompt_id"] as? String, current != incoming { return }
        switch object["hook_event_name"] as? String {
        case "PreToolUse", "PermissionRequest":
            start(id: id, name: object["tool_name"] as? String ?? "", at: date,
                  waiting: awaitsDecision || pending || object["hook_event_name"] as? String == "PermissionRequest", liveHook: true,
                  summary: (object["tool_input"] as? [String: Any])?["description"] as? String)
        case "PostToolUse", "PostToolUseFailure":
            finish(id: id, at: date, failed: object["hook_event_name"] as? String == "PostToolUseFailure",
                   interrupted: object["is_interrupt"] as? Bool == true)
        default: break
        }
    }
    mutating func transcript(_ record: ClaudeCodeTranscriptRecord, at date: Date) {
        guard let boundary else { return }
        let id: String
        switch record {
        case .toolUse(let value, _, _), .toolResult(let value, _, _): id = value
        default: return
        }
        // Main-actor delivery can lag the log timestamp. Only a proved live start
        // permits joining an older log record; unrelated old history stays excluded.
        guard date >= boundary || entries.contains(where: { $0.id == id && $0.liveStart }) else { return }
        let evidenceDate = max(date, boundary)
        switch record {
        case .toolUse(let id, let name, let input):
            let object = name.lowercased() == "bash" && input.utf8.count <= 262_144
                ? (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] : nil
            start(id: id, name: name, at: evidenceDate, summary: object?["description"] as? String)
        case .toolResult(let id, _, let failed): finish(id: id, at: evidenceDate, failed: failed)
        default: break
        }
    }
    var runningTitle: String? {
        entries.filter { $0.state == .running && $0.title != nil }.max { $0.startedAt < $1.startedAt }?.title
    }
    var visible: [IslandStep] {
        let named = entries.filter { $0.title != nil }.sorted { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt }
        return IslandStep.visibleSteps(from: named.map { .init(id: $0.id, title: $0.title!, state: $0.state) })
    }
    static func title(for tool: String) -> String {
        let clean = String(tool.prefix(128)).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        switch clean.lowercased() {
        case "read": return "读取文件"
        case "write": return "写入文件"
        case "edit", "multiedit": return "修改文件"
        case "bash": return "运行命令"
        case "grep": return "搜索内容"
        case "glob": return "查找文件"
        case "webfetch": return "读取网页"
        case "websearch": return "搜索网页"
        case "agent", "task": return "调用子 Agent"
        case "askuserquestion": return "询问用户"
        default: return String(clean.prefix(60))
        }
    }
}
