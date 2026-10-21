import AppKit
import Foundation

@main enum ClaudeRuntimeTests {
    @MainActor static func main() async throws {
        try await fallbackRegression()
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

    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 { if predicate() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        fatalError("Claude runtime test timed out")
    }
    static func send(_ installer: ClaudeCodeInstaller, event: String) async throws {
        let output = try await Task.detached { try helperRun(installer, event: event) }.value
        assert(output.isEmpty)
    }
    static func helperRun(_ installer: ClaudeCodeInstaller, event: String) throws -> Data {
        let process = Process(); process.executableURL = installer.installedHelperURL
        process.arguments = [event.hasSuffix("StatusLine") || event == "statusLine" ? "--claude-statusline" : "--claude-code", "--configuration", installer.routeURL.path]
        let stdin = Pipe(), stdout = Pipe(); process.standardInput = stdin; process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        var object: [String: Any] = ["hook_event_name": event, "session_id": "runtime-fixture", "cwd": "/fixture", "tool_use_id": "tool", "tool_name": "Bash", "tool_input": ["command": "echo fixture"]]
        if event == "statusLine" { object["rate_limits"] = ["five_hour": ["used_percentage": 25, "resets_at": Date().addingTimeInterval(3600).timeIntervalSince1970]] }
        try stdin.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: object)); try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        assert(process.terminationStatus == 0); return data
    }
}
