import Foundation
import SQLite3

@main
enum ActivitySessionStateTests {
    static var failures = 0
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    static func main() throws {
        UserDefaults.standard.setVolatileDomain([CountStyle.preferenceKey: "western"], forName: UserDefaults.argumentDomain)
        expect(CodexActivityTokenUsageFormatter.string(for: 128_000) == "128K", "western forwarding")
        UserDefaults.standard.setVolatileDomain([CountStyle.preferenceKey: "chinese"], forName: UserDefaults.argumentDomain)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/activity-session-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lookupHome = root.appendingPathComponent("lookup")
        let lookupSessions = lookupHome.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: lookupSessions, withIntermediateDirectories: true)
        let indexed = lookupSessions.appendingPathComponent("indexed.jsonl")
        try Data(#"{"type":"session_meta","payload":{"id":"exact","source":"vscode"}}"#.utf8).write(to: indexed)
        var database: OpaquePointer?
        expect(sqlite3_open(lookupHome.appendingPathComponent("state_5.sqlite").path, &database) == SQLITE_OK, "create isolated thread lookup fixture")
        sqlite3_exec(database, "CREATE TABLE threads (id TEXT, rollout_path TEXT)", nil, nil, nil)
        func indexedPath(_ id: String, _ url: URL) {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(database, "INSERT INTO threads VALUES (?, ?)", -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            _ = url.path.withCString { sqlite3_bind_text(statement, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            _ = sqlite3_step(statement)
        }
        indexedPath("exact", indexed)
        indexedPath("wrong-id", indexed)
        indexedPath("outside", root.appendingPathComponent("outside.jsonl"))
        expect(SessionActivityService.preferredSessionFiles(sessionIDs: ["exact"], codexHome: lookupHome) == [indexed], "exact Hook identity discovers indexed rollout without directory refresh")
        expect(SessionActivityService.preferredSessionFiles(sessionIDs: ["unknown"], codexHome: lookupHome).isEmpty, "unknown Hook identity cannot invent a rollout")
        expect(SessionActivityService.preferredSessionFiles(sessionIDs: ["wrong-id"], codexHome: lookupHome).isEmpty, "mismatched rollout header cannot bind a Hook alias")
        expect(SessionActivityService.preferredSessionFiles(sessionIDs: ["outside"], codexHome: lookupHome).isEmpty, "indexed path cannot escape sessions root")
        sqlite3_close(database)
        let service = SessionActivityService()
        let now = Date()
        let compactWorking = ActivitySessionSnapshot(sessionID: "compact-live", turnID: "one", projectID: "p",
            projectName: "Project", title: "Task", phase: .usingTool, actionText: "运行测试", updatedAt: now, tokenUsage: nil)
        expect(compactWorking.compactTaskText == "工作中 · 运行测试", "compact text includes actual activity instead of a phase-only label")
        var compactThinking = compactWorking; compactThinking.phase = .working; compactThinking.actionText = "正在思考"
        expect(compactThinking.compactTaskText == "思考中 · Task", "duplicate phase falls back to the task title")
        expect(compactWorking.hidingDetails().compactTaskText == "工作中 · 任务内容已隐藏", "compact privacy cannot leak task or action")
        var compactDone = ActivitySessionSnapshot(sessionID: "compact-done", turnID: "done", projectID: "p",
            projectName: "Project", title: "Finished", phase: .completed, actionText: "已完成", updatedAt: now, tokenUsage: nil)
        let compactRows = [compactWorking, compactDone]
        expect(ActivitySessionSnapshot.compactFocus(rows: compactRows, selectedID: compactWorking.id, receipt: compactDone)?.id == compactDone.id,
               "new completion can temporarily lead compact display without changing list selection")
        expect(ActivitySessionSnapshot.compactFocus(rows: compactRows, selectedID: compactWorking.id, receipt: nil)?.id == compactWorking.id,
               "expired receipt restores running selection")
        var compactWaiting = compactWorking; compactWaiting.phase = .waitingApproval
        expect(ActivitySessionSnapshot.compactFocus(rows: [compactDone, compactWaiting], selectedID: compactDone.id, receipt: compactDone)?.phase == .waitingApproval,
               "pending confirmation takes priority over completion receipt")
        compactDone = ActivitySessionSnapshot(sessionID: "compact-done", turnID: "new", projectID: "p", projectName: "Project",
            title: "New turn", phase: .working, actionText: "思考中", updatedAt: now, tokenUsage: nil)
        expect(ActivitySessionSnapshot.compactFocus(rows: [compactWorking, compactDone], selectedID: compactWorking.id, receipt: compactRows[1])?.id == compactWorking.id,
               "receipt from a retired turn cannot replace compact focus")
        expect(ActivitySessionSnapshot.compactFocus(rows: [], selectedID: nil, receipt: nil) == nil, "empty compact state has no stale focus")
        var statusRow = ActivitySessionSnapshot(sessionID: "status", turnID: "turn", projectID: "project",
            projectName: "Project", title: "Task", phase: .working, actionText: "", updatedAt: now, tokenUsage: nil)
        for (phase, title) in [(TaskPhase.starting, "开始中"), (.working, "思考中"), (.usingTool, "工作中"),
                               (.waitingApproval, "待确认"), (.completed, "已完成"), (.ended, "已结束"), (.failed, "失败")] {
            statusRow.phase = phase
            expect(ActivitySessionSnapshot.statusSummary([statusRow]) == "1 \(title)", "footer follows \(phase.rawValue) transition")
        }
        statusRow.phase = .working
        var approvalRow = statusRow; approvalRow.phase = .waitingApproval
        expect(ActivitySessionSnapshot.statusSummary([statusRow, statusRow, approvalRow]) == "1 待确认 · 2 思考中",
               "mixed footer counts phases independently and prioritizes attention")
        statusRow.endReason = .cancelled
        expect(ActivitySessionSnapshot.statusSummary([statusRow]) == "1 已取消", "cancelled feedback remains distinct from success")
        expect(ActivitySessionSnapshot.statusSummary([]).isEmpty, "empty footer has no stale running count")
        let privateRow = statusRow.hidingDetails()
        expect(privateRow.title == "Codex 任务" && privateRow.projectName == "项目" && privateRow.actionText == "任务内容已隐藏",
               "privacy removes task, project and action from rendered data")
        expect(privateRow.tokenUsage == nil && privateRow.modelName == nil && privateRow.startedAt == nil && privateRow.tokenTitle == "— tokens",
               "privacy removes token and model metadata")
        expect(privateRow.id == statusRow.id && privateRow.turnID == statusRow.turnID && privateRow.statusTitle == statusRow.statusTitle,
               "privacy preserves identity and live status")
        expect(statusRow.title == "Task", "privacy projection does not mutate source evidence")
        func event(_ type: String, _ turn: String? = nil) -> [String: Any] {
            var payload: [String: Any] = ["type": type]
            if let turn { payload["turn_id"] = turn }
            return ["type": "event_msg", "payload": payload]
        }
        func fixture(_ name: String, _ records: [[String: Any]]) throws -> URL {
            let url = root.appendingPathComponent("\(name).jsonl")
            let lines = try records.enumerated().map { index, value -> Data in
                var value = value
                value["timestamp"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(index)))
                return try JSONSerialization.data(withJSONObject: value)
            }
            try lines.reduce(into: Data()) { $0.append($1); $0.append(0x0A) }.write(to: url)
            return url
        }

        func tokenCount(_ total: Any, last: Any) -> [String: Any] {
            ["type": "event_msg", "payload": ["type": "token_count", "info": [
                "total_token_usage": ["total_tokens": total, "cached_input_tokens": 999999, "reasoning_output_tokens": 9999],
                "last_token_usage": ["total_tokens": last]]]]
        }
        let publicMessage: [String: Any] = ["type": "response_item", "payload": ["type": "message", "role": "assistant",
            "channel": "commentary", "content": [["type": "output_text", "text": "紧凑态已经改成原项目的布局，正在验证当前动作。"]]]]
        let sessionUsageFile = try fixture("session-usage", [
            ["type": "session_meta", "payload": ["id": "usage-session", "cwd": "/Demo"]],
            event("task_started", "old"), tokenCount(88_400_000, last: 88_400_000), event("task_complete", "old"),
            event("task_started", "new"), tokenCount(95_300_000, last: 6_900_000), publicMessage,
            ["type": "response_item", "payload": ["type": "function_call", "call_id": "read", "name": "read", "arguments": "{\"title\":\"读取 MonitorStore.swift\"}"]],
            ["type": "response_item", "payload": ["type": "function_call_output", "call_id": "read", "output": "not retained"]],
            ["type": "response_item", "payload": ["type": "message", "role": "assistant", "channel": "analysis",
                "content": [["type": "output_text", "text": "private reasoning must not appear"]]]]
        ])
        let usageSnapshot = service.readSnapshot(from: sessionUsageFile)!
        expect(usageSnapshot.sessionTotalTokens == 95_300_000, "card count uses session cumulative total without adding cached or reasoning breakdowns")
        expect(usageSnapshot.turnTokenUsage?.total == 6_900_000, "turn-token evidence remains separately scoped")
        expect(usageSnapshot.latestAssistantSummary == "紧凑态已经改成原项目的布局，正在验证当前动作。", "public assistant progress survives later tool output and ignores private analysis")
        var display = ActivitySessionState()
        let usageProjects = ProjectActivityAggregator.projects(snapshots: [usageSnapshot],  now: now, catalog: .empty)
        display.update(projects: usageProjects, snapshots: [usageSnapshot],
                       usages: ["usage-session": usageSnapshot.turnTokenUsage!], now: now, completionHold: 3)
        expect(display.rows.first?.tokenTitle == "9,530万 tokens", "card formats the upstream session total instead of the 6.9M turn count")
        expect(display.rows.first?.actionText == usageSnapshot.latestAssistantSummary, "thinking card shows public progress instead of stale file-read output")
        expect(display.rows.first?.tokenUsage?.total == 6_900_000, "island display choice does not overwrite existing turn accounting")
        let runningFile = try fixture("public-running", [event("task_started", "tool"), publicMessage,
            ["type": "response_item", "payload": ["type": "function_call", "call_id": "tool", "name": "read", "arguments": "{\"title\":\"检查当前文件\"}"]]])
        let runningSnapshot = service.readSnapshot(from: runningFile)!
        let runningProjects = ProjectActivityAggregator.projects(snapshots: [runningSnapshot],  now: now, catalog: .empty)
        display.update(projects: runningProjects, snapshots: [runningSnapshot],  usages: [:], now: now, completionHold: 3)
        expect(display.rows.first?.phase == .usingTool && display.rows.first?.actionText == usageSnapshot.latestAssistantSummary && display.rows.first?.recentSteps.last?.title == "检查当前文件", "focus stage retains both latest assistant progress and current tool step")
        let nativeUsage: [String: Any] = ["thread_id": "thread", "turn_id": "turn",
            "thread_token_usage": ["total_tokens": 100000000], "turn_token_usage": ["total_tokens": 7000000], "usage": ["total_tokens": 1000]]
        expect(SessionActivityService.cumulativeTokens(type: "token_usage_record", payload: nativeUsage, sessionID: "thread") == 100000000,
               "native usage ledger reads thread total rather than turn or last-response usage")
        expect(SessionActivityService.cumulativeTokens(type: "token_usage_record", payload: nativeUsage, sessionID: "other") == nil,
               "native usage from another thread cannot contaminate the card")
        expect(SessionActivityService.cumulativeTokens(type: "event_msg", payload: ["type": "token_count", "info": ["total_token_usage": ["total_tokens": true]]], sessionID: "thread") == nil,
               "boolean token totals are rejected")
        expect(SessionActivityService.cumulativeTokens(type: "event_msg", payload: ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 10], "last_token_usage": ["total_tokens": 11]]], sessionID: "thread") == nil,
               "inconsistent cumulative counters are rejected")
        expect(CodexActivityTokenUsageFormatter.string(for: 128000) == "12.8万" && CodexActivityTokenUsageFormatter.string(for: 0) == "0",
               "upstream count formatting removes unnecessary trailing decimal and preserves zero")

