import Foundation

/// Projects QuotaView's owner-validated desktop stream onto the existing local
/// model. Never reads request bodies or exports conversation state.
struct NativeActivityEvidence {
    let turnID: String
    let phase: TaskPhase
    let title: String
    let startedAt: Date?
    let receivedAt: Date
    let terminal: SessionEndReason?
    var waitReason: CodexActivityWaitReason? = nil
    var pendingAsyncQuestionIDs: Set<String> = []
    var replyRequestIDs: Set<String> = []

    static func project(_ value: CodexDesktopInteractionProjection, previous: Self?, now: Date) -> Self? {
        guard value.sourceKind == .user || value.sourceKind == .unknown,
              let turn = value.currentTurnID, !turn.isEmpty else { return nil }
        let phase: TaskPhase
        let terminal: SessionEndReason?
        var waitReason: CodexActivityWaitReason? = nil
        switch value.status {
        case "inProgress":
            terminal = nil
            let waiting: Bool
            if case let .waiting(reason) = value.threadWaitStatus {
                waiting = true; waitReason = reason
            } else if !value.authoritativePendingIdentities.isEmpty {
                waiting = true
                waitReason = value.authoritativePendingIdentities.allSatisfy {
                    $0.method == "item/tool/requestUserInput" || $0.method == "mcpServer/elicitation/request"
                } ? .userInput : .approval
            } else if !value.authoritativeAsyncQuestionIDs.isEmpty {
                waiting = true; waitReason = .userInput
            } else {
                // Accepted replies settle only the exact async questions that
                // established this wait, even if runtime flags arrive later.
                let answered = Set(value.asyncQuestions.filter { $0.resolvedAnswer != nil }.map(\.questionItemID))
                let resolvedAsyncWait = previous?.turnID == turn && previous?.waitReason == .userInput
                    && value.pendingRequestsAreAuthoritative
                    && previous?.pendingAsyncQuestionIDs.isEmpty == false
                    && previous?.pendingAsyncQuestionIDs.isSubset(of: answered) == true
                waiting = previous?.turnID == turn && previous?.phase == .waitingApproval
                    && !value.provesNoPendingConfirmation && !resolvedAsyncWait
                waitReason = waiting ? previous?.waitReason : nil
            }
            phase = waiting ? .waitingApproval : .working
        case "completed": phase = .completed; terminal = .completed
        case "interrupted": phase = .ended; terminal = .cancelled
        case "failed": phase = .failed; terminal = .failed
        default: return nil
        }
        let pendingQuestions = phase == .waitingApproval && waitReason == .userInput
            ? (value.authoritativeAsyncQuestionIDs.isEmpty
               ? (previous?.turnID == turn ? previous?.pendingAsyncQuestionIDs ?? [] : [])
               : value.authoritativeAsyncQuestionIDs)
            : []
        var replyRequests = Set(value.authoritativeAsyncQuestionIDs.map { "async:" + $0 })
        for request in value.authoritativePendingIdentities where
            request.method == "item/tool/requestUserInput" || request.method == "mcpServer/elicitation/request" {
            switch request.requestID {
            case .string(let id): replyRequests.insert("rpc:\(request.method):string:\(id)")
            case .integer(let id): replyRequests.insert("rpc:\(request.method):integer:\(id)")
            }
        }
        if phase != .waitingApproval || waitReason != .userInput { replyRequests = [] }
        else if replyRequests.isEmpty, previous?.turnID == turn {
            replyRequests = previous?.replyRequestIDs ?? []
        }
        return Self(turnID: turn, phase: phase, title: value.title, startedAt: value.startedAt,
            receivedAt: now, terminal: terminal, waitReason: waitReason,
            pendingAsyncQuestionIDs: pendingQuestions, replyRequestIDs: replyRequests)
    }

