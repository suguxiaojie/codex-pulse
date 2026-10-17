import Foundation

/// One row always belongs to one session and one observed turn, never to a
/// project's representative task or merged activity list.
struct ActivitySessionSnapshot: Identifiable, Equatable {
    var id: String { sessionID }
    let sessionID: String
    let turnID: String?
    let projectID: String
    let projectName: String
    var title: String
    var phase: TaskPhase
    var actionText: String
    var updatedAt: Date
    var tokenUsage: TurnTokenUsage?
    var endReason: SessionEndReason? = nil
    var modelName: String? = nil
    var reasoningEffort: String? = nil
    var startedAt: Date? = nil
    var sessionTotalTokens: Int? = nil
    var isPrivate = false
    var waitReason: CodexActivityWaitReason? = nil

    var tokenTitle: String {
        guard !isPrivate, let sessionTotalTokens else { return "— tokens" }
        return "\(CodexActivityTokenUsageFormatter.string(for: Int64(sessionTotalTokens))) tokens"
    }
    var displayedTokenTitle: String {
        guard phase == .completed, !isPrivate else { return tokenTitle }
        let total: Int? = tokenUsage.flatMap { usage in
            guard let turnID, !turnID.isEmpty, usage.sessionID == sessionID, usage.turnID == turnID else { return nil }
            return usage.total
        }
        let turn = total.map { CodexActivityTokenUsageFormatter.string(for: Int64($0)) } ?? "—"
        return "本轮 \(turn) tokens · 累计 \(tokenTitle)"
    }
    func hidingDetails() -> Self {
        Self(sessionID: sessionID, turnID: turnID, projectID: projectID, projectName: "项目",
             title: "Codex 任务", phase: phase, actionText: "任务内容已隐藏", updatedAt: updatedAt,
             tokenUsage: nil, endReason: endReason, isPrivate: true, waitReason: waitReason)
    }

    var statusTitle: String {
        if endReason == .cancelled { return "已取消" }
        switch phase {
        case .starting: return "开始中"
        case .working: return "思考中"
        case .usingTool: return "工作中"
        case .waitingApproval: return waitReason == .userInput ? "待回复" : "待确认"
        case .completed: return "已完成"
        case .ended: return "已结束"
        case .failed: return "失败"
        }
    }

    static func statusSummary(_ rows: [Self]) -> String {
        let counts = Dictionary(grouping: rows, by: \.statusTitle).mapValues(\.count)
        return ["待确认", "待回复", "开始中", "思考中", "工作中", "失败", "已完成", "已取消", "已结束"]
            .compactMap { title in counts[title].map { "\($0) \(title)" } }.joined(separator: " · ")
    }