        let unknownEnd = try fixture("tail", [event("task_complete", "outside-tail")])
        let nativeCall = try fixture("native-call", [event("task_started", "native"),
            ["type": "response_item", "payload": ["type": "function_call", "call_id": "native-1", "name": "mcp__cua_repl__js", "arguments": "{\"title\":\"查看任务卡片\",\"code\":\"sensitive content must not be retained\"}"]]])
        expect(service.readSnapshot(from: nativeCall)?.activities.first?.title == "查看任务卡片", "native MCP call uses its safe title")
        expect(service.readSnapshot(from: nativeCall)?.activities.first?.isRunning == true, "native MCP call is running")
        let nativeResult = try fixture("native-result", [event("task_started", "native"),
            ["type": "response_item", "payload": ["type": "function_call", "call_id": "native-1", "name": "mcp__cua_repl__js", "arguments": "{}"]],
            ["type": "response_item", "payload": ["type": "function_call_output", "call_id": "native-1", "output": "must not retain output"]]])
        expect(service.readSnapshot(from: nativeResult)?.activities.first?.isRunning == false, "native result closes exact tool call")
        var watcherReady = false
        var writeNotices = 0
        service.onChange = { writeNotices += 1 }
        service.observeChanges(at: [nativeCall]) { watcherReady = true }
        let watchDeadline = Date().addingTimeInterval(3)
        while !watcherReady && Date() < watchDeadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        expect(watcherReady, "read-only log observer attaches")
        let handle = try FileHandle(forWritingTo: nativeCall)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("\n\n".utf8)); try handle.close()
        while writeNotices == 0 && Date() < watchDeadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        expect(writeNotices > 0, "log append notifies without waiting for five-second reconciliation")
        expect(service.cachedSnapshot(for: nativeCall)?.activities.first?.isRunning == true, "write notification preserves session evidence")
        expect(service.readSnapshot(from: unknownEnd)?.turnID == "outside-tail",
               "terminal-only tail retains its explicit turn identity")

        let oldContext = try fixture("old-context", [
            event("task_started", "one"), event("task_complete", "one"),
            event("task_started", "two"),
            ["type": "turn_context", "payload": ["turn_id": "one", "cwd": "/old"]],
            event("task_complete", "one")
        ])
        let current = service.readSnapshot(from: oldContext)
        expect(current?.turnID == "two", "late old context cannot rewind the current turn")
        expect(current?.isActive == true, "late old completion cannot end the new turn")

        var tokenState = TurnTokenState()
        tokenState.consume(type: "event_msg", payload: ["type": "task_started", "turn_id": "one"])
        tokenState.consume(type: "event_msg", payload: ["type": "task_complete"])
        expect(tokenState.isCompleted, "legacy completion without turn id closes the observed turn")
        tokenState.consume(type: "event_msg", payload: ["type": "task_started", "turn_id": "two"])
        tokenState.consume(type: "event_msg", payload: ["type": "task_complete", "turn_id": "two"])
        tokenState.consume(type: "event_msg", payload: ["type": "turn_aborted", "turn_id": "one"])
        expect(tokenState.isCompleted, "foreign cancellation cannot overwrite completion")

        let legacy = try fixture("legacy", [event("task_started"),
            ["type": "turn_context", "payload": ["turn_id": "legacy"]]])
        let legacySnapshot = service.cachedSnapshot(for: legacy, now: now)
        expect(legacySnapshot?.evidence?.lifecycleState == true, "legacy start survives its following context")
        expect(service.cachedSnapshot(for: legacy, now: now.addingTimeInterval(602))?.isActive == false,
               "unchanged cached quiet turn expires after its grace period")
        _ = try fixture("legacy", [event("task_started", "legacy"), event("task_complete", "legacy")])
        expect(service.cachedSnapshot(for: legacy)?.evidence?.endReason == .completed,
               "same URL observes changed file metadata and invalidates parsed cache")
        let unknown = try fixture("unknown", [["type": "turn_context", "payload": ["turn_id": "unknown"]]])
        expect(service.cachedSnapshot(for: unknown, now: now)?.isActive == true, "unknown boundary uses recent file discovery")
        expect(service.cachedSnapshot(for: unknown, now: now.addingTimeInterval(16))?.isActive == false,
               "unchanged discovery cache expires after fifteen seconds")
        let running = try fixture("running", [event("task_started", "running"),
            ["type": "response_item", "payload": ["type": "custom_tool_call", "call_id": "tool", "name": "exec", "input": "swift test"]]])
        expect(service.cachedSnapshot(for: running, now: now.addingTimeInterval(7199))?.isActive == true,
               "cached running tool retains its longer grace")
        expect(service.cachedSnapshot(for: running, now: now.addingTimeInterval(7202))?.isActive == false,
               "cached running tool cannot remain active forever")

        let cancelled = try fixture("cancelled", [event("task_started", "cancelled"), event("turn_aborted", "cancelled")])
        expect(service.readSnapshot(from: cancelled)?.evidence?.endReason == .cancelled,
               "cancellation has explicit evidence distinct from success")
        let terminal = service.readSnapshot(from: unknownEnd)
        expect(terminal?.evidence?.endReason == .completed, "terminal-only tail has completion evidence")
        expect(terminal?.turnTokenUsage?.total == nil, "terminal-only tail cannot fabricate token totals")

        let cleanTurn = try fixture("clean-turn", [event("task_started", "one"),
            ["type": "response_item", "payload": ["type": "custom_tool_call", "call_id": "old-tool", "name": "exec", "input": "old"]],
            event("task_started", "two")])
        expect(service.readSnapshot(from: cleanTurn)?.activities.isEmpty == true,
               "old running tool does not leak into a new turn")
        let secondLegacy = try fixture("second-legacy", [event("task_started", "one"), event("task_complete", "one"),
            event("task_started"), event("task_complete", "one"),
            ["type": "turn_context", "payload": ["turn_id": "two"]]])
        let secondLegacySnapshot = service.readSnapshot(from: secondLegacy)
        expect(secondLegacySnapshot?.turnID == "two" && secondLegacySnapshot?.evidence?.lifecycleState == true,
               "subsequent legacy start opens its new context despite late old completion")
        expect(secondLegacySnapshot?.evidence?.endReason == nil,
               "new legacy turn does not inherit old terminal evidence")

        let large = root.appendingPathComponent("large.jsonl")
        var largeData = Data(repeating: 0x20, count: 8 * 1_024 * 1_024 + 100)
        largeData.append(0x0A)
        largeData.append(try Data(contentsOf: unknownEnd))
        try largeData.write(to: large)
        expect(service.readSnapshot(from: large)?.turnID == "outside-tail", "bounded large tail preserves terminal identity")

        func snapshot(_ id: String, turn: String = "turn", path: String = "/Demo", active: Bool = true,
                      reason: SessionEndReason? = nil, offset: Double = 0, items: [SessionActivityItem]? = nil) -> LocalSessionSnapshot {
            LocalSessionSnapshot(sessionID: id, turnID: turn, cwd: path, model: "test", isActive: active,
                updatedAt: now.addingTimeInterval(offset),
                activities: items ?? [.init(id: id + "-activity", kind: .command, title: "Action " + id,
                                   isRunning: active, updatedAt: now.addingTimeInterval(offset))],
                evidence: .init(lifecycleState: active, hasRunningTool: active, fileModifiedAt: now,
                                endReason: reason, endedAt: reason == nil ? nil : now))
        }
        func projects(_ snapshots: [LocalSessionSnapshot]) -> [ActiveProjectState] {
            ProjectActivityAggregator.projects(snapshots: snapshots,  now: now,
                catalog: .empty, threadNames: ["a": "Session A", "b": "Session B"])
        }
        var stepState = ActivitySessionState()
        let stepItems: [SessionActivityItem] = (0..<5).map { index in
            .init(id: "step-\(index)", kind: index == 4 ? .progress : .command,
                  title: "Step \(index)", isRunning: index == 3, updatedAt: now.addingTimeInterval(Double(index)))
        }
        var stepSource = snapshot("steps", items: stepItems)
        stepState.update(projects: projects([stepSource]), snapshots: [stepSource], usages: [:], now: now, completionHold: 8)
        expect(stepState.rows.first?.recentSteps.map(\.id) == ["step-1", "step-2", "step-3"], "steps exclude progress and take last three in chronological order")
        expect(stepState.rows.first?.recentSteps.map(\.state) == [.done, .done, .running], "steps retain running and done states")
        stepSource = snapshot("steps", items: [])
        stepSource.nativePhase = .waitingApproval
        stepState.update(projects: projects([stepSource]), snapshots: [stepSource], usages: [:], now: now, completionHold: 8)
        expect(stepState.rows.first?.recentSteps.count == 3 && stepState.rows.first?.recentSteps.last?.state == .waiting, "same-turn sparse wait keeps steps and marks last waiting")
        expect(stepState.rows.first?.hidingDetails().recentSteps.isEmpty == true, "privacy removes step titles")
        let stepEnd = snapshot("steps", active: false, reason: .completed)
        stepState.update(projects: [], snapshots: [stepEnd], usages: [:], now: now, completionHold: 8)
        expect(stepState.rows.first?.recentSteps.map(\.state) == [.done, .done, .done], "receipt preserves steps as done")
        stepState.update(projects: [], snapshots: [stepEnd], usages: [:], now: now.addingTimeInterval(8), completionHold: 8)
        expect(stepState.rows.first?.isRetainedReceipt == true, "receipt boundary marks retained row")
        expect(stepState.rows.first?.hidingDetails().isRetainedReceipt == true, "privacy preserves lifecycle retention flag")
        let nextSteps = snapshot("steps", turn: "next", items: [])
        stepState.update(projects: projects([nextSteps]), snapshots: [nextSteps], usages: [:], now: now, completionHold: 8)
        expect(stepState.rows.first?.turnID == "next" && stepState.rows.first?.recentSteps.isEmpty == true && stepState.rows.first?.isRetainedReceipt == false, "new turn replaces retained receipt and clears steps")

        var state = ActivitySessionState()
        var retained = ActivitySessionState()
        var rich = snapshot("a")
        rich.startedAt = now.addingTimeInterval(-180)
        rich.reasoningEffort = "medium"
        rich.sessionTotalTokens = 122_100_000
        retained.update(projects: projects([rich]), snapshots: [rich],  usages: [:], now: now, completionHold: 8)
        let sparse = snapshot("a")
        retained.update(projects: ProjectActivityAggregator.projects(snapshots: [sparse],  now: now, catalog: .empty),
            snapshots: [sparse],  usages: [:], now: now, completionHold: 8)
        expect(retained.rows.first?.title == "Session A", "verified sparse refresh retains known thread title")
        expect(retained.rows.first?.reasoningEffort == "medium" && retained.rows.first?.durationTitle(at: now) == "3m",
            "same-turn sparse refresh retains effort and start time")
        expect(retained.rows.first?.sessionTotalTokens == 122_100_000, "sparse refresh retains cumulative tokens")
        var final = snapshot("a", active: false, reason: .completed)
        final.reasoningEffort = "high"
        final.sessionTotalTokens = 123_000_000
        retained.update(projects: [], snapshots: [final],  usages: [:], now: now.addingTimeInterval(2), completionHold: 8,
            threadNames: ["a": "Resolved title"])
        expect(retained.rows.first?.title == "Resolved title" && retained.rows.first?.reasoningEffort == "high",
            "terminal snapshot and catalog hydrate completed metadata")
        expect(retained.rows.first?.actionText == "已完成", "completion does not invent redundant operation detail")
        expect(retained.rows.first?.durationTitle(at: now.addingTimeInterval(60)) == "3m", "receipt duration freezes at terminal evidence")
        expect(retained.rows.first?.sessionTotalTokens == 123_000_000, "late terminal total replaces earlier cumulative value")
        let newTurn = snapshot("a", turn: "new")
        retained.update(projects: projects([newTurn]), snapshots: [newTurn],  usages: [:], now: now, completionHold: 8)
        expect(retained.rows.first?.startedAt == nil && retained.rows.first?.reasoningEffort == nil,
            "new turn cannot inherit previous turn timing or effort")
        expect(retained.rows.first?.sessionTotalTokens == 123_000_000, "session total survives turn boundary")
        retained.update(projects: projects([snapshot("b")]), snapshots: [snapshot("b")],  usages: [:], now: now.addingTimeInterval(20), completionHold: 8)
        expect(retained.rows.first?.sessionTotalTokens == nil, "different session cannot inherit metadata")
        let a = snapshot("a"), b = snapshot("b", offset: 1), c = snapshot("c", path: "/Other")
        let usages: [String: TurnTokenUsage] = [
            "a": .init(sessionID: "a", turnID: "turn", total: 100),
            "b": .init(sessionID: "b", turnID: "turn", total: 200)
        ]
        func update(_ locals: [LocalSessionSnapshot],
                    tokens: [String: TurnTokenUsage] = [:], offset: Double = 0) {
            state.update(projects: projects(locals), snapshots: locals,
                         usages: tokens, now: now.addingTimeInterval(offset), completionHold: 8)
        }
        update([a, b, c], tokens: usages)
        expect(state.rows.count == 3, "same-project sessions are independent rows")
        expect(Set(state.rows.map(\.projectID)).count == 2, "project count is independent from session count")
        expect(state.rows.first(where: { $0.id == "a" })?.title == "Session A", "row title belongs to its own session")
        expect(state.rows.first(where: { $0.id == "a" })?.actionText == "Action a", "action is not borrowed from project representative")
        expect(state.rows.first(where: { $0.id == "a" })?.tokenUsage?.total == 100, "first session keeps its own tokens")
        expect(state.rows.first(where: { $0.id == "b" })?.tokenUsage?.total == 200, "second session keeps its own tokens")
        let order = state.rows.map(\.id)
        update([snapshot("a", offset: 5), b, c], tokens: usages, offset: 5)
        expect(state.rows.map(\.id) == order, "activity timestamps do not reorder resident rows")
        var waitingC = c; waitingC.nativePhase = .waitingApproval
        update([a, b, waitingC], offset: 6)
        expect(state.rows.first?.id == "c", "approval is promoted to the attention area")
        update([a, b, c], offset: 6)
        expect(state.rows.map(\.id) == order, "resolved approval returns to stable resident order")

        let invalidUsage = TurnTokenUsage(sessionID: "b", turnID: "turn", total: 999)
        expect(ActivitySessionSnapshot.matchingUsage(["a": invalidUsage], sessionID: "a", turnID: "turn") == nil,
               "mismatched embedded session identity is rejected")
        expect(ActivitySessionSnapshot.matchingUsage(usages, sessionID: "a", turnID: "next") == nil,
               "tokens never cross turn boundaries")
        expect(ActivitySessionSnapshot.matchingUsage(usages, sessionID: "a", turnID: nil) == nil,
               "unknown turn does not borrow measured tokens")
        expect(ActivitySessionSnapshot.matchingUsage(["a": .init(sessionID: "a", turnID: "", total: 100)],
               sessionID: "a", turnID: "") == nil, "empty turn identity cannot validate token attribution")

        update([b], offset: 7)
        expect(state.rows.count == 1 && state.rows[0].id == "b", "vanishing sources do not produce success receipts")
        let bCancelled = snapshot("b", active: false, reason: .cancelled)
        update([bCancelled], offset: 8)
        expect(state.rows.first?.endReason == .cancelled, "observed cancellation produces a cancelled receipt")
        expect(state.rows.first?.phase == .ended, "cancelled receipt is never green completed")
        update([bCancelled], offset: 15)
        expect(state.rows.count == 1, "terminal receipt remains inside bounded hold")
        update([bCancelled], offset: 16)
        expect(state.rows.first?.isRetainedReceipt == true, "receipt deadline expires without removing retained result")
        update([bCancelled], offset: 59)
        expect(state.rows.first?.isRetainedReceipt == true, "retained result survives until just before one minute")
        update([bCancelled], offset: 60)
        expect(state.rows.isEmpty, "terminal row expires 60 seconds after its end without extension")

        update([a], tokens: usages, offset: 20)
        let aComplete = snapshot("a", active: false, reason: .completed)
        update([aComplete], tokens: ["a": .init(sessionID: "a", turnID: "turn", total: 120, isCompleted: true)], offset: 21)
        expect(state.rows.first?.phase == .completed, "matching explicit terminal proves completion")
        expect(state.rows.first?.tokenUsage?.total == 120, "late final tokens update the completed turn")
        update([snapshot("a", turn: "next", offset: 22)], tokens: usages, offset: 22)
        expect(state.rows.first?.turnID == "next" && state.rows.first?.phase.isActive == true,
               "new local turn supersedes the completion receipt")
        expect(state.rows.first?.tokenUsage == nil, "new turn does not inherit old tokens")
        update([snapshot("a", turn: "next", active: false, reason: .completed, offset: 23)],
               offset: 23)
        expect(state.rows.first?.turnID == "next" && state.rows.first?.phase == .completed,
               "current-turn terminal evidence creates a completion receipt")
        update([snapshot("a", turn: "third", offset: 24)], offset: 24)
        update([snapshot("a", turn: "third", active: false, reason: .completed, offset: 25)], offset: 25)
        expect(state.rows.first?.phase == .completed, "local terminal closes the same turn")

        var retainedSignal = compactRows[1]
        retainedSignal.endReason = .completed
        retainedSignal.isRetainedReceipt = true
        var observedSignal = retainedSignal; observedSignal.phase = .working
        expect(ActivitySessionSnapshot.newlyCompleted(in: [retainedSignal], previous: [observedSignal]) == nil,
               "retained result cannot trigger confetti or recreate compact receipt")
        expect(!retainedSignal.isFreshReceipt, "retained result cannot trigger activityEnded or extend popup hold")
        expect(ActivitySessionSnapshot.newAttention(in: [retainedSignal], previous: []) == nil,
               "retained result never steals attention")
        var attention = compactWorking; attention.phase = .waitingApproval; attention.replyRequestIDs = ["one"]
        expect(ActivitySessionSnapshot.newAttention(in: [attention], previous: [compactWorking])?.id == attention.id,
               "new request steals focus once")
        expect(ActivitySessionSnapshot.newAttention(in: [attention], previous: [attention]) == nil,
               "same pending request does not steal manual selection")
        var nextAttention = attention; nextAttention.replyRequestIDs = ["two"]
        expect(ActivitySessionSnapshot.newAttention(in: [nextAttention], previous: [attention]) != nil,
               "new request identity can reclaim focus in same turn")

        var focusA = compactRows[1]
        focusA.endReason = .completed
        let focusB = compactWorking
        let freshFocusRows = [focusA, focusB]
        expect(ActivitySessionSnapshot.autoFocus(rows: freshFocusRows, previous: freshFocusRows,
            currentFocusID: focusA.id, manualFocusID: nil, now: now.addingTimeInterval(2.9))?.id == focusA.id,
            "A keeps focus at 2.9 seconds after completion")
        expect(ActivitySessionSnapshot.autoFocus(rows: freshFocusRows, previous: freshFocusRows,
            currentFocusID: focusA.id, manualFocusID: nil, now: now.addingTimeInterval(3))?.id == focusB.id,
            "A hands focus to B at exactly three seconds while receipt remains fresh")
        expect(focusA.isFreshReceipt, "focus handoff does not expire the receipt")
        expect(ActivitySessionSnapshot.autoFocus(rows: [focusA], previous: freshFocusRows,
            currentFocusID: focusA.id, manualFocusID: nil, now: now.addingTimeInterval(3)) == nil,
            "three-second deadline without live rows leaves terminal handling unchanged")
        focusA.isRetainedReceipt = true
        let retainedFocusRows = [focusA, focusB]
        expect(ActivitySessionSnapshot.autoFocus(rows: retainedFocusRows, previous: freshFocusRows,
            currentFocusID: focusA.id, manualFocusID: nil, now: now.addingTimeInterval(3))?.id == focusB.id,
            "A retention refresh transfers focus to running B")
        expect(ActivitySessionSnapshot.newlyCompleted(in: retainedFocusRows, previous: freshFocusRows) == nil,
            "focus transfer at retention cannot replay completion signals")
        expect(ActivitySessionSnapshot.autoFocus(rows: retainedFocusRows, previous: retainedFocusRows,
            currentFocusID: focusB.id, manualFocusID: focusA.id, now: now.addingTimeInterval(3))?.id == focusA.id,
            "manual completed A selection remains during expansion")
        expect(ActivitySessionSnapshot.autoFocus(rows: retainedFocusRows, previous: retainedFocusRows,
            currentFocusID: focusA.id, manualFocusID: nil, now: now.addingTimeInterval(3))?.id == focusB.id,
            "clearing manual selection on collapse returns to B")
        let otherLive = ActivitySessionSnapshot(sessionID: "other-live", turnID: "turn", projectID: "p",
            projectName: "P", title: "Other", phase: .working, actionText: "", updatedAt: now, tokenUsage: nil)
        for reason: CodexActivityWaitReason? in [nil, .userInput] {
            var pendingB = focusB
            pendingB.phase = .waitingApproval; pendingB.waitReason = reason
            pendingB.replyRequestIDs = ["new-request"]
            let pendingRows = [focusA, pendingB]
            expect(ActivitySessionSnapshot.autoFocus(rows: pendingRows, previous: retainedFocusRows,
                currentFocusID: focusA.id, manualFocusID: focusA.id, now: now.addingTimeInterval(3))?.id == pendingB.id,
                "new approval or reply preempts even manual A")
            expect(ActivitySessionSnapshot.autoFocus(rows: pendingRows, previous: pendingRows,
                currentFocusID: pendingB.id, manualFocusID: nil, now: now.addingTimeInterval(3))?.id == pendingB.id,
                "preempting request keeps focus after manual choice is cleared")
            expect(ActivitySessionSnapshot.autoFocus(rows: pendingRows, previous: pendingRows,
                currentFocusID: focusA.id, manualFocusID: focusA.id, now: now.addingTimeInterval(3))?.id == focusA.id,
                "user can manually select A after request has already appeared")
            expect(ActivitySessionSnapshot.autoFocus(rows: [otherLive, focusA, pendingB],
                previous: pendingRows, currentFocusID: nil, manualFocusID: nil, now: now.addingTimeInterval(3))?.id == pendingB.id,
                "fallback prefers a pending live row")
        }
        expect(ActivitySessionSnapshot.autoFocus(rows: retainedFocusRows, previous: retainedFocusRows,
            currentFocusID: focusB.id, manualFocusID: nil, now: now.addingTimeInterval(3))?.id == focusB.id,
            "active current focus stays selected")
        expect(ActivitySessionSnapshot.autoFocus(rows: [focusB], previous: retainedFocusRows,
            currentFocusID: focusA.id, manualFocusID: focusA.id, now: now.addingTimeInterval(3))?.id == focusB.id,
            "missing manual row falls back to live session")
        expect(ActivitySessionSnapshot.autoFocus(rows: [focusA], previous: retainedFocusRows,
            currentFocusID: focusA.id, manualFocusID: focusA.id, now: now.addingTimeInterval(3)) == nil,
            "terminal-only rows delegate to existing controller branches")
        expect(ActivitySessionSnapshot.autoFocus(rows: [], previous: retainedFocusRows,
            currentFocusID: focusA.id, manualFocusID: focusA.id, now: now.addingTimeInterval(3)) == nil,
            "empty rows have no automatic live focus")

        var cold = ActivitySessionState()
        cold.update(projects: [], snapshots: [aComplete],  usages: usages, now: now, completionHold: 8)
        expect(cold.rows.isEmpty, "cold startup never replays historic completion")
        let abortedLocal = snapshot("a", active: false, reason: .cancelled)
        expect(projects([abortedLocal]).isEmpty, "cancelled local turns never become active cards")
        try FileManager.default.removeItem(at: unknown)
        expect(service.cachedSnapshot(for: unknown) == nil, "deleted source cannot leave its cached session active")

        expect(projects([]).isEmpty, "no local or native execution creates no card")
        var internalSnapshot = a; internalSnapshot.sessionKind = .internalTask
        expect(projects([internalSnapshot]).isEmpty, "internal sessions never create a user card")
        var finishedTokens = ActivitySessionSnapshot(sessionID: "a", turnID: "turn", projectID: "p", projectName: "P",
            title: "T", phase: .completed, actionText: "已完成", updatedAt: now,
            tokenUsage: .init(sessionID: "a", turnID: "turn", total: 6_900_000), sessionTotalTokens: 122_100_000)
        expect(finishedTokens.displayedTokenTitle == "本轮 690万 tokens · 累计 1.22亿 tokens", "completed card distinguishes turn consumption and session total")
        finishedTokens.tokenUsage = .init(sessionID: "a", turnID: "old", total: 100)
        expect(finishedTokens.displayedTokenTitle.hasPrefix("本轮 — tokens"), "previous turn tokens never appear as current completion consumption")
        finishedTokens.tokenUsage = .init(sessionID: "foreign", turnID: "turn", total: 100)
        expect(finishedTokens.displayedTokenTitle.hasPrefix("本轮 — tokens"), "foreign session tokens cannot appear in completion")
        expect(finishedTokens.hidingDetails().displayedTokenTitle == "— tokens", "privacy hides both token values")
        finishedTokens.phase = .working
        expect(finishedTokens.displayedTokenTitle == "1.22亿 tokens", "running card keeps the established cumulative display")
        let settled = snapshot("a", active: false, reason: .completed)
        expect(projects([settled]).isEmpty, "settled local turns never create active cards")
        var nativeRunning = a; nativeRunning.nativePhase = .working
        expect(projects([nativeRunning]).first?.task.phase == .working, "native phase is authoritative over tool detail")
        var vanished = ActivitySessionState()
        vanished.update(projects: projects([a]), snapshots: [a], usages: [:], now: now, completionHold: 8)
        vanished.update(projects: [], snapshots: [], usages: [:], now: now, completionHold: 8)
        expect(vanished.rows.isEmpty, "vanished sources do not leave a running card")

        print("Activity session state: \(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
