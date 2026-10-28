// Claude-specific orchestration around QuotaView f779531's MIT bridge and decoders.
import AppKit
import SwiftUI
import Combine
import CryptoKit
import Darwin

@MainActor
final class ClaudeCodeRuntime: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var approvalsEnabled: Bool
    @Published private(set) var statusLineEnabled: Bool
    @Published private(set) var configuring = false
    @Published private(set) var status = "未启用"
    @Published private(set) var error: String?
    @Published private(set) var rows: [ActivitySessionSnapshot] = []
    @Published private(set) var requests: [ClaudePermissionRequest] = []
    @Published private(set) var limits: ClaudeCodeRateLimits?
    @Published private(set) var usage: ClaudeCodeUsageSummary?
    @Published private(set) var scanning = false
    var onRowsChanged: (() -> Void)?
    let installer: ClaudeCodeInstaller
    private let defaults: UserDefaults
    private let bridge: ClaudeCodeBridge
    private let scanner: ClaudeCodeUsageScanner
    private let configurationQueue: DispatchQueue
    private var bridgeListening = false
    private var bridgeGeneration = UUID()
    private var permissionValidAfter = Date.distantPast
    private var bufferedHooks: [(message: ClaudeCodeBridgeMessage, receivedAt: Date)] = []
    var bufferedHookCount: Int { bufferedHooks.count }
    private var desiredConfiguration: (enabled: Bool, approvals: Bool, statusLine: Bool)?
    private var running = false
    private var generation = UUID()
    private var timer: Timer?
    private var usageTask: Task<Void, Never>?
    private var startupUsageTask: Task<Void, Never>?
    private var startupUsageDeadline: Date?
    private var lastUsageScan = Date.distantPast
    private var sessions: [String: Session] = [:]
    private var registryReadInFlight = false
    private var requestWindow: NSWindow?
    private var requestTimeouts: [String: Task<Void, Never>] = [:]
    private struct Session {
        var row: ActivitySessionSnapshot
        var tail: ClaudeCodeTranscriptTail?
        var entries: [String: Int64] = [:]
        var turnEntries: [String: Int64] = [:]
        var completeHistory = true
        var explicitTitle = false
        var submittedAt: Date?
        var lastHookAt = Date.distantPast
        var lastTranscriptAt = Date.distantPast
        var hookProcessID: pid_t?
        var completionEvidence = ClaudeTranscriptCompletionEvidence()
        var registryOwner: ClaudeLiveSessionRegistry.ProcessIdentity?
        var lastRegistrySeenAt = Date.distantPast
        var turnStartKnown = true
        var steps = ClaudeActivitySteps()
    }

    init(defaults: UserDefaults = .standard, installer: ClaudeCodeInstaller? = nil,
         configurationQueue: DispatchQueue = DispatchQueue(label: "com.coverai.codex-pulse.claude.configuration")) {
        self.defaults = defaults
        self.configurationQueue = configurationQueue
        enabled = defaults.bool(forKey: "claude.enabled")
        approvalsEnabled = defaults.object(forKey: "claude.approvals") as? Bool ?? false
        statusLineEnabled = defaults.object(forKey: "claude.statusLine") as? Bool ?? true
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexNotchMonitor/Claude", isDirectory: true)
        let installer = installer ?? ClaudeCodeInstaller(socketURL: base.appendingPathComponent("bridge.sock"),
            authenticationToken: UUID().uuidString + UUID().uuidString)
        self.installer = installer
        bridge = ClaudeCodeBridge(socketURL: installer.socketURL, authenticationToken: installer.authenticationToken)
        scanner = ClaudeCodeUsageScanner(projectsURL: installer.projectsURL)
    }

    func start() {
        guard !running else { return }
        running = true
        if enabled {
            startupUsageDeadline = Date().addingTimeInterval(20)
            configure(enabled: true, approvals: approvalsEnabled, statusLine: statusLineEnabled, startup: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func configure(enabled target: Bool, approvals: Bool, statusLine: Bool, startup: Bool = false) {
        guard !configuring else { return }
        if !startup { cancelStartupUsage() }
        desiredConfiguration = (target, approvals, statusLine)
        configuring = true; error = nil; status = "配置中"
        registryReadInFlight = false
        permissionValidAfter = .distantFuture
        // Revoke all old request capabilities before any configuration change.
        generation = UUID(); usageTask?.cancel(); usageTask = nil; scanning = false
        let configurationGeneration = generation
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts.removeAll()
        for request in requests { bridge.resolve(eventID: request.id, decision: nil) }
        requests.removeAll(); limits = nil
        if target && running {
            do { try startBridge() } catch { self.error = error.localizedDescription }
        } else if !target { stopBridge(); bufferedHooks.removeAll() }
        let installer = installer
        configurationQueue.async { [weak self] in
            let result: Result<Void, Error> = Result {
                if target { try installer.install(.init(interactiveApprovals: approvals, statusLine: statusLine)) }
                else { try installer.uninstall() }
            }
            Task { @MainActor [weak self] in
                guard let self, self.generation == configurationGeneration else { return }
                configuring = false
                switch result {
                case .failure(let failure):
                    status = "需要处理"; error = failure.localizedDescription
                    // Runtime is disconnected; a failed install never claims a live connection.
                    bufferedHooks.removeAll(); stopBridge(); limits = nil
                    sessions.removeAll(); publishRows()
                case .success:
                    enabled = target; approvalsEnabled = approvals; statusLineEnabled = statusLine
                    defaults.set(target, forKey: "claude.enabled")
                    defaults.set(approvals, forKey: "claude.approvals")
                    defaults.set(statusLine, forKey: "claude.statusLine")
                    permissionValidAfter = Date()
                    if !target { sessions.removeAll(); publishRows() }
                    if target && running {
                        do {
                            try startBridge()
                            self.error = nil
                            status = "等待 Claude Code 会话"
                            if let deadline = startupUsageDeadline {
                                scheduleStartupUsage(deadline: deadline)
                            } else {
                                refreshUsage()
                            }
                        } catch { status = "需要处理"; self.error = error.localizedDescription }
                    } else { status = target ? "等待 Claude Code 会话" : "未启用"; usage = nil }
                    let pending = bufferedHooks; bufferedHooks.removeAll()
                    if enabled {
                        for item in pending { receive(item.message, receivedAt: item.receivedAt) }
                        refreshLiveRegistry(recoverMissing: true)
                    }
                }
            }
        }
    }

    private func startBridge() throws {
        guard !bridgeListening else { return }
        let epoch = UUID(); bridgeGeneration = epoch
        try bridge.start(onMessage: { [weak self] message in
            let receivedAt = Date()
            Task { @MainActor in
                guard let self, self.bridgeGeneration == epoch, self.running else { return }
                self.receive(message, receivedAt: receivedAt)
            }
        }, onDisconnect: { [weak self] id in
            Task { @MainActor in
                guard let self, self.bridgeGeneration == epoch else { return }
                self.returnToTerminal(id)
            }
        })
        bridgeListening = true
    }

    private func stopBridge() {
        bridgeGeneration = UUID(); bridgeListening = false; bridge.stop()
    }

    func retry() {
        guard let desiredConfiguration else { return }
        configure(enabled: desiredConfiguration.enabled, approvals: desiredConfiguration.approvals,
                  statusLine: desiredConfiguration.statusLine)
    }

    func stop() {
        cancelStartupUsage()
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts.removeAll()
        running = false; generation = UUID(); timer?.invalidate(); timer = nil
        registryReadInFlight = false
        configuring = false; desiredConfiguration = nil
        usageTask?.cancel(); usageTask = nil; stopBridge(); bufferedHooks.removeAll(); requests.removeAll()
        sessions.removeAll(); publishRows()
    }

    private func cancelStartupUsage() {
        startupUsageTask?.cancel()
        startupUsageTask = nil
        startupUsageDeadline = nil
    }

    private func scheduleStartupUsage(deadline: Date) {
        startupUsageTask = Task { @MainActor [weak self] in
            let delay = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.running else { return }
            self.refreshUsage(startup: true)
        }
    }

    func refreshUsage(startup: Bool = false) {
        cancelStartupUsage()
        guard enabled, !configuring, usageTask == nil else { return }
        scanning = true; let epoch = generation; let scanner = scanner
        usageTask = Task(priority: startup ? .background : .utility) { [weak self] in
            let result = await scanner.scan()
            guard let self, !Task.isCancelled, generation == epoch else { return }
            usage = result; scanning = false; usageTask = nil; lastUsageScan = Date()
        }
    }

    func receive(_ message: ClaudeCodeBridgeMessage, receivedAt: Date = Date()) {
        guard (configuring ? desiredConfiguration?.enabled == true : enabled),
              let object = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any] else {
            bridge.resolve(eventID: message.eventID, decision: nil); return
        }
        if message.kind == "statusLine" {
            guard configuring ? desiredConfiguration?.statusLine == true : statusLineEnabled else { return }
            limits = ClaudeCodeRateLimits.decode(snapshot: message.payload)
            if let id = object["session_id"] as? String,
               var session = sessions["claude:" + id],
               receivedAt >= (session.row.startedAt ?? .distantPast) {
                // Accept JSON booleans only, not strings or numeric values bridged to Bool.
                let value = object["fast_mode"] as? NSNumber
                session.row.fastMode = value.flatMap {
                    CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil
                }
                sessions["claude:" + id] = session
                publishRows()
            }
            return
        }
        if configuring {
            if message.awaitsDecision || object["hook_event_name"] as? String == "PermissionRequest" {
                bridge.resolve(eventID: message.eventID, decision: nil)
                // No permission capability is retained or replayed during reconfiguration.
                return
            }
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            if bufferedHooks.count == 256 { bufferedHooks.removeFirst() }
            bufferedHooks.append((.init(eventID: message.eventID, kind: message.kind,
                awaitsDecision: false, payload: message.payload), receivedAt))
            return
        }
        status = "已连接"
        guard let id = object["session_id"] as? String, !id.isEmpty, id.utf8.count <= 256,
              let event = object["hook_event_name"] as? String else {
            bridge.resolve(eventID: message.eventID, decision: nil); return
        }
        // A callback accepted before/during configuration may reach MainActor after it finishes.
        if message.awaitsDecision || event == "PermissionRequest", receivedAt <= permissionValidAfter {
            bridge.resolve(eventID: message.eventID, decision: nil); return
        }
        let now = receivedAt
        let key = "claude:" + id
        let cwd = object["cwd"] as? String ?? ""
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        if event == "SessionStart" { return }
        if event == "SessionEnd", sessions[key] == nil { return }
        if event == "SessionEnd", sessions[key]?.row.endReason != nil {
            finishRequests(sessionID: key)
            return // A connection closing cannot replace an observed completion/failure receipt.
        }
        if var terminal = sessions[key], terminal.row.endReason != nil {
            if Self.midTurnEvents.contains(event) {
                // Late tool results may refine steps, but cannot reopen a finished turn or its receipt timer.
                terminal.steps.hook(object, at: now, awaitsDecision: false, pending: false)
                updateStepPresentation(&terminal); sessions[key] = terminal
                readTranscript(key, now: now); publishRows()
                if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
                return
            }
            if ["PreToolUse", "PermissionRequest"].contains(event),
               let toolID = object["tool_use_id"] as? String, terminal.steps.knows(toolID) {
                bridge.resolve(eventID: message.eventID, decision: nil)
                return
            }
        }
        guard sessions[key] != nil || sessions.count < 128 else { bridge.resolve(eventID: message.eventID, decision: nil); return }
        // Mid-turn events cannot open a turn. After a restart, a late "subagent returned" or tool-finished
        // event for a session the island never saw would otherwise become an endless "thinking" task.
        if sessions[key] == nil, Self.midTurnEvents.contains(event) { return }
        var session = sessions[key] ?? Session(row: .init(sessionID: key, turnID: UUID().uuidString,
            projectID: "claude:" + cwd, projectName: project.isEmpty ? "Claude Code" : project,
            title: project.isEmpty ? "Claude Code 任务" : project,
            phase: .working, actionText: "Claude Code", updatedAt: now, startedAt: now, provider: "Claude Code"))
        if event == "UserPromptSubmit" || (!session.row.phase.isActive && ["PreToolUse", "PermissionRequest"].contains(event)) {
            finishRequests(sessionID: key)
            let old = session.row
            session.row = .init(sessionID: old.sessionID, turnID: UUID().uuidString,
                projectID: old.projectID, projectName: old.projectName, title: old.title,
                phase: .working, actionText: "正在思考", updatedAt: now,
                modelName: old.modelName, startedAt: now, provider: "Claude Code")
            session.row.endReason = nil; session.turnEntries.removeAll()
            session.turnStartKnown = true
            session.completionEvidence = .init(); session.hookProcessID = nil
            session.submittedAt = event == "UserPromptSubmit" ? now : nil
            session.steps.reset(at: session.submittedAt, promptID: object["prompt_id"] as? String)
        }
        session.lastHookAt = now
        // Fresh hooks take over lifecycle ownership; registry recovery grants no request capability.
        session.registryOwner = nil
        session.lastRegistrySeenAt = .distantPast
        // Missing/invalid current evidence disables the fallback rather than retaining a stale owner.
        session.hookProcessID = Self.validatedHookProcessID(object)
        session.row.updatedAt = now
        if let model = object["model"] as? String { session.row.modelName = model }
        if let title = object["session_title"] as? String, !title.isEmpty {
            session.row.title = String(title.prefix(160)); session.explicitTitle = true
        }
        if let path = object["transcript_path"] as? String, session.tail == nil, validTranscript(path) {
            let size = ClaudeCodeTranscriptTail.fileSize(path) ?? 0
            let offset = size > 1_048_576 ? size - 1_048_576 : 0
            session.completeHistory = offset == 0
            session.tail = .init(path: path, offset: offset)
        }
        session.row.waitReason = nil
        session.steps.hook(object, at: now, awaitsDecision: message.awaitsDecision,
            pending: requests.contains { $0.sessionID == key && $0.toolUseID == (object["tool_use_id"] as? String) })
        switch event {
        case "UserPromptSubmit": session.row.phase = .working; session.row.actionText = "正在思考"
        case "PreToolUse" where !message.awaitsDecision:
            session.row.phase = .usingTool
            session.row.actionText = object["tool_name"] as? String ?? "执行工具"
        case "PostToolUse", "PostToolUseFailure":
            finishRequests(sessionID: key, toolUseID: object["tool_use_id"] as? String)
            session.row.phase = .working
            session.row.actionText = event == "PostToolUseFailure" ? "工具执行失败，等待后续处理" : "工具完成，继续思考"
        case "PermissionRequest", "PreToolUse":
            finishRequests(sessionID: key, toolUseID: object["tool_use_id"] as? String)
            session.row.phase = .waitingApproval; session.row.actionText = "请在 Claude Code 中确认"
            if let request = ClaudePermissionRequest.decode(message, sessionID: key), approvalsEnabled {
                requests.append(request)
                requestTimeouts[request.id] = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(max(0, request.deadline.timeIntervalSinceNow) * 1_000_000_000)) }
                    catch { return }
                    self?.returnToTerminal(request.id)
                }
                session.row.actionText = "点击任务查看 Claude 请求"
                session.row.waitReason = request.questions.isEmpty ? nil : .userInput
                session.row.replyRequestIDs = [request.id]
            } else { bridge.resolve(eventID: message.eventID, decision: nil) }
        case "Stop", "StopFailure", "SessionEnd":
            finishRequests(sessionID: key)
            let cancelled = object["is_interrupt"] as? Bool == true || (object["reason"] as? String)?.contains("interrupt") == true
            let reason: SessionEndReason = cancelled ? .cancelled : event == "StopFailure" ? .failed : event == "Stop" ? .completed : .ended
            session.row.endReason = reason; session.row.phase = reason.phase
            session.row.actionText = (object["last_assistant_message"] as? String).map { String($0.prefix(500)) } ?? reason.title
        case "PreCompact": session.row.phase = .usingTool; session.row.actionText = "正在压缩上下文"
        case "PostCompact": session.row.phase = .working; session.row.actionText = "上下文压缩完成"
        case "SubagentStart": session.row.actionText = "子 Agent 工作中"
        case "SubagentStop": session.row.actionText = "子 Agent 已返回"
        case "Notification":
            guard object["notification_type"] as? String == "permission_prompt" else { return }
            session.row.phase = .waitingApproval; session.row.actionText = "请在 Claude Code 中确认"
        default: return
        }
        updateStepPresentation(&session)
        sessions[key] = session
        readTranscript(key, now: receivedAt)
        publishRows()
    }

    static let midTurnEvents: Set<String> = ["SubagentStop", "PostToolUse", "PostToolUseFailure", "PostCompact"]
    /// A thinking turn with no hook and no transcript growth for this long has stopped without a Stop hook.
    static let quietTurnGrace: TimeInterval = 10 * 60

    private func validTranscript(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let root = installer.projectsURL.resolvingSymlinksInPath().path + "/"
        return url.pathExtension == "jsonl" && url.resolvingSymlinksInPath().path.hasPrefix(root)
    }

    private func readTranscript(_ key: String, now: Date = Date()) {
        guard var session = sessions[key], var tail = session.tail else { return }
        let lines = tail.readLines(maximumBytes: 1_048_576)
        if !lines.isEmpty { session.lastTranscriptAt = now }
        for line in lines {
            let records = ClaudeCodeTranscriptDecoder.records(line)
            let timestamp = ClaudeCodeTranscriptDecoder.lineTimestamp(line)
            session.completionEvidence.consume(records, at: timestamp,
                since: session.submittedAt ?? session.row.startedAt ?? session.lastHookAt)
            for record in records {
                switch record {
                case .customTitle(let title): session.row.title = String(title.prefix(160)); session.explicitTitle = true
                case .userPrompt(let title):
                    if let timestamp { session.steps.advanceBoundary(to: timestamp) }
                    if !session.explicitTitle { session.row.title = String(title.prefix(160)) }
                    session.turnEntries.removeAll()
                    if session.registryOwner != nil || !session.turnStartKnown,
                       let timestamp,
                       timestamp > (session.row.startedAt ?? .distantPast) {
                        session.row.startedAt = timestamp; session.submittedAt = timestamp
                        session.turnStartKnown = true
                    }
                case .usage(let id, let model, let usage, let timestamp):
                    session.entries[id] = max(session.entries[id] ?? 0, usage.total)
                    if session.submittedAt == nil || timestamp.map({ $0 >= session.submittedAt!.addingTimeInterval(-1) }) == true {
                        session.turnEntries[id] = max(session.turnEntries[id] ?? 0, usage.total)
                    }
                    session.row.modelName = model
                case .assistantText(_, let text):
                    if !session.row.phase.isActive { session.row.actionText = String(text.prefix(500)) }
                default: break
                }
                if let timestamp { session.steps.transcript(record, at: timestamp) }
            }
        }
        session.tail = tail
        // A partial tail cannot prove there is no later tool_use; wait until the file is caught up.
        if session.row.phase.isActive, !tail.hasPendingLine, tail.offset == ClaudeCodeTranscriptTail.fileSize(tail.path),
           let end = session.completionEvidence.terminal(after: session.lastHookAt, now: now) {
            finishRequests(sessionID: key)
            session.row.endReason = end.interrupted ? .cancelled : .completed
            session.row.phase = session.row.endReason!.phase
            session.row.updatedAt = end.date
            session.row.actionText = session.completionEvidence.assistantText ?? session.row.statusTitle
            session.row.waitReason = nil; session.row.replyRequestIDs = []
        }
        session.row.sessionTotalTokens = session.completeHistory ? Int(session.entries.values.reduce(0, +)) : nil
        if let turn = session.row.turnID, !session.turnEntries.isEmpty, session.turnStartKnown {
            session.row.tokenUsage = .init(sessionID: key, turnID: turn,
                total: Int(session.turnEntries.values.reduce(0, +)), isCompleted: !session.row.phase.isActive)
        }
        updateStepPresentation(&session)
        sessions[key] = session
    }

    func tick(now: Date = Date()) {
        guard enabled, !configuring else { return }
        refreshLiveRegistry()
        for request in requests where now >= request.deadline { returnToTerminal(request.id) }
        for key in Array(sessions.keys) {
            readTranscript(key, now: now)
            if var session = sessions[key], session.row.phase.isActive, let pid = session.hookProcessID,
               Self.processHasExited(pid) {
                finishRequests(sessionID: key)
                session.row.endReason = .ended; session.row.phase = .ended; session.row.updatedAt = now
                session.row.actionText = session.row.statusTitle
                session.row.waitReason = nil; session.row.replyRequestIDs = []
                sessions[key] = session
            }
            // Tools may legitimately run for hours and approvals wait on the user; only plain thinking times out.
            if var session = sessions[key], [.starting, .working].contains(session.row.phase),
               now.timeIntervalSince(max(session.lastHookAt, session.lastTranscriptAt, session.lastRegistrySeenAt)) >= Self.quietTurnGrace {
                finishRequests(sessionID: key)
                session.row.endReason = .ended; session.row.phase = .ended; session.row.updatedAt = now
                session.row.actionText = session.row.statusTitle
                session.row.waitReason = nil; session.row.replyRequestIDs = []
                sessions[key] = session
            }
        }
        // Expiry removes stale activity; only Hook, transcript or process evidence creates a receipt.
        sessions = sessions.filter { _, value in
            now.timeIntervalSince(value.row.updatedAt) < (value.row.phase.isActive ? 21_600 : ActivityIslandSessionRetention.duration)
        }
        for key in Array(sessions.keys) {
            guard var session = sessions[key], !session.row.phase.isActive else { continue }
            session.row.isRetainedReceipt = now.timeIntervalSince(session.row.updatedAt) >= 15
            sessions[key] = session
        }
        publishRows()
        if startupUsageDeadline == nil,
           now.timeIntervalSince(lastUsageScan) > (usage?.complete == false ? 5 : 60) { refreshUsage() }
    }

    private func refreshLiveRegistry(recoverMissing: Bool = false) {
        guard running, enabled, !configuring, !registryReadInFlight else { return }
        let tracked = sessions.compactMapValues { $0.row.phase.isActive ? $0.registryOwner : nil }
        guard recoverMissing || !tracked.isEmpty else { return }
        registryReadInFlight = true
        let epoch = generation
        let registry = ClaudeLiveSessionRegistry(configurationDirectory: installer.configurationDirectory)
        configurationQueue.async { [weak self] in
            let records = registry.read(includeTranscripts: recoverMissing)
            let liveOwners = Set(tracked.filter { ClaudeLiveSessionRegistry.isCurrent($0.value) }.keys)
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch, self.running, self.enabled, !self.configuring else { return }
                self.registryReadInFlight = false
                self.applyLiveRegistry(records, liveOwners: liveOwners, recoverMissing: recoverMissing)
            }
        }
    }

    private func applyLiveRegistry(_ records: [ClaudeLiveSessionRegistry.Record], liveOwners: Set<String>,
                                   recoverMissing: Bool, now: Date = Date()) {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ("claude:" + $0.sessionID, $0) })
        for key in Array(sessions.keys) {
            guard var session = sessions[key], session.row.phase.isActive, let owner = session.registryOwner else { continue }
            let record = byID[key].flatMap { $0.process == owner ? $0 : nil }
            if record?.status == "busy" { session.lastRegistrySeenAt = now }
            let idle = record?.status == "idle" && (record?.statusAt ?? .distantPast) >= session.lastHookAt
            if !liveOwners.contains(key) || idle {
                session.row.phase = .ended; session.row.endReason = .ended
                session.row.updatedAt = now; session.row.actionText = idle ? "Claude Code 已空闲" : "会话已结束"
                session.registryOwner = nil
            }
            sessions[key] = session
        }
        if recoverMissing {
            for record in records where record.status == "busy" {
                let key = "claude:" + record.sessionID
                guard sessions[key] == nil, sessions.count < 128,
                      ClaudeLiveSessionRegistry.isCurrent(record.process) else { continue }
                let project = URL(fileURLWithPath: record.cwd).lastPathComponent
                let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                var session = Session(row: .init(sessionID: key, turnID: UUID().uuidString,
                    projectID: "claude:" + record.cwd, projectName: project.isEmpty ? "Claude Code" : project,
                    title: title?.isEmpty == false ? title! : (project.isEmpty ? "Claude Code 任务" : project),
                    phase: .working, actionText: "正在继续执行", updatedAt: now,
                    provider: "Claude Code"))
                session.submittedAt = record.statusAt; session.lastHookAt = record.statusAt
                session.hookProcessID = record.process.pid; session.registryOwner = record.process
                session.lastRegistrySeenAt = now
                session.turnStartKnown = false
                session.steps.reset(at: record.statusAt)
                session.explicitTitle = title?.isEmpty == false
                if let path = record.transcriptPath, validTranscript(path) {
                    let size = ClaudeCodeTranscriptTail.fileSize(path) ?? 0
                    let offset = size > 1_048_576 ? size - 1_048_576 : 0
                    session.tail = .init(path: path, offset: offset); session.completeHistory = offset == 0
                }
                sessions[key] = session
                readTranscript(key, now: now)
                status = "已连接"
            }
        }
        publishRows()
    }

    static func processHasExited(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(pid, 0) == -1 && errno == ESRCH
    }

    static func validatedHookProcessID(_ payload: [String: Any]) -> pid_t? {
        guard let number = payload["hook_process_id"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue > 1,
              number.doubleValue <= Double(Int32.max), number.doubleValue.rounded() == number.doubleValue,
              let rawName = payload["hook_process_name"] as? String,
              !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = URL(fileURLWithPath: rawName).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = String(name.drop(while: { $0 == "-" })).lowercased()
        guard !executable.isEmpty,
              !["sh", "bash", "zsh", "dash", "fish", "env", "login", "timeout"].contains(executable) else { return nil }
        let pid = pid_t(number.int32Value)
        return Darwin.kill(pid, 0) == 0 ? pid : nil
    }

    private func publishRows() {
        for key in Array(sessions.keys) {
            guard var session = sessions[key] else { continue }
            updateStepPresentation(&session)
            sessions[key] = session
        }
        let value = sessions.values.map(\.row).sorted { $0.updatedAt > $1.updatedAt }
        if value != rows { rows = value; onRowsChanged?() }
    }

    private func updateStepPresentation(_ session: inout Session) {
        if !session.row.phase.isActive { session.steps.endUnfinished() }
        session.row.recentSteps = session.steps.visible
        guard session.row.phase.isActive else { return }
        if let pending = requests.first(where: { $0.sessionID == session.row.sessionID }) {
            session.row.phase = .waitingApproval
            session.row.waitReason = pending.questions.isEmpty ? nil : .userInput
            session.row.actionText = "点击任务查看 Claude 请求"
        } else if session.row.phase == .working || session.row.phase == .usingTool, let title = session.steps.runningTitle {
            session.row.phase = .usingTool; session.row.actionText = title
        } else if session.registryOwner != nil, session.row.phase == .usingTool,
                  session.steps.runningTitle == nil, !session.row.recentSteps.isEmpty {
            session.row.phase = .working; session.row.actionText = "正在继续执行"
        }
        // The transcript evidence already excludes prior turns and private thinking blocks.
        // Keep the public progress line separate from tool-node titles and approval prompts.
        if session.row.phase == .working || session.row.phase == .usingTool,
           let text = session.completionEvidence.assistantText,
           let line = text.replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            session.row.actionText = line
        }
    }

    private func finishRequests(sessionID: String, toolUseID: String? = nil) {
        let removed = requests.filter { $0.sessionID == sessionID && (toolUseID == nil || $0.toolUseID == toolUseID) }
        for request in removed {
            requestTimeouts.removeValue(forKey: request.id)?.cancel()
            bridge.resolve(eventID: request.id, decision: nil)
        }
        requests.removeAll { request in removed.contains { $0.id == request.id } }
    }

    func respond(_ id: String, choice: ClaudePermissionRequest.Choice, answers: [String: String] = [:]) {
        guard enabled, approvalsEnabled, !configuring, let request = requests.first(where: { $0.id == id }),
              let decision = request.decision(choice, answers: answers) else { return }
        guard Date() < request.deadline else { returnToTerminal(id); return }
        requestTimeouts.removeValue(forKey: id)?.cancel()
        requests.removeAll { $0.id == id }
        bridge.resolve(eventID: id, decision: decision)
        if var session = sessions[request.sessionID] {
            session.row.actionText = "已发送决定，等待 Claude Code 响应"
            sessions[request.sessionID] = session; publishRows()
        }
    }

    func returnToTerminal(_ id: String) {
        guard let request = requests.first(where: { $0.id == id }) else { return }
        requestTimeouts.removeValue(forKey: id)?.cancel()
        requests.removeAll { $0.id == id }; bridge.resolve(eventID: id, decision: nil)
        if var session = sessions[request.sessionID] {
            session.row.actionText = "已交回 Claude Code 终端"
            session.row.replyRequestIDs.remove(id)
            sessions[request.sessionID] = session; publishRows()
        }
    }

    func showRequests(for sessionID: String? = nil) {
        if requestWindow == nil {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 580),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Claude Code 请求"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ClaudeRequestsView(runtime: self))
            requestWindow = window
        }
        requestWindow?.center(); requestWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
