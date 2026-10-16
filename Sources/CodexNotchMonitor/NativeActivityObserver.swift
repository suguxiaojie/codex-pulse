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

    static func project(_ value: CodexDesktopInteractionProjection, previous: Self?, now: Date) -> Self? {
        guard value.sourceKind == .user || value.sourceKind == .unknown,
              let turn = value.currentTurnID, !turn.isEmpty else { return nil }
        let phase: TaskPhase
        let terminal: SessionEndReason?
        switch value.status {
        case "inProgress":
            terminal = nil
            let waiting: Bool
            if case .waiting = value.threadWaitStatus { waiting = true }
            else if !value.authoritativePendingIdentities.isEmpty { waiting = true }
            else { waiting = previous?.turnID == turn && previous?.phase == .waitingApproval && !value.provesNoPendingConfirmation }
            phase = waiting ? .waitingApproval : .working
        case "completed": phase = .completed; terminal = .completed
        case "interrupted": phase = .ended; terminal = .cancelled
        case "failed": phase = .failed; terminal = .failed
        default: return nil
        }
        return Self(turnID: turn, phase: phase, title: value.title, startedAt: value.startedAt, receivedAt: now, terminal: terminal)
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
            nativePhase: phase == .working && toolRunning ? .usingTool : phase, sessionKind: local.sessionKind)
    }
}

@MainActor
final class NativeActivityObserver {
    private let client: CodexDesktopIPCClient
    private var started = false
    private var followed: Set<String> = []
    private var evidence: [String: NativeActivityEvidence] = [:]
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
        if value != .connected { evidence.removeAll(); revisionKeys.removeAll(); excluded.removeAll() }
        publishChange()
    }
    private func invalidate(_ id: String?) {
        if let id { evidence.removeValue(forKey: id); revisionKeys.removeValue(forKey: id) }
        else { evidence.removeAll(); revisionKeys.removeAll() }
        publishChange()
    }
    func merge(_ snapshots: [LocalSessionSnapshot], names: [String: String], hooks: [MonitoredTask])
        -> (snapshots: [LocalSessionSnapshot], names: [String: String], hooks: [MonitoredTask]) {
        var titles = names
        var nativeIDs = Set<String>()
        let internalIDs = Set(snapshots.filter { ![CodexActivitySessionKind.user, .unknown].contains($0.sessionKind) }.map(\.sessionID)).union(excluded)
        let result = snapshots.filter { !internalIDs.contains($0.sessionID) }.map { local in
            let terminal = terminalTurns[local.sessionID].flatMap { $0.turnID == local.turnID ? $0 : nil }
            guard let value = evidence[local.sessionID] ?? terminal, let merged = value.applying(to: local) else { return local }
            nativeIDs.insert(local.sessionID)
            if !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { titles[local.sessionID] = value.title }
            return merged
        }
        return (result, titles, hooks.filter { !nativeIDs.contains($0.id) && !internalIDs.contains($0.id) })
    }
    func stop() async {
        publishWork?.cancel(); publishWork = nil
        started = false; followed.removeAll(); evidence.removeAll(); terminalTurns.removeAll(); excluded.removeAll(); revisionKeys.removeAll()
        await client.stop()
    }
}