    func applying(to local: LocalSessionSnapshot) -> LocalSessionSnapshot? {
        // A native old turn cannot overwrite newer local start/terminal evidence.
        if local.turnID != turnID, let localStart = local.startedAt {
            guard let startedAt, startedAt >= localStart else { return nil }
        }
        if local.turnID == turnID, let ended = local.evidence?.endedAt, ended > receivedAt { return nil }
        let sameTurn = local.turnID == turnID
        let toolRunning = sameTurn && local.activities.contains { $0.kind != .progress && $0.isRunning }
        return LocalSessionSnapshot(sessionID: local.sessionID, turnID: turnID, cwd: local.cwd,
            model: sameTurn ? local.model : nil, isActive: phase.isActive,
            updatedAt: max(receivedAt, sameTurn ? local.updatedAt : .distantPast),
            activities: sameTurn ? local.activities : [], turnTokenUsage: sameTurn ? local.turnTokenUsage : nil,
            evidence: .init(lifecycleState: phase.isActive, hasRunningTool: toolRunning,
                fileModifiedAt: local.evidence?.fileModifiedAt ?? local.updatedAt,
                endReason: terminal, endedAt: terminal == nil ? nil : receivedAt),
            reasoningEffort: sameTurn ? local.reasoningEffort : nil,
            startedAt: startedAt ?? (sameTurn ? local.startedAt : nil), sessionTotalTokens: local.sessionTotalTokens,
            latestAssistantSummary: sameTurn ? local.latestAssistantSummary : nil,
            nativePhase: phase == .working && toolRunning ? .usingTool : phase, sessionKind: local.sessionKind,
            nativeWaitReason: waitReason, nativeReplyRequestIDs: replyRequestIDs)
    }
}

@MainActor
final class NativeActivityObserver {
    private let client: CodexDesktopIPCClient
    private var started = false
    private var followed: Set<String> = []
    private var evidence: [String: NativeActivityEvidence] = [:]
    private(set) var approvalSnapshots: [String: CodexDesktopConversationSnapshot] = [:]
    private(set) var submissionMessages: [String: String] = [:]
    func submit(_ handle: CodexDesktopIPCRequestHandle, result: Data) async -> String {
        if let message = submissionMessages[handle.identity] { return message }
        submissionMessages[handle.identity] = "正在提交"
        let message: String
        do {
            _ = try await client.submit(handle: handle, result: result)
            let current = approvalSnapshots[handle.conversationID]
            message = Self.submissionMessage(for: current?.supportsUntrustedAppInput == true
                && current?.requests.contains(handle) == true ? nil : CodexDesktopIPCError.outcomeUnknown)
        } catch {
            message = Self.submissionMessage(for: error)
        }
        submissionMessages[handle.identity] = message
        publishChange()
        return message
    }
    static func submissionMessage(for error: Error?) -> String {
        guard let error else { return "已发送，等待 Codex 确认" }
        if let error = error as? CodexDesktopIPCError, error == .staleRequest || error == .alreadySubmitted {
            return "请求已变化，请在 Codex 中查看"
        }
        return "结果未知，请在 Codex 中确认"
    }
    // Like QuotaView's terminal-turn registry, positive stale events cannot
    // reopen a settled identity. Keep only one bounded tombstone per follow.
    private var terminalTurns: [String: NativeActivityEvidence] = [:]
    private var excluded: Set<String> = []
    private var revisionKeys: [String: String] = [:]
    private(set) var state: CodexDesktopIPCConnectionState = .disconnected
    private(set) var acceptedSnapshots = 0
    private var publishWork: DispatchWorkItem?
    var onChange: (() -> Void)?
    private func publishChange() {
        guard publishWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.publishWork = nil; self?.onChange?() }
        publishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    init(client: CodexDesktopIPCClient = CodexDesktopIPCClient()) { self.client = client }

