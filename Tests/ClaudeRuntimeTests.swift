import AppKit
import Foundation

@main enum ClaudeRuntimeTests {
    @MainActor static func main() async throws {
        activityStepLedgerRegression()
        try await activityStepsRegression()
        if CommandLine.arguments.contains("--steps-only") { return }
        try await liveRegistryRecoveryRegression()
        if CommandLine.arguments.contains("--registry-only") { return }
        try await startupUsageRegression()
        try await fallbackRegression()
        quietTurnRegression()
        if CommandLine.arguments.contains("--fallback-only") { return }
        try await IslandApprovalTests.run()
        let root = URL(fileURLWithPath: "/tmp/cpulse-runtime-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "test.claude." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let helper = URL(fileURLWithPath: CommandLine.arguments[1])
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("bridge.sock"), authenticationToken: "runtime-fixture",
            configurationDirectory: root.appendingPathComponent("config"), supportDirectory: root.appendingPathComponent("support"), helperURL: helper)
        let runtime = ClaudeCodeRuntime(defaults: defaults, installer: installer)
        runtime.start()
        assert(!FileManager.default.fileExists(atPath: installer.settingsURL.path), "disabled start must not write settings")
        try FileManager.default.createDirectory(at: installer.configurationDirectory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: installer.settingsURL)
        runtime.configure(enabled: true, approvals: true, statusLine: true)
        try await wait { !runtime.configuring }
        assert(!runtime.enabled && runtime.error != nil)
        try Data("{}".utf8).write(to: installer.settingsURL)
        runtime.retry()
        try await wait { !runtime.configuring }
        assert(runtime.enabled && runtime.error == nil)
        _ = try await Task.detached { try helperRun(installer, event: "statusLine") }.value
        try await wait { runtime.limits != nil }
        let captured = runtime.limits!
        runtime.tick(now: captured.capturedAt.addingTimeInterval(301))
        assert(runtime.limits == captured, "tick retains stale quota in memory")
        try await send(installer, event: "SessionEnd")
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(runtime.limits == captured, "idle SessionEnd retains quota")
        runtime.configure(enabled: true, approvals: true, statusLine: false)
        assert(runtime.limits == nil, "reconfiguration immediately clears quota")
        try await wait { !runtime.configuring }
        assert(!runtime.statusLineEnabled && runtime.limits == nil, "statusLine off clears quota")
        runtime.configure(enabled: true, approvals: true, statusLine: true)
        try await wait { !runtime.configuring }
        _ = try await Task.detached { try helperRun(installer, event: "statusLine") }.value
        try await wait { runtime.limits != nil }
        _ = try await Task.detached { try helperRun(installer, event: "emptyStatusLine") }.value
        try await wait { runtime.limits == nil }
        _ = try await Task.detached { try helperRun(installer, event: "statusLine") }.value
        try await wait { runtime.limits != nil }
        try await send(installer, event: "SessionStart")
        assert(runtime.rows.isEmpty, "SessionStart alone is not an active task")
        try await send(installer, event: "SessionEnd")
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(runtime.rows.isEmpty, "closing an idle session creates no task receipt")
        try await send(installer, event: "UserPromptSubmit")
        try await wait { runtime.rows.first?.phase == .working }
        let firstTurn = runtime.rows.first!.turnID
        _ = try await Task.detached { try helperRun(installer, event: "statusLine", fields: ["fast_mode": true]) }.value
        try await wait { runtime.rows.first?.fastMode == true }
        _ = try await Task.detached { try helperRun(installer, event: "statusLine", fields: ["session_id": "other", "fast_mode": false]) }.value
        assert(runtime.rows.first?.fastMode == true, "another session cannot overwrite Fast mode")
        _ = try await Task.detached { try helperRun(installer, event: "statusLine", fields: ["fast_mode": false]) }.value
        try await wait { runtime.rows.first?.fastMode == false }
        _ = try await Task.detached { try helperRun(installer, event: "statusLine", fields: ["fast_mode": "true"]) }.value
        try await wait { runtime.rows.first?.fastMode == nil }
        _ = try await Task.detached { try helperRun(installer, event: "statusLine", fields: ["fast_mode": 1]) }.value
        assert(runtime.rows.first?.fastMode == nil, "numeric Fast mode is not a boolean")
        try await send(installer, event: "PreToolUse")
        try await wait { runtime.rows.first?.phase == .usingTool }
        let pending = Task.detached { try helperRun(installer, event: "PermissionRequest") }
        try await wait { runtime.requests.count == 1 }
        assert(runtime.rows.first?.phase == .waitingApproval)
        runtime.respond(runtime.requests[0].id, choice: .deny)
        let answer = try await pending.value
        assert(String(decoding: answer, as: UTF8.self).contains("deny"))
        assert(runtime.requests.isEmpty)
        try await send(installer, event: "PostToolUse")
        let questions: [String: Any] = ["questions": [
            ["question": "选择组件？", "options": [["label": "A", "description": "说明 A"], ["label": "B"]], "multiSelect": true],
            ["question": "选择方案？", "options": [["label": "C"], ["label": "D"]]]
        ], "preserved": "original"]
        let questionTask = Task.detached { try helperRun(installer, event: "PreToolUse", fields: ["tool_name": "AskUserQuestion", "tool_input": questions]) }
        try await wait { runtime.requests.count == 1 }
        let questionID = runtime.requests[0].id
        assert(runtime.rows.first?.waitReason == .userInput)
        assert(runtime.requests[0].questions[0].descriptions["A"] == "说明 A")
        let draft = IslandAnswerDraft()
        draft.toggle("B", for: "选择组件？", orderedOptions: ["A", "B"])
        draft.toggle("A", for: "选择组件？", orderedOptions: ["A", "B"])
        assert(draft.answers["选择组件？"] == "A, B", "multi-select uses original option order")
        draft.toggle("A", for: "选择组件？", orderedOptions: ["A", "B"])
        assert(draft.answers["选择组件？"] == "B", "checkbox deselects")
        draft.toggle("A", for: "选择组件？", orderedOptions: ["A", "B"])
        runtime.respond(questionID, choice: .once, answers: draft.answers)
        assert(runtime.requests.count == 1, "partial answers cannot submit")
        draft.type(" 自定义方案 ", for: "选择方案？")
        runtime.respond(questionID, choice: .once, answers: draft.answers)
        let questionOutput = try JSONSerialization.jsonObject(with: await questionTask.value) as! [String: Any]
        let hookOutput = questionOutput["hookSpecificOutput"] as! [String: Any]
        assert(hookOutput["hookEventName"] as? String == "PreToolUse")
        assert(hookOutput["permissionDecision"] as? String == "allow")
        let updated = hookOutput["updatedInput"] as! [String: Any]
        assert(updated["answers"] as? [String: String] == ["选择组件？": "A, B", "选择方案？": "自定义方案"])
        assert(updated["preserved"] as? String == "original")
        assert(NSDictionary(dictionary: (updated["questions"] as! [[String: Any]])[0]).isEqual(to: (questions["questions"] as! [[String: Any]])[0]))
        runtime.respond(questionID, choice: .once, answers: draft.answers)
        assert(runtime.requests.isEmpty, "duplicate submission has no pending request")
        draft.type("其他", for: "选择组件？")
        assert(draft.selections["选择组件？"] == nil && draft.answers["选择组件？"] == "其他", "custom answer clears checkboxes")
        draft.toggle("A", for: "选择组件？", orderedOptions: ["A", "B"])
        assert(draft.texts["选择组件？"] == nil && draft.answers["选择组件？"] == "A", "checkbox clears custom answer")
        try await send(installer, event: "PostToolUse")
        let fallbackQuestion = Task.detached { try helperRun(installer, event: "PreToolUse", fields: ["tool_name": "AskUserQuestion", "tool_input": questions]) }
        try await wait { runtime.requests.count == 1 }
        runtime.tick(now: runtime.requests[0].deadline)
        let fallbackOutput = try await fallbackQuestion.value
        assert(fallbackOutput.isEmpty && runtime.requests.isEmpty, "expired pretool question returns to Claude without an answer")
        let deniedQuestion = Task.detached { try helperRun(installer, event: "PreToolUse", fields: ["tool_name": "AskUserQuestion", "tool_input": questions]) }
        try await wait { runtime.requests.count == 1 }
        runtime.respond(runtime.requests[0].id, choice: .deny)
        let deniedOutput = try JSONSerialization.jsonObject(with: await deniedQuestion.value) as! [String: Any]
        assert((deniedOutput["hookSpecificOutput"] as? [String: Any])?["permissionDecision"] as? String == "deny")
        try await send(installer, event: "PostToolUse")
        try await send(installer, event: "Stop")
        try await wait { runtime.rows.first?.phase == .completed }
        assert(runtime.rows.first?.provider == "Claude Code")
        try await send(installer, event: "SessionEnd")
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(runtime.rows.first?.phase == .completed, "SessionEnd preserves observed completion")
        assert(runtime.limits != nil, "terminal SessionEnd retains quota")
        let endedAt = runtime.rows.first!.updatedAt
        runtime.tick(now: endedAt.addingTimeInterval(14))
        assert(runtime.rows.first?.isRetainedReceipt == false, "Claude receipt stays fresh before 15 seconds")
        runtime.tick(now: endedAt.addingTimeInterval(15))
        assert(runtime.rows.first?.isRetainedReceipt == true, "Claude receipt hold remains 15 seconds while list retains result")
        runtime.tick(now: endedAt.addingTimeInterval(59))
        assert(runtime.rows.first?.phase == .completed, "Claude result remains for one minute")
        runtime.tick(now: endedAt.addingTimeInterval(60))
        assert(runtime.rows.isEmpty, "Claude result expires at retention boundary")
        try await send(installer, event: "UserPromptSubmit")
        try await wait { runtime.rows.first?.phase == .working }
        assert(runtime.rows.first?.turnID != firstTurn, "turns stay distinct")
        assert(runtime.rows.first?.fastMode == nil, "new turn does not inherit Fast mode")
        let expired = Task.detached { try helperRun(installer, event: "PermissionRequest") }
        try await wait { runtime.requests.count == 1 }
        let deadline = runtime.requests[0].deadline
        runtime.tick(now: deadline.addingTimeInterval(-0.01))
        assert(runtime.requests.count == 1, "request remains before deadline")
        runtime.tick(now: deadline)
        assert(runtime.requests.isEmpty, "120 seconds revokes all buttons")
        assert(runtime.rows.first?.actionText == "已交回 Claude Code 终端")
        let expiredOutput = try await expired.value
        assert(expiredOutput.isEmpty, "deadline returns to terminal without decision")
        let released = Task.detached { try helperRun(installer, event: "PermissionRequest") }
        try await wait { runtime.requests.count == 1 }
        runtime.configure(enabled: false, approvals: false, statusLine: false)
        let releasedOutput = try await released.value
        assert(releasedOutput.isEmpty, "disable releases pending helper without a decision")
        try await wait { !runtime.configuring }
        assert(!runtime.enabled && runtime.rows.isEmpty && runtime.requests.isEmpty && runtime.limits == nil)
        assert(!installer.state().hasOwnedHooks)
        runtime.stop()
        print("Claude runtime: disabled/start/tool/permission/deny/completion/new turn/disable/quota retention/replace/statusLine off passed")
    }
    @MainActor static func startupUsageRegression() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/perf-startup-round2/runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "test.claude.startup." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claude.enabled")
        // AF_UNIX paths have a small byte limit; keep only the socket in /tmp.
        let socket = URL(fileURLWithPath: "/tmp/cpulse-startup-\(UUID().uuidString.prefix(8)).sock")
        let installer = ClaudeCodeInstaller(socketURL: socket,
            authenticationToken: "startup-fixture", configurationDirectory: root.appendingPathComponent("config"),
            supportDirectory: root.appendingPathComponent("support"), helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let runtime = ClaudeCodeRuntime(defaults: defaults, installer: installer)
        defer { runtime.stop() }
        runtime.start()
        try await wait { !runtime.configuring }
        assert(runtime.error == nil)
        runtime.tick(now: Date().addingTimeInterval(120))
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(runtime.usage == nil && !runtime.scanning, "periodic tick cannot bypass startup delay")
        runtime.refreshUsage()
        try await wait { runtime.usage != nil }
        assert(!runtime.scanning, "manual refresh starts immediately during startup delay")
        let updatedAt = runtime.usage!.updatedAt
        try await Task.sleep(nanoseconds: 20_100_000_000)
        assert(runtime.usage!.updatedAt == updatedAt, "manual scan cancels delayed duplicate")
        runtime.stop()

        let automatic = ClaudeCodeRuntime(defaults: defaults, installer: installer)
        defer { automatic.stop() }
        automatic.start()
        try await wait { !automatic.configuring }
        assert(automatic.usage == nil)
        try await Task.sleep(nanoseconds: 20_100_000_000)
        try await wait { automatic.usage != nil }
        print("Claude startup usage: delayed automatic scan, tick suppression, manual preemption and duplicate cancellation passed")
    }