    var modelTitle: String {
        [modelName?.replacingOccurrences(of: "gpt-", with: "").replacingOccurrences(of: "-", with: " ").capitalized,
         reasoningEffort?.capitalized].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    func durationTitle(at now: Date = Date()) -> String {
        guard let startedAt else { return "—" }
        let seconds = max(0, Int((endReason == nil ? now : updatedAt).timeIntervalSince(startedAt)))
        return seconds < 60 ? "<1m" : seconds < 3600 ? "\(seconds / 60)m" : "\(seconds / 3600)h"
    }

    var compactTaskText: String {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = action.isEmpty || action == phase.title ? title : action
        return [statusTitle, detail == statusTitle ? "" : detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    static func compactFocus(rows: [Self], selectedID: String?, receipt: Self?) -> Self? {
        let selected = rows.first { $0.id == selectedID } ?? rows.first
        if selected?.phase == .waitingApproval { return selected }
        if let waiting = rows.first(where: { $0.phase == .waitingApproval }) { return waiting }
        if rows.contains(where: { $0.phase.isActive }), let receipt,
           let completed = rows.first(where: { $0.id == receipt.id && $0.turnID == receipt.turnID && $0.phase == .completed }) { return completed }
        if let selected, selected.phase.isActive { return selected }
        return rows.first(where: { $0.phase.isActive }) ?? selected
    }

    static func matchingUsage(_ usages: [String: TurnTokenUsage], sessionID: String,
                              turnID: String?) -> TurnTokenUsage? {
        guard let turnID, !turnID.isEmpty, let usage = usages[sessionID], usage.sessionID == sessionID,
              usage.turnID == turnID else { return nil }
        return usage
    }
}

/// In-memory presentation history. Missing/expired sources simply remove a row;
/// only a terminal event for a previously observed turn can create a receipt.
struct ActivitySessionState {
    private(set) var rows: [ActivitySessionSnapshot] = []
    private var receiptDeadlines: [String: Date] = [:]
    private var residentOrder: [String] = []

    mutating func update(projects: [ActiveProjectState], snapshots: [LocalSessionSnapshot],
                         usages: [String: TurnTokenUsage],
                         now: Date, completionHold: TimeInterval, threadNames: [String: String] = [:]) {
        var incoming: [ActivitySessionSnapshot] = []
        var seen: Set<String> = []
        for project in projects {
            for session in project.sessions where seen.insert(session.id).inserted {
                let task = session.task
                let title = task.threadName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let previous = rows.first { $0.sessionID == session.id }
                let sameTurn = task.turnID != nil && previous?.turnID == task.turnID ? previous : nil
                let local = snapshots.first { $0.sessionID == session.id && $0.turnID == task.turnID }
                let activity = session.activities.filter { $0.kind != .progress && $0.isRunning }.max { $0.updatedAt < $1.updatedAt }
                let action = task.phase == .waitingApproval && local?.nativeWaitReason == .userInput
                    ? "请在 Codex 中选择或回复"
                    : task.phase == .usingTool ? activity?.title ?? task.phase.title
                    : local?.latestAssistantSummary ?? task.phase.title
                incoming.append(ActivitySessionSnapshot(
                    sessionID: session.id, turnID: task.turnID, projectID: project.id,
                    projectName: project.name, title: title.isEmpty ? previous?.title ?? project.name : title,
                    phase: task.phase, actionText: action,
                    updatedAt: max(task.updatedAt, activity?.updatedAt ?? .distantPast),
                    tokenUsage: ActivitySessionSnapshot.matchingUsage(usages, sessionID: session.id, turnID: task.turnID),
                    modelName: task.model ?? local?.model ?? sameTurn?.modelName,
                    reasoningEffort: task.reasoningEffort ?? local?.reasoningEffort ?? sameTurn?.reasoningEffort,
                    startedAt: task.startedAt ?? local?.startedAt ?? sameTurn?.startedAt,
                    sessionTotalTokens: [local?.sessionTotalTokens, previous?.sessionTotalTokens].compactMap { $0 }.max(),
                    waitReason: task.phase == .waitingApproval ? local?.nativeWaitReason ?? sameTurn?.waitReason : nil
                ))
            }
        }
        var deadlines: [String: Date] = [:]
        for previous in rows where !seen.contains(previous.sessionID) {
            let local = snapshots.first { $0.sessionID == previous.sessionID }
            // A new turn supersedes the old receipt even before it is active.
            if let turn = local?.turnID, turn != previous.turnID { continue }

            var row = previous
            var deadline = receiptDeadlines[row.sessionID]
            if previous.phase.isActive {
                guard previous.turnID?.isEmpty == false else { continue }
                let localEnd = local?.turnID == previous.turnID ? local?.evidence?.endReason : nil
                guard let reason = localEnd else { continue }
                row.phase = reason.phase
                row.endReason = reason
                row.actionText = row.statusTitle
                row.updatedAt = min(now, local?.evidence?.endedAt ?? local?.updatedAt ?? now)
                deadline = now.addingTimeInterval(completionHold)
            }
            guard let deadline, now < deadline else { continue }
            if let usage = ActivitySessionSnapshot.matchingUsage(usages, sessionID: row.sessionID, turnID: row.turnID) {
                row.tokenUsage = usage
            }
            if let title = threadNames[row.sessionID]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                row.title = title
            }
            if local?.turnID == row.turnID {
                row.modelName = local?.model ?? row.modelName
                row.reasoningEffort = local?.reasoningEffort ?? row.reasoningEffort
                row.startedAt = local?.startedAt ?? row.startedAt
                row.sessionTotalTokens = [local?.sessionTotalTokens, row.sessionTotalTokens].compactMap { $0 }.max()
            }
            incoming.append(row)
            deadlines[row.sessionID] = deadline
        }

        // Stable resident order; only requests needing attention move to the front.
        residentOrder = CompactProjectLayout.reconcileOrder(existing: residentOrder, discovered: incoming.map(\.id))
        let order = Dictionary(uniqueKeysWithValues: residentOrder.enumerated().map { ($0.element, $0.offset) })
        rows = incoming.sorted {
            let left = $0.phase == .waitingApproval, right = $1.phase == .waitingApproval
            if left != right { return left }
            return order[$0.id, default: 0] < order[$1.id, default: 0]
        }
        receiptDeadlines = deadlines
    }
}

// Reused from QuotaView d16307f, Copyright (c) 2026 Duoasa, MIT.
enum CodexActivityTokenUsageFormatter {
    static func string(for totalTokens: Int64) -> String {
        let tokens = max(totalTokens, 0)
        if tokens >= 1_000_000_000 {
            return compact(Double(tokens) / 1_000_000_000, suffix: "B")
        }
        if tokens >= 1_000_000 {
            return compact(
                Double(tokens) / 1_000_000,
                suffix: "M"
            )
        }
        if tokens >= 1_000 {
            return compact(Double(tokens) / 1_000, suffix: "K")
        }
        return String(tokens)
    }

    private static func compact(
        _ value: Double,
        suffix: String
    ) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int64(rounded))\(suffix)"
        }
        return String(
            format: "%.1f%@",
            locale: Locale(identifier: "en_US_POSIX"),
            rounded,
            suffix
        )
    }
}
