import Foundation

struct IslandStep: Identifiable, Equatable {
    enum State { case done, running, waiting }
    let id: String
    var title: String
    var state: State
}

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
    var provider = "Codex"
    var isPrivate = false
    var waitReason: CodexActivityWaitReason? = nil
    var replyRequestIDs: Set<String> = []
    var suppressCompletion = false

    var recentSteps: [IslandStep] = []
    var isRetainedReceipt = false

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
             title: provider + " 任务", phase: phase, actionText: "任务内容已隐藏", updatedAt: updatedAt,
             tokenUsage: nil, endReason: endReason, provider: provider, isPrivate: true,
             waitReason: waitReason, replyRequestIDs: replyRequestIDs,
             suppressCompletion: suppressCompletion, isRetainedReceipt: isRetainedReceipt)
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

    var isFreshReceipt: Bool { !phase.isActive && endReason != nil && !isRetainedReceipt }

    /// Expanded-stage selection only. Nil leaves terminal-only handling to the controller.
    static func autoFocus(rows: [Self], previous: [Self], currentFocusID: String?,
                          manualFocusID: String?, now: Date = Date()) -> Self? {
        let live = rows.filter { $0.phase.isActive }
        guard !live.isEmpty else { return nil }
        if let attention = newAttention(in: live, previous: previous) { return attention }
        if let manual = rows.first(where: { $0.id == manualFocusID }) { return manual }
        if let current = rows.first(where: { $0.id == currentFocusID }) {
            let elapsed = now.timeIntervalSince(current.updatedAt)
            if current.phase.isActive || (current.endReason != nil && elapsed >= 0
                && elapsed < ActivityIslandFocusHandoff.duration) { return current }
        }
        return live.first(where: { $0.phase == .waitingApproval }) ?? live.first
    }

    static func newlyCompleted(in rows: [Self], previous: [Self]) -> Self? {
        rows.filter { row in row.phase == .completed && !row.suppressCompletion && !row.isRetainedReceipt && previous.contains {
            $0.id == row.id && $0.turnID == row.turnID && $0.phase.isActive
        } }.max { $0.updatedAt < $1.updatedAt }
    }

    static func newAttention(in rows: [Self], previous: [Self]) -> Self? {
        rows.first { row in row.phase == .waitingApproval && !previous.contains {
            $0.id == row.id && $0.turnID == row.turnID && $0.phase == .waitingApproval
                && $0.replyRequestIDs == row.replyRequestIDs
        } }
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
    private var retentionDeadlines: [String: Date] = [:]
    private var residentOrder: [String] = []

    mutating func update(projects: [ActiveProjectState], snapshots: [LocalSessionSnapshot],
                         usages: [String: TurnTokenUsage],
                         now: Date, completionHold: TimeInterval, retention: TimeInterval = 60, threadNames: [String: String] = [:]) {
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
                    : task.phase == .usingTool ? local?.latestAssistantSummary ?? activity?.title ?? task.phase.title
                    : local?.latestAssistantSummary ?? task.phase.title
                // The existing parser resets activities on turn start; no new source is read.
                let currentActivities = session.activities.filter { $0.kind != .progress }
                    .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt }
                var steps = currentActivities.suffix(3).map {
                    IslandStep(id: $0.id, title: $0.title, state: $0.isRunning ? .running : .done)
                }
                if steps.isEmpty {
                    steps = (sameTurn?.recentSteps ?? []).map { step in
                        var step = step
                        if step.state == .waiting && task.phase != .waitingApproval { step.state = .running }
                        return step
                    }
                }
                if task.phase == .waitingApproval, !steps.isEmpty { steps[steps.count - 1].state = .waiting }
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
                    waitReason: task.phase == .waitingApproval ? local?.nativeWaitReason ?? sameTurn?.waitReason : nil,
                    replyRequestIDs: task.phase == .waitingApproval ? local?.nativeReplyRequestIDs ?? sameTurn?.replyRequestIDs ?? [] : [],
                    suppressCompletion: local?.nativeSuppressCompletion == true || sameTurn?.suppressCompletion == true,
                    recentSteps: steps
                ))
            }
        }
        var deadlines: [String: Date] = [:]
        var retainedDeadlines: [String: Date] = [:]
        for previous in rows where !seen.contains(previous.sessionID) {
            let local = snapshots.first { $0.sessionID == previous.sessionID }
            // A new turn supersedes the old receipt even before it is active.
            if let turn = local?.turnID, turn != previous.turnID { continue }

            var row = previous
            var deadline = receiptDeadlines[row.sessionID]
            var retentionDeadline = retentionDeadlines[row.sessionID]
            if previous.phase.isActive {
                guard previous.turnID?.isEmpty == false else { continue }
                let localEnd = local?.turnID == previous.turnID ? local?.evidence?.endReason : nil
                guard let reason = localEnd else { continue }
                row.phase = reason.phase
                row.suppressCompletion = row.suppressCompletion || local?.nativeSuppressCompletion == true
                row.endReason = reason
                row.actionText = row.statusTitle
                row.updatedAt = min(now, local?.evidence?.endedAt ?? local?.updatedAt ?? now)
                deadline = now.addingTimeInterval(completionHold)
                retentionDeadline = row.updatedAt.addingTimeInterval(retention)
                row.recentSteps = row.recentSteps.map { IslandStep(id: $0.id, title: $0.title, state: .done) }
            }
            guard let deadline, let retentionDeadline, now < retentionDeadline else { continue }
            row.isRetainedReceipt = now >= deadline
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
            retainedDeadlines[row.sessionID] = retentionDeadline
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
        retentionDeadlines = retainedDeadlines
    }
}

// Reused from QuotaView d16307f, Copyright (c) 2026 Duoasa, MIT.
enum CodexActivityTokenUsageFormatter {
    static func string(for totalTokens: Int64) -> String {
        CountFormatter.display(totalTokens)
    }
}