    @MainActor static func fallbackRegression() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/claude-runtime-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "fallback-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claude.enabled")
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("bridge.sock"), authenticationToken: "fixture",
            configurationDirectory: root.appendingPathComponent("config"), supportDirectory: root.appendingPathComponent("support"),
            helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let queue = DispatchQueue(label: "test.claude.configuration")
        let runtime = ClaudeCodeRuntime(defaults: defaults, installer: installer, configurationQueue: queue)
        defer { runtime.stop() }
        let base = Date()
        func hook(_ event: String, id: String = "fixture", at: Date? = nil, fields: [String: Any] = [:]) {
            let object: [String: Any] = ["session_id": id, "hook_event_name": event, "cwd": root.path]
                .merging(fields) { _, new in new }
            runtime.receive(.init(eventID: UUID().uuidString, kind: "hook", awaitsDecision: event == "PermissionRequest",
                payload: try! JSONSerialization.data(withJSONObject: object)), receivedAt: at ?? base)
        }
        hook("UserPromptSubmit"); hook("PreToolUse")
        let observedTurn = runtime.rows.first?.turnID
        queue.suspend()
        runtime.configure(enabled: true, approvals: true, statusLine: true)
        hook("UserPromptSubmit", id: "evicted")
        for _ in 0..<255 { hook("PostToolUse") }
        hook("Stop")
        assert(runtime.bufferedHookCount == 256, "configuration buffer is bounded and drops oldest")
        hook("PermissionRequest", fields: ["tool_name": "Bash", "tool_input": ["command": "echo fixture"]])
        assert(runtime.requests.isEmpty && runtime.bufferedHookCount == 256, "permission is returned, never queued or authorized")
        runtime.receive(.init(eventID: "status", kind: "statusLine", awaitsDecision: false,
            payload: try JSONSerialization.data(withJSONObject: ["capturedAt": base.timeIntervalSince1970, "rate_limits": ["five_hour": ["used_percentage": 20]]])))
        assert(runtime.limits != nil, "statusLine processed during configuration")
        queue.resume()
        try await wait { !runtime.configuring }
        assert(runtime.bufferedHookCount == 0 && runtime.rows.first?.phase == .completed, "Stop replays last and closes existing session")
        assert(runtime.rows.first?.turnID == observedTurn, "configuration preserves the observed turn identity")
        assert(!runtime.rows.contains { $0.id == "claude:evicted" }, "oldest queued event was evicted")
        hook("PermissionRequest", at: base, fields: ["tool_name": "Bash", "tool_input": ["command": "echo fixture"]])
        assert(runtime.requests.isEmpty, "late preconfiguration callback cannot restore stale approval capability")
        try FileManager.default.createDirectory(at: installer.projectsURL, withIntermediateDirectories: true)
        let transcript = installer.projectsURL.appendingPathComponent("fixture.jsonl")
        func append(_ type: String, at: Date, message: [String: Any]) throws {
            let line = try JSONSerialization.data(withJSONObject: ["type": type,
                "timestamp": ISO8601DateFormatter().string(from: at), "message": message]) + Data([10])
            if !FileManager.default.fileExists(atPath: transcript.path) { try Data().write(to: transcript) }
            let handle = try FileHandle(forWritingTo: transcript); defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: line)
        }
        let turn = Date(timeIntervalSince1970: floor(base.timeIntervalSince1970) + 10)
        try append("assistant", at: turn.addingTimeInterval(-10), message: ["id": "old", "stop_reason": "end_turn", "content": []])
        hook("UserPromptSubmit", at: turn, fields: ["transcript_path": transcript.path])
        hook("PreToolUse", at: turn)
        runtime.tick(now: turn.addingTimeInterval(6))
        assert(runtime.rows.first?.phase.isActive == true, "historical ending cannot finish new turn")
        try append("assistant", at: turn.addingTimeInterval(2), message: ["id": "end", "stop_reason": "end_turn", "content": [["type": "text", "text": "Finished"]]])
        runtime.tick(now: turn.addingTimeInterval(5))
        assert(runtime.rows.first?.phase.isActive == true, "transcript waits beyond five seconds")
        runtime.tick(now: turn.addingTimeInterval(6))
        assert(runtime.rows.first?.phase == .completed && runtime.rows.first?.actionText == "Finished", "missed Stop recovered from transcript")
        let next = turn.addingTimeInterval(10)
        hook("UserPromptSubmit", at: next)
        try append("assistant", at: next.addingTimeInterval(1), message: ["id": "end2", "stop_reason": "max_tokens", "content": []])
        try append("assistant", at: next.addingTimeInterval(2), message: ["id": "tool", "content": [["type": "tool_use", "id": "t", "name": "Bash"]]])
        runtime.tick(now: next.addingTimeInterval(6))
        assert(runtime.rows.first?.phase.isActive == true, "tool after ending blocks fallback")
        try append("user", at: next.addingTimeInterval(7), message: ["content": "[Request interrupted by user]"])
        runtime.tick(now: next.addingTimeInterval(8))
        assert(runtime.rows.first?.endReason == .cancelled, "transcript interruption cancels active turn")
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run(); child.waitUntilExit()
        assert(ClaudeCodeRuntime.processHasExited(child.processIdentifier), "reaped process returns ESRCH")
        assert(!ClaudeCodeRuntime.processHasExited(ProcessInfo.processInfo.processIdentifier), "live process is not ended")
        assert(!ClaudeCodeRuntime.processHasExited(0), "invalid PID is not probed")
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for shell in ["sh", "bash", "zsh", "dash", "fish", "env", "login", "timeout", "/bin/sh", "-zsh"] {
            assert(ClaudeCodeRuntime.validatedHookProcessID(["hook_process_id": ownPID, "hook_process_name": shell]) == nil,
                "shell process cannot become a fallback owner")
        }
        assert(ClaudeCodeRuntime.validatedHookProcessID(["hook_process_id": ownPID]) == nil, "name is required")
        assert(ClaudeCodeRuntime.validatedHookProcessID(["hook_process_id": ownPID, "hook_process_name": " "]) == nil, "blank name rejected")
        assert(ClaudeCodeRuntime.validatedHookProcessID(["hook_process_id": child.processIdentifier, "hook_process_name": "claude"]) == nil,
            "already dead process rejected at event receipt")
        assert(ClaudeCodeRuntime.validatedHookProcessID(["hook_process_id": ownPID, "hook_process_name": "claude"]) == ownPID,
            "live non-shell process accepted")
        func sleeper() throws -> Process {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]
            try process.run(); return process
        }
        let shellOwner = try sleeper()
        hook("UserPromptSubmit", at: next.addingTimeInterval(10), fields: ["hook_process_id": shellOwner.processIdentifier, "hook_process_name": "sh"])
        shellOwner.terminate(); shellOwner.waitUntilExit()
        runtime.tick(now: next.addingTimeInterval(11))
        assert(runtime.rows.first?.phase.isActive == true, "shell exit cannot end a working session")
        let firstOwner = try sleeper()
        hook("PreToolUse", at: next.addingTimeInterval(12), fields: ["hook_process_id": firstOwner.processIdentifier, "hook_process_name": "claude"])
        hook("PreToolUse", at: next.addingTimeInterval(13), fields: ["hook_process_id": ownPID, "hook_process_name": "runtime"])
        firstOwner.terminate(); firstOwner.waitUntilExit()
        runtime.tick(now: next.addingTimeInterval(14))
        assert(runtime.rows.first?.phase.isActive == true, "latest valid owner replaces the previous PID")
        hook("PreToolUse", at: next.addingTimeInterval(15), fields: ["hook_process_id": child.processIdentifier, "hook_process_name": "claude"])
        runtime.tick(now: next.addingTimeInterval(16))
        assert(runtime.rows.first?.phase.isActive == true, "dead incoming PID does not enable fallback")
        let finalOwner = try sleeper()
        hook("PreToolUse", at: next.addingTimeInterval(17), fields: ["hook_process_id": finalOwner.processIdentifier, "hook_process_name": "claude"])
        finalOwner.terminate(); finalOwner.waitUntilExit()
        runtime.tick(now: next.addingTimeInterval(18))
        assert(runtime.rows.first?.endReason == .ended, "validated owner exit closes active turn without success")
        queue.suspend()
        runtime.configure(enabled: false, approvals: false, statusLine: false)
        hook("Stop", id: "disabled")
        assert(runtime.bufferedHookCount == 0, "disabling does not retain events")
        queue.resume()
        try await wait { !runtime.configuring }
        assert(!runtime.enabled && runtime.rows.isEmpty, "disabled configuration cannot replay stale sessions")
        print("Claude runtime configuration/transcript/process fallback regressions passed")
    }

    /// Late subagent returns after a restart and thinking turns that never got a Stop hook.
    @MainActor static func quietTurnRegression() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/claude-runtime-quiet-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "quiet-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claude.enabled")
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("bridge.sock"), authenticationToken: "fixture",
            configurationDirectory: root.appendingPathComponent("config"), supportDirectory: root.appendingPathComponent("support"),
            helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let runtime = ClaudeCodeRuntime(defaults: defaults, installer: installer, configurationQueue: DispatchQueue(label: "test.claude.quiet"))
        defer { runtime.stop() }
        let start = Date()
        func hook(_ event: String, id: String, at: Date) {
            let object: [String: Any] = ["session_id": id, "hook_event_name": event, "cwd": root.path]
            runtime.receive(.init(eventID: UUID().uuidString, kind: "hook", awaitsDecision: false,
                payload: try! JSONSerialization.data(withJSONObject: object)), receivedAt: at)
        }
        func phase(_ id: String) -> TaskPhase? { runtime.rows.first { $0.id == "claude:" + id }?.phase }
        hook("SubagentStop", id: "ghost", at: start); hook("PostToolUse", id: "ghost", at: start)
        assert(phase("ghost") == nil, "late mid-turn events cannot open an unknown session")
        hook("UserPromptSubmit", id: "quiet", at: start); hook("PreToolUse", id: "longtool", at: start)
        runtime.tick(now: start.addingTimeInterval(ClaudeCodeRuntime.quietTurnGrace - 1))
        assert(phase("quiet") == .working, "a recently active thinking turn stays open")
        runtime.tick(now: start.addingTimeInterval(ClaudeCodeRuntime.quietTurnGrace + 1))
        assert(phase("quiet") == .ended, "a silent thinking turn ends without a Stop hook")
        assert(phase("longtool") == .usingTool, "a long-running tool keeps its turn open")
        hook("SubagentStop", id: "quiet", at: start.addingTimeInterval(ClaudeCodeRuntime.quietTurnGrace + 2))
        assert(phase("quiet") == .ended, "a late subagent return cannot reopen a finished turn")
        print("Claude runtime quiet-turn regressions passed")
    }
    static func activityStepLedgerRegression() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var summaries = ClaudeActivitySteps(); summaries.reset(at: start)
        summaries.transcript(.toolUse(id: "command", name: "Bash",
            input: "{\"description\":\"检查登录接口测试\",\"command\":\"fixture-private-argument\"}"), at: start)
        assert(summaries.runningTitle == "运行命令 · 检查登录接口测试")
        summaries.start(id: "command", name: "Bash", at: start, liveHook: true)
        assert(summaries.runningTitle == "运行命令 · 检查登录接口测试", "sparse duplicate hooks preserve command description")
        summaries.finish(id: "command", at: start, failed: true)
        summaries.transcript(.toolUse(id: "command", name: "Bash", input: "{}"), at: start)
        assert(summaries.visible.first?.title == "运行命令 · 检查登录接口测试" && summaries.visible.first?.state == .failed)
        for (index, input) in ["invalid", "{\"description\":42}", "{\"description\":\"   \"}",
                               "{\"command\":\"fixture-private-argument\"}"].enumerated() {
            summaries.transcript(.toolUse(id: "invalid-\(index)", name: "Bash", input: input), at: start.addingTimeInterval(Double(index + 1)))
            assert(summaries.runningTitle == "运行命令", "missing descriptions never expose raw commands")
        }
        summaries.start(id: "long", name: "Bash", at: start.addingTimeInterval(10),
            summary: "\n `" + String(repeating: "测", count: 300) + "`\n第二行")
        assert(summaries.runningTitle == "运行命令 · " + String(repeating: "测", count: 160))
        summaries.reset(at: start.addingTimeInterval(20))
        assert(summaries.visible.isEmpty, "new turns discard command descriptions")
        var steps = ClaudeActivitySteps(); steps.reset(at: start, promptID: "p1")
        func hook(_ event: String, _ id: String, _ name: String = "Read", prompt: String = "p1", agent: String? = nil) -> [String: Any] {
            var value: [String: Any] = ["hook_event_name": event, "tool_use_id": id, "tool_name": name, "prompt_id": prompt]
            if let agent { value["agent_id"] = agent }
            return value
        }
        steps.hook(hook("PreToolUse", "a"), at: start.addingTimeInterval(1), awaitsDecision: false, pending: false)
        steps.transcript(.toolUse(id: "a", name: "Read", input: "ignored"), at: start.addingTimeInterval(0.5))
        assert(steps.visible.count == 1 && steps.visible[0].state == .running, "Hook/log starts deduplicate")
        steps.hook(hook("PreToolUse", "b", "Bash"), at: start.addingTimeInterval(2), awaitsDecision: false, pending: false)
        steps.finish(id: "a", at: start.addingTimeInterval(3), failed: false)
        assert(steps.visible.first?.state == .done && steps.runningTitle == "运行命令", "parallel completion leaves other tool running")
        steps.hook(hook("PermissionRequest", "b", "Bash"), at: start.addingTimeInterval(4), awaitsDecision: true, pending: false)
        steps.transcript(.toolUse(id: "b", name: "Bash", input: ""), at: start.addingTimeInterval(2))
        assert(steps.visible.last?.state == .waiting, "log replay cannot clear a permission wait")
        steps.finish(id: "b", at: start.addingTimeInterval(5), failed: true)
        steps.finish(id: "b", at: start.addingTimeInterval(6), failed: false)
        assert(steps.visible.last?.state == .failed, "late generic success cannot erase explicit failure")
        steps.finish(id: "end-only", at: start.addingTimeInterval(8), failed: false)
        assert(!steps.visible.contains { $0.id == "end-only" }, "end-only evidence does not invent a named step")
        steps.start(id: "end-only", name: "Write", at: start.addingTimeInterval(7))
        assert(steps.visible.last?.state == .done, "late start joins known terminal without reopening")
        steps.start(id: "unfinished", name: "Bash", at: start.addingTimeInterval(9))
        steps.endUnfinished()
        assert(steps.visible.last?.state == .ended, "turn ending cannot manufacture tool success")
        steps.reset(at: start.addingTimeInterval(20), promptID: "p2")
        steps.hook(hook("PreToolUse", "late-old"), at: start.addingTimeInterval(21), awaitsDecision: false, pending: false)
        steps.hook(hook("PreToolUse", "a", prompt: "p2"), at: start.addingTimeInterval(21), awaitsDecision: false, pending: false)
        steps.transcript(.toolUse(id: "old-log", name: "Read", input: ""), at: start.addingTimeInterval(19))
        steps.hook(hook("PreToolUse", "child", prompt: "p2", agent: "subagent"), at: start.addingTimeInterval(21), awaitsDecision: false, pending: false)
        assert(steps.visible.isEmpty, "old prompt, retired IDs, old timestamps and child hooks stay out")
        steps.start(id: "", name: "Read", at: start.addingTimeInterval(22))
        steps.start(id: "nameless", name: " \n ", at: start.addingTimeInterval(22))
        assert(steps.visible.isEmpty, "invalid identity/name cannot create a step")
        steps.start(id: "long-running", name: "Bash", at: start.addingTimeInterval(22))
        for index in 0..<300 {
            let date = start.addingTimeInterval(Double(index + 23))
            steps.start(id: "tool-\(index)", name: "Read", at: date)
            steps.finish(id: "tool-\(index)", at: date, failed: false)
        }
        assert(steps.visible.count == 3 && steps.visible.contains { $0.id == "long-running" && $0.state == .running },
            "visible slots retain pending tools alongside recent finished steps")
        assert(steps.retainedCount <= 384, "bookkeeping stays bounded")
        var delayed = ClaudeActivitySteps(); delayed.reset(at: start.addingTimeInterval(20))
        delayed.start(id: "current", name: "Read", at: start.addingTimeInterval(21), liveHook: true)
        delayed.transcript(.toolResult(toolUseID: "current", text: "", isError: false), at: start.addingTimeInterval(19))
        delayed.transcript(.toolUse(id: "unrelated-old", name: "Write", input: ""), at: start.addingTimeInterval(19))
        assert(delayed.visible.count == 1 && delayed.visible[0].state == .done, "delayed current-ID result joins without admitting unrelated old history")
        print("Claude activity step ledger: dedup, parallel, waits, failure, terminal-only, late events, turn boundaries, child exclusion and bounds passed")
    }

    @MainActor static func activityStepsRegression() async throws {
        let root = URL(fileURLWithPath: "/tmp/cpulse-steps-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "test.claude.steps." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claude.enabled"); defaults.set(true, forKey: "claude.approvals")
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("bridge.sock"), authenticationToken: "fixture",
            configurationDirectory: root.appendingPathComponent("config"), supportDirectory: root.appendingPathComponent("support"),
            helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let runtime = ClaudeCodeRuntime(defaults: defaults, installer: installer)
        runtime.start(); defer { runtime.stop() }
        try await wait { !runtime.configuring && runtime.enabled }
        var time = Date().addingTimeInterval(1)
        func send(_ event: String, id: String = "", name: String = "Read", decision: Bool = false, extra: [String: Any] = [:]) throws {
            time = time.addingTimeInterval(1)
            var payload: [String: Any] = ["session_id": "steps", "cwd": "/fixture", "hook_event_name": event,
                "tool_use_id": id, "tool_name": name, "tool_input": [:], "prompt_id": "p1"]
            payload.merge(extra) { _, new in new }
            runtime.receive(.init(eventID: UUID().uuidString, kind: "hook", awaitsDecision: decision,
                payload: try JSONSerialization.data(withJSONObject: payload)), receivedAt: time)
        }
        try send("UserPromptSubmit")
        try send("PreToolUse", id: "a")
        try send("PreToolUse", id: "b", name: "Bash",
            extra: ["tool_input": ["description": "运行测试验证修复", "command": "fixture-private-argument"]])
        assert(runtime.rows[0].recentSteps.last?.title == "运行命令 · 运行测试验证修复"
            && runtime.rows[0].actionText == "运行命令 · 运行测试验证修复",
            "command descriptions reach both timeline and action fallback")
        try send("PostToolUse", id: "a")
        assert(runtime.rows[0].phase == .usingTool && runtime.rows[0].recentSteps.map(\.state) == [.done, .running])
        try send("PermissionRequest", id: "b", name: "Bash", decision: true)
        assert(runtime.rows[0].recentSteps.last?.state == .waiting && runtime.requests.count == 1)
        try send("PreToolUse", id: "c", name: "Grep")
        assert(runtime.rows[0].phase == .waitingApproval, "parallel work cannot hide a real pending approval")
        try send("PostToolUseFailure", id: "b", name: "Bash")
        assert(runtime.requests.isEmpty && runtime.rows[0].phase == .usingTool
            && runtime.rows[0].recentSteps.contains { $0.id == "b" && $0.state == .failed })
        try send("Stop", extra: ["is_interrupt": true])
        assert(runtime.rows[0].recentSteps.last?.state == .ended, "cancel leaves unconfirmed tool completion neutral")
        assert(runtime.rows[0].hidingDetails().recentSteps.isEmpty)
        let finishedAt = runtime.rows[0].updatedAt
        try send("PostToolUse", id: "c", name: "Grep")
        assert(runtime.rows[0].phase == .ended && runtime.rows[0].updatedAt == finishedAt
            && runtime.rows[0].recentSteps.last?.state == .done, "late result refines evidence without reopening a terminal turn")
        try send("PreToolUse", id: "c", name: "Grep")
        assert(runtime.rows[0].phase == .ended && runtime.rows[0].updatedAt == finishedAt, "duplicate start cannot reopen a settled call")
        try send("UserPromptSubmit", extra: ["prompt_id": "p2"])
        assert(runtime.rows[0].recentSteps.isEmpty)
        try send("PreToolUse", id: "child", extra: ["agent_id": "child", "prompt_id": "p2"])
        assert(runtime.rows[0].recentSteps.isEmpty)

        // Startup/log-only projection: current-turn boundary and matched tool results, no permission creation.
        let project = installer.projectsURL.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let path = project.appendingPathComponent("log-only.jsonl")
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let base = Date().addingTimeInterval(-10)
        let events: [[String: Any]] = [
            ["type": "user", "timestamp": formatter.string(from: base), "message": ["content": "Current task"]],
            ["type": "assistant", "timestamp": formatter.string(from: base.addingTimeInterval(1)),
             "message": ["id": "m", "content": [["type": "tool_use", "id": "log-a", "name": "Read", "input": [:]]]]],
            ["type": "user", "timestamp": formatter.string(from: base.addingTimeInterval(2)),
             "message": ["content": [["type": "tool_result", "tool_use_id": "log-a", "content": "ok", "is_error": false]]]],
            ["type": "assistant", "timestamp": formatter.string(from: base.addingTimeInterval(3)), "isSidechain": true,
             "message": ["id": "child", "content": [["type": "tool_use", "id": "child-log", "name": "Write", "input": [:]]]]]
        ]
        var data = Data()
        for event in events { data.append(try JSONSerialization.data(withJSONObject: event)); data.append(10) }
        try data.write(to: path)
        let payload: [String: Any] = ["session_id": "log-only", "cwd": "/fixture", "hook_event_name": "PreToolUse",
            "tool_use_id": "live-tool", "tool_name": "Bash", "transcript_path": path.path]
        runtime.receive(.init(eventID: "live", kind: "hook", awaitsDecision: false,
            payload: try JSONSerialization.data(withJSONObject: payload)))
        let recovered = runtime.rows.first { $0.sessionID == "claude:log-only" }!
        assert(recovered.recentSteps.map(\.id) == ["log-a", "live-tool"] && recovered.recentSteps.first?.state == .done)
        runtime.tick()
        assert(runtime.rows.first { $0.sessionID == "claude:log-only" }?.recentSteps == recovered.recentSteps,
            "repeated tail reads do not duplicate or restart steps")
        assert(runtime.requests.isEmpty)
        // Public progress survives tool callbacks, but never overrides approvals or crosses turns.
        let summaryPath = project.appendingPathComponent("summary.jsonl")
        let summaryStart = Date(timeIntervalSince1970: floor(time.timeIntervalSince1970) + 100)
        func appendSummary(_ offset: Double, content: [[String: Any]], sidechain: Bool = false) throws {
            let value: [String: Any] = ["type": "assistant", "uuid": UUID().uuidString,
                "timestamp": formatter.string(from: summaryStart.addingTimeInterval(offset)), "isSidechain": sidechain,
                "message": ["id": UUID().uuidString, "content": content]]
            let bytes = try JSONSerialization.data(withJSONObject: value) + Data([10])
            if !FileManager.default.fileExists(atPath: summaryPath.path) { try Data().write(to: summaryPath) }
            let handle = try FileHandle(forWritingTo: summaryPath); defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: bytes)
        }
        func summaryHook(_ event: String, _ offset: Double, decision: Bool = false) throws {
            let payload: [String: Any] = ["session_id": "summary", "cwd": "/fixture", "hook_event_name": event,
                "transcript_path": summaryPath.path, "tool_use_id": "summary-tool", "tool_name": "Bash",
                "tool_input": ["command": "echo fixture"]]
            runtime.receive(.init(eventID: UUID().uuidString, kind: "hook", awaitsDecision: decision,
                payload: try JSONSerialization.data(withJSONObject: payload)), receivedAt: summaryStart.addingTimeInterval(offset))
        }
        func summaryRow() -> ActivitySessionSnapshot { runtime.rows.first { $0.sessionID == "claude:summary" }! }
        try appendSummary(-10, content: [["type": "text", "text": "旧轮摘要"]])
        try summaryHook("UserPromptSubmit", 0)
        assert(summaryRow().actionText != "旧轮摘要")
        try appendSummary(1, content: [["type": "text", "text": "\n正在检查 `登录失败` 的原因\n第二行"]])
        try summaryHook("PreToolUse", 2)
        assert(summaryRow().actionText == "正在检查 登录失败 的原因" && summaryRow().recentSteps.last?.state == .running)
        try summaryHook("PostToolUse", 3)
        assert(summaryRow().actionText == "正在检查 登录失败 的原因", "tool completion preserves public progress")
        try appendSummary(4, content: [["type": "text", "text": "正在验证修复结果"]])
        try summaryHook("PermissionRequest", 5, decision: true)
        assert(summaryRow().phase == .waitingApproval && summaryRow().actionText == "点击任务查看 Claude 请求")
        try summaryHook("PostToolUse", 6)
        assert(summaryRow().actionText == "正在验证修复结果")
        assert(summaryRow().hidingDetails().actionText == "任务内容已隐藏")
        try summaryHook("UserPromptSubmit", 10)
        try appendSummary(7, content: [["type": "text", "text": "迟到的旧轮摘要"]])
        try appendSummary(11, content: [["type": "thinking", "thinking": "private"], ["type": "text", "text": "   "]])
        try appendSummary(12, content: [["type": "text", "text": "子任务摘要"]], sidechain: true)
        try summaryHook("PreToolUse", 13)
        assert(!["正在验证修复结果", "迟到的旧轮摘要", "private", "子任务摘要"].contains(summaryRow().actionText),
            "new turns, private reasoning, empty text and sidechains cannot leak stale progress")
        try appendSummary(14, content: [["type": "text", "text": "新轮公开进展"]])
        try summaryHook("PostToolUse", 15)
        assert(summaryRow().actionText == "新轮公开进展")
        print("Claude activity runtime: live steps, parallel approval, failure, cancellation, new turn, privacy and transcript recovery passed")
    }

    @MainActor static func liveRegistryRecoveryRegression() async throws {
        // Short path is required for the fixture's Unix-domain bridge socket.
        let root = URL(fileURLWithPath: "/tmp/cpulse-recovery-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("claude")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
        func owner() throws -> Process {
            let process = Process(); process.executableURL = executable; process.arguments = ["120"]
            try process.run(); return process
        }
        let busyProcess = try owner(), idleProcess = try owner()
        defer {
            for process in [busyProcess, idleProcess] where process.isRunning { process.terminate(); process.waitUntilExit() }
        }
        try await wait { ClaudeLiveSessionRegistry.processInfo(busyProcess.processIdentifier)?.name == "claude" }
        let configuration = root.appendingPathComponent("config")
        let registry = configuration.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: configuration.appendingPathComponent("settings.json"))
        let busyID = UUID().uuidString.lowercased(), idleID = UUID().uuidString.lowercased()
        let started = Date()
        func write(_ process: Process, id: String, status: String, at date: Date) throws {
            let info = ClaudeLiveSessionRegistry.processInfo(process.processIdentifier)!
            let object: [String: Any] = ["pid": process.processIdentifier, "pidDomain": "darwin", "kind": "interactive",
                "sessionId": id, "cwd": "/fixture", "name": "Existing task", "status": status,
                "statusUpdatedAt": date.timeIntervalSince1970 * 1000,
                "procStart": ClaudeLiveSessionRegistry.processStamp(info.startedAt)]
            try JSONSerialization.data(withJSONObject: object).write(to: registry.appendingPathComponent("\(process.processIdentifier).json"), options: .atomic)
        }
        try write(busyProcess, id: busyID, status: "busy", at: started)
        try write(idleProcess, id: idleID, status: "idle", at: started)
        let suite = "test.claude.recovery." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claude.enabled")
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("bridge.sock"), authenticationToken: "fixture",
            configurationDirectory: configuration, supportDirectory: root.appendingPathComponent("support"),
            helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let runtime = ClaudeCodeRuntime(defaults: defaults, installer: installer)
        runtime.start(); defer { runtime.stop() }
        try await wait { !runtime.configuring && runtime.rows.count == 1 }
        assert(runtime.rows[0].sessionID == "claude:" + busyID && runtime.rows[0].phase == .working,
            "startup recovers only the already-busy live owner without a new Hook")
        assert(runtime.rows[0].startedAt == nil && runtime.rows[0].tokenUsage == nil,
            "registry busy transition alone cannot invent turn start time or token usage")
        assert(runtime.requests.isEmpty, "recovery never recreates approval capabilities")
        try write(busyProcess, id: busyID, status: "idle", at: Date())
        runtime.tick()
        try await wait { runtime.rows.first?.phase == .ended }
        assert(busyProcess.isRunning, "idle owner stays alive but does not remain an active task")
        runtime.stop()

        try write(busyProcess, id: busyID, status: "busy", at: Date())
        let project = configuration.appendingPathComponent("projects/fixture")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        var transcript = Data()
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for time in [started.addingTimeInterval(-60), started] {
            transcript.append(try JSONSerialization.data(withJSONObject: ["type": "user", "timestamp": formatter.string(from: time),
                "message": ["content": "Existing user task"]])); transcript.append(0x0A)
        }
        let toolTime = Date()
        for event: [String: Any] in [
            ["type": "assistant", "timestamp": formatter.string(from: toolTime),
             "message": ["id": "recovered-message", "content": [["type": "tool_use", "id": "recovered-read", "name": "Read", "input": [:]]]]],
            ["type": "user", "timestamp": formatter.string(from: toolTime),
             "message": ["content": [["type": "tool_result", "tool_use_id": "recovered-read", "content": "done"]]]]
        ] {
            transcript.append(try JSONSerialization.data(withJSONObject: event)); transcript.append(0x0A)
        }
        try transcript.write(to: project.appendingPathComponent(busyID + ".jsonl"))
        let restarted = ClaudeCodeRuntime(defaults: defaults, installer: installer)
        restarted.start(); defer { restarted.stop() }
        try await wait { !restarted.configuring && restarted.rows.first?.phase == .working }
        assert(abs(restarted.rows[0].startedAt!.timeIntervalSince(started)) < 0.01,
            "recovery finds the latest user prompt instead of treating registry busy transitions as turn starts")
        assert(restarted.rows[0].recentSteps.first?.id == "recovered-read" && restarted.rows[0].recentSteps.first?.state == .done,
            "registry startup recovers confirmed tool steps without new Hooks")
        let hook: [String: Any] = ["session_id": busyID, "hook_event_name": "PostToolUse", "cwd": "/fixture",
            "hook_process_id": busyProcess.processIdentifier, "hook_process_name": "claude"]
        restarted.receive(.init(eventID: "fresh-hook", kind: "hook", awaitsDecision: false,
            payload: try JSONSerialization.data(withJSONObject: hook)))
        try write(busyProcess, id: busyID, status: "idle", at: Date())
        restarted.tick()
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(restarted.rows.first?.phase == .working, "fresh Hook owns lifecycle after recovery; registry cannot override it")
        busyProcess.terminate(); busyProcess.waitUntilExit()
        restarted.tick()
        assert(restarted.rows.first?.phase == .ended, "recovered session still ends when its proved owner exits")
        assert(restarted.requests.isEmpty)
        print("Claude registry recovery: live busy/idle, restart, start time, no approvals, hook takeover and owner exit passed")
    }

    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 { if predicate() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        fatalError("Claude runtime test timed out")
    }
    static func send(_ installer: ClaudeCodeInstaller, event: String) async throws {
        let output = try await Task.detached { try helperRun(installer, event: event) }.value
        assert(output.isEmpty)
    }
    static func helperRun(_ installer: ClaudeCodeInstaller, event: String, fields: [String: Any] = [:]) throws -> Data {
        let process = Process(); process.executableURL = installer.installedHelperURL
        process.arguments = [event.hasSuffix("StatusLine") || event == "statusLine" ? "--claude-statusline" : "--claude-code", "--configuration", installer.routeURL.path]
        let stdin = Pipe(), stdout = Pipe(); process.standardInput = stdin; process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        var object: [String: Any] = ["hook_event_name": event, "session_id": "runtime-fixture", "cwd": "/fixture", "tool_use_id": "tool", "tool_name": "Bash", "tool_input": ["command": "echo fixture"]]
        object.merge(fields) { _, new in new }
        if event == "statusLine" { object["rate_limits"] = ["five_hour": ["used_percentage": 25, "resets_at": Date().addingTimeInterval(3600).timeIntervalSince1970]] }
        try stdin.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: object)); try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        assert(process.terminationStatus == 0); return data
    }
}