    func observe(_ snapshots: [LocalSessionSnapshot]) {
        let desired = Set(snapshots.filter { $0.sessionKind == .user || $0.sessionKind == .unknown }.map(\.sessionID))
        let added = desired.subtracting(followed), removed = followed.subtracting(desired)
        followed = desired
        approvalSnapshots = approvalSnapshots.filter { desired.contains($0.key) }
        evidence = evidence.filter { desired.contains($0.key) }
        terminalTurns = terminalTurns.filter { desired.contains($0.key) }
        excluded.formIntersection(desired)
        revisionKeys = revisionKeys.filter { desired.contains($0.key) }
        if !started {
            started = true
            Task { [weak self, client] in
                await client.start(snapshotHandler: { [weak self] snapshot in
                    guard await client.isCurrent(snapshot) else { return }
                    await self?.receive(snapshot)
                }, stateHandler: { [weak self] state in await self?.connectionChanged(state) },
                invalidationHandler: { [weak self] invalidation in await self?.invalidate(invalidation.conversationID) })
            }
        }
        if !added.isEmpty || !removed.isEmpty {
            Task { [weak self, client] in
                for id in removed { await client.unfollow(conversationID: id) }
                for id in added {
                    guard self?.followed.contains(id) == true else { continue }
                    try? await client.follow(conversationID: id)
                }
            }
        }
    }
    private func receive(_ snapshot: CodexDesktopConversationSnapshot) {
        guard state == .connected, followed.contains(snapshot.conversationID), snapshot.hostID == "local",
              let projection = snapshot.interactionProjection else { return }
        let id = snapshot.conversationID
        if [.user, .unknown].contains(projection.sourceKind) { approvalSnapshots[id] = snapshot }
        else { approvalSnapshots.removeValue(forKey: id) }
        let live = Set(approvalSnapshots.values.flatMap { $0.requests.map(\.identity) })
        submissionMessages = submissionMessages.filter { live.contains($0.key) }
        let revision = "\(snapshot.connectionEpoch)/\(snapshot.streamGeneration)/\(snapshot.revision)"
        guard revisionKeys[id] != revision else { return }
        revisionKeys[id] = revision
        if [.internalTask, .memoryConsolidation, .subagent].contains(projection.sourceKind) {
            excluded.insert(id); evidence.removeValue(forKey: id)
            terminalTurns.removeValue(forKey: id)
        } else {
            excluded.remove(id)
            if let next = NativeActivityEvidence.project(projection, previous: evidence[id], now: Date()) {
                if let terminal = terminalTurns[id], terminal.turnID == next.turnID {
                    evidence[id] = terminal
                } else {
                    evidence[id] = next
                    if next.terminal != nil { terminalTurns[id] = next }
                    else { terminalTurns.removeValue(forKey: id) }
                }
            } else if projection.currentTurnID != evidence[id]?.turnID {
                evidence.removeValue(forKey: id)
            }
        }
        acceptedSnapshots += 1
        publishChange()
    }
    private func connectionChanged(_ value: CodexDesktopIPCConnectionState) {
        state = value
        if value != .connected { disableSubmissions(for: nil) }
        if value != .connected { evidence.removeAll(); revisionKeys.removeAll(); excluded.removeAll() }
        publishChange()
    }
    private func invalidate(_ id: String?) {
        disableSubmissions(for: id)
        if let id { evidence.removeValue(forKey: id); revisionKeys.removeValue(forKey: id) }
        else { evidence.removeAll(); revisionKeys.removeAll() }
        publishChange()
    }
    private func disableSubmissions(for id: String?) {
        for key in Array(approvalSnapshots.keys) where id == nil || key == id {
            guard let snapshot = approvalSnapshots[key] else { continue }
            approvalSnapshots[key] = snapshot.disablingSubmission()
            for handle in snapshot.requests where submissionMessages[handle.identity] != nil {
                submissionMessages[handle.identity] = Self.submissionMessage(for: CodexDesktopIPCError.outcomeUnknown)
            }
        }
    }
    func merge(_ snapshots: [LocalSessionSnapshot], names: [String: String])
        -> (snapshots: [LocalSessionSnapshot], names: [String: String]) {
        var titles = names
        let internalIDs = Set(snapshots.filter { ![CodexActivitySessionKind.user, .unknown].contains($0.sessionKind) }.map(\.sessionID)).union(excluded)
        let result = snapshots.filter { !internalIDs.contains($0.sessionID) }.map { local in
            let terminal = terminalTurns[local.sessionID].flatMap { $0.turnID == local.turnID ? $0 : nil }
            guard let value = evidence[local.sessionID] ?? terminal, let merged = value.applying(to: local) else { return local }
            if !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { titles[local.sessionID] = value.title }
            return merged
        }
        return (result, titles)
    }
    func stop() async {
        approvalSnapshots.removeAll(); submissionMessages.removeAll()
        publishWork?.cancel(); publishWork = nil
        started = false; followed.removeAll(); evidence.removeAll(); terminalTurns.removeAll(); excluded.removeAll(); revisionKeys.removeAll()
        await client.stop()
    }
}
