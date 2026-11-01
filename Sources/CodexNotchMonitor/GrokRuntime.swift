import AppKit
import Combine

@MainActor
final class GrokRuntime: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var quota: GrokQuotaSnapshot?
    @Published private(set) var usage: GrokUsageSummary?
    @Published private(set) var rows: [ActivitySessionSnapshot] = []
    @Published private(set) var refreshing = false
    @Published private(set) var quotaStatus = "尚未查询"
    @Published private(set) var quotaFailed = false
    @Published private(set) var questions: [GrokQuestionRequest] = []
    @Published private(set) var questionStatus = "等待下次正常启动 Grok，自动接入新请求"
    @Published private(set) var automaticReady = false
    @Published private(set) var automaticConfiguring = false
    @Published private(set) var automaticStatus = "一次启用后，正常启动 Grok 即可自动接入"
    private(set) var submittedQuestions: Set<String> = []
    var onRowsChanged: (() -> Void)?
    let home: URL
    private let defaults: UserDefaults
    private let reader: GrokSessionReader
    private let shared: GrokSharedClient
    private var lastScan: GrokSessionScan?
    private var sharedRevision: UInt64 = 0
    var sharedSocketURL: URL { GrokLauncher.sharedSocket(home: home) }
    private var timer: AnyCancellable?
    private var billingTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var client: GrokBillingClient?
    private var generation = 0
    private var lastQuotaAttempt = Date.distantPast
    private var observedTurns = Set<String>()
    private var receipts: [String: ActivitySessionSnapshot] = [:]

    init(home: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let root = home ?? ProcessInfo.processInfo.environment["GROK_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
        self.home = root; reader = GrokSessionReader(home: root)
        shared = GrokSharedClient(socketURL: GrokLauncher.sharedSocket(home: root))
        enabled = defaults.bool(forKey: "grok.enabled")
        shared.onSnapshot = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.consumeShared(snapshot)
            }
        }
        refreshAutomaticStatus()
    }
    func start() {
        guard enabled, timer == nil else { return }
        refreshAutomaticStatus()
        shared.start()
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            self.refreshActivity()
            if Date().timeIntervalSince(self.lastQuotaAttempt) >= 60 { self.refreshQuota() }
        }
    }
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled; defaults.set(enabled, forKey: "grok.enabled")
        generation += 1
        if enabled { start() }
        else {
            timer = nil; client?.cancel(); billingTask?.cancel(); billingTask = nil
            scanTask?.cancel(); scanTask = nil; refreshing = false
            quota = nil; usage = nil; rows = []; receipts = [:]; observedTurns = []
            shared.stop(); questions = []; submittedQuestions = []; lastScan = nil
            quotaStatus = "接入已关闭"; quotaFailed = false; onRowsChanged?()
        }
    }
    func refresh() { refreshQuota(); refreshActivity() }
    func consumeShared(_ snapshot: GrokSharedClient.Snapshot) {
        guard enabled, snapshot.revision > sharedRevision else { return }
        sharedRevision = snapshot.revision
        questions = snapshot.requests; submittedQuestions = snapshot.submitted; questionStatus = snapshot.status
        if let scan = lastScan { projectRows(scan) }
    }
    func refreshAutomaticStatus() {
        do {
            automaticReady = try GrokLauncher.isEnabled(home: home)
            automaticStatus = automaticReady ? "自动接入已就绪，之后照常运行 grok" : "开启后自动识别项目，无需选择文件夹"
        } catch { automaticReady = false; automaticStatus = "无法安全识别 Grok 启动配置，已保留原文件" }
    }
    func enableAutomatic() {
        guard !automaticConfiguring else { return }
        automaticConfiguring = true
        let home = home, setupGeneration = generation
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Result { try GrokLauncher.enable(home: home) } }.value
            guard let self else { return }
            self.automaticConfiguring = false
            switch result {
            case .success:
                self.refreshAutomaticStatus()
                if self.generation == setupGeneration { self.configure(enabled: true) }
            case .failure(let error):
                self.automaticStatus = (error as? GrokLauncher.Failure) == .concurrentChange
                    ? "Grok 配置被同时修改，已保留最新文件，请重试"
                    : "未改写 Grok 配置：文件不可写或格式无法安全识别"
            }
        }
    }
    func stop() {
        shared.stop()
        generation += 1; timer = nil; client?.cancel(); billingTask?.cancel(); scanTask?.cancel()
        billingTask = nil; scanTask = nil; refreshing = false
    }
    func refreshQuota() {
        guard enabled, billingTask == nil else { return }
        lastQuotaAttempt = Date()
        guard let executable = GrokBillingClient.executable(home: home) else {
            quota = nil; quotaFailed = true; quotaStatus = GrokBillingClient.Failure.missingCLI.title; return
        }
        refreshing = true
        quotaStatus = "正在查询官方额度…"
        let version = generation, home = home, worker = GrokBillingClient()
        client = worker
        billingTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<GrokQuotaSnapshot, Error> in
                Result { try worker.fetch(executable: executable, home: home) }
            }.value
            guard let self, self.enabled, self.generation == version else { return }
            self.refreshing = false; self.billingTask = nil; self.client = nil
            switch result {
            case .success(let quota): self.quota = quota; self.quotaFailed = false; self.quotaStatus = "官方额度已同步"
            case .failure(let error):
                self.quotaFailed = true
                let failure = error as? GrokBillingClient.Failure ?? .service
                // Authentication can change the account: never attach an older account's quota to it.
                if failure == .authentication || failure == .noQuota { self.quota = nil }
                self.quotaStatus = failure.title
            }
        }
    }
    func refreshActivity() {
        guard enabled, scanTask == nil else { return }
        let version = generation
        scanTask = Task { [weak self, reader] in
            let scan = await reader.scan()
            guard let self, self.enabled, self.generation == version else { return }
            self.scanTask = nil; self.consume(scan)
        }
    }
    func consume(_ scan: GrokSessionScan, now: Date = Date()) {
        guard enabled else { return }
        lastScan = scan
        shared.updateSessions(Dictionary(scan.sessions.filter { scan.registeredIDs.contains($0.id) }.map { ($0.id, $0.cwd) }, uniquingKeysWith: { _, last in last }))
        projectRows(scan, now: now)
    }
    func answer(_ request: GrokQuestionRequest, action: String = "answers", selections: [String: [String]], texts: [String: String]) async -> String {
        guard enabled, questions.contains(request) else { return "问题已失效，请在 Grok 原终端查看" }
        return await shared.submit(request, action: action, selections: selections, texts: texts)
    }
    private func projectRows(_ scan: GrokSessionScan, now: Date = Date()) {
        if usage?.days != scan.usage.days || usage?.complete != scan.usage.complete || usage?.sessionCount != scan.usage.sessionCount {
            usage = scan.usage
        }
        var next: [ActivitySessionSnapshot] = []
        for session in scan.sessions where session.caughtUp {
            let t = session.turn
            let question = questions.first { $0.sessionID == session.id && (t.promptID == nil || t.promptID == $0.turnID) }
            guard let prompt = question?.turnID ?? t.promptID, t.phase != .idle || question != nil else { continue }
            let id = "grok:" + session.id, key = id + ":" + prompt
            let previous = rows.first { $0.id == id && $0.turnID == prompt }
            let live = scan.liveIDs.contains(session.id)
            guard question != nil || (live && t.active) || previous?.phase.isActive == true || receipts[key] != nil else { continue }
            var phase: TaskPhase
            var end: SessionEndReason?
            switch t.phase {
            case .working: phase = live ? .working : .ended; end = live ? nil : .ended
            case .tool: phase = live ? .usingTool : .ended; end = live ? nil : .ended
            case .completed: phase = .completed; end = .completed
            case .failed: phase = .failed; end = .failed
            case .cancelled: phase = .ended; end = .cancelled
            default: phase = .ended; end = .ended
            }
            if question != nil { phase = .waitingApproval; end = nil }
            var row = ActivitySessionSnapshot(sessionID: id, turnID: prompt, projectID: "grok:" + session.cwd,
                projectName: URL(fileURLWithPath: session.cwd).lastPathComponent, title: session.title,
                phase: phase, actionText: t.text.isEmpty ? phase.title : t.text, updatedAt: end == nil ? t.updatedAt : previous?.endReason != nil ? previous!.updatedAt : t.active ? now : t.updatedAt,
                tokenUsage: .init(sessionID: id, turnID: prompt, total: t.tokens, isCompleted: end != nil),
                endReason: end, modelName: session.model, startedAt: t.startedAt, sessionTotalTokens: session.totalTokens,
                provider: "Grok CLI", suppressCompletion: !observedTurns.contains(key))
            if let question { row.waitReason = question.permission == nil ? .userInput : .approval; row.replyRequestIDs = [question.id]; row.actionText = question.permission == nil ? "请回答 Grok 的问题" : "请批准 Grok 的操作"; row.suppressCompletion = true }
            row.recentSteps = IslandStep.visibleSteps(from: t.steps.map { step in
                let state: IslandStep.State = step.status == "completed" ? .done : step.status == "failed" ? .failed
                    : end != nil ? .ended : .running
                return .init(id: step.id, title: step.title, state: state)
            })
            if phase.isActive { observedTurns.insert(key) }
            else if receipts[key] == nil { receipts[key] = row }
            if end == nil { next.append(row) }
        }
        for old in rows where old.phase.isActive && !next.contains(where: { $0.id == old.id }) {
            let key = old.id + ":" + (old.turnID ?? "")
            if receipts[key] == nil {
                var ended = old; ended.phase = .ended; ended.endReason = .ended; ended.updatedAt = now
                ended.suppressCompletion = true; ended.recentSteps = ended.recentSteps.map { $0.endingTask() }
                receipts[key] = ended
            }
        }
        receipts = receipts.filter { now.timeIntervalSince($0.value.updatedAt) < 60 }
        next += receipts.values.filter { receipt in !next.contains(where: { $0.id == receipt.id }) }
        next.sort { $0.id < $1.id }
        if observedTurns.count > 1024 { observedTurns = Set(next.map { $0.id + ":" + ($0.turnID ?? "") }) }
        if rows != next { rows = next; onRowsChanged?() }
    }
    deinit { shared.stop(); timer?.cancel(); client?.cancel(); billingTask?.cancel(); scanTask?.cancel() }
}
