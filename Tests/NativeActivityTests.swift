import Foundation

@main
@MainActor
enum NativeActivityTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do { if try !condition() { fatalError(message) } } catch { fatalError("\(message): \(error)") }
    }
    static func projection(status: String = "inProgress", turn: String = "turn", flags: [String]? = [], requests: [[String: Any]] = [], source: Any = "appServer") throws -> CodexDesktopInteractionProjection {
        var state: [String: Any] = ["id": "thread", "source": source, "title": "Example", "requests": requests,
            "turns": [["turnId": turn, "status": status, "turnStartedAtMs": 1000000, "items": []]]]
        if let flags { state["threadRuntimeStatus"] = ["type": "active", "activeFlags": flags] }
        return try CodexDesktopRequestProjector.project(conversationID: "thread", conversationStateData: JSONSerialization.data(withJSONObject: state))
    }
    static func main() async throws {
        setbuf(stdout, nil)
        let now = Date(timeIntervalSince1970: 1100)
        let running = NativeActivityEvidence.project(try projection(), previous: nil, now: now)!
        expect(running.phase == .working, "owner proves running without Hook")
        let waiting = NativeActivityEvidence.project(try projection(flags: ["waitingOnApproval"]), previous: running, now: now)!
        expect(waiting.phase == .waitingApproval, "native runtime flags prove waiting without Hook")
        let unknown = NativeActivityEvidence.project(try projection(flags: nil), previous: waiting, now: now)!
        expect(unknown.phase == .waitingApproval, "missing runtime flags cannot clear pending approval")
        expect(NativeActivityEvidence.project(try projection(), previous: waiting, now: now)?.phase == .working, "authoritative empty pending and running flags settle wait")
        let request: [String: Any] = ["id": "approval", "method": "item/commandExecution/requestApproval", "params": ["threadId": "thread", "turnId": "turn", "command": "test"]]
        expect(NativeActivityEvidence.project(try projection(requests: [request]), previous: nil, now: now)?.phase == .waitingApproval, "pending request also proves wait")
        expect(NativeActivityEvidence.project(try projection(turn: "new", requests: [request]), previous: waiting, now: now)?.phase == .working, "old-turn request cannot block new turn")
        for (status, reason) in [("completed", SessionEndReason.completed), ("interrupted", .cancelled), ("failed", .failed)] {
            expect(NativeActivityEvidence.project(try projection(status: status), previous: waiting, now: now)?.terminal == reason, "native terminal preserves \(status) semantics")
        }
        expect(NativeActivityEvidence.project(try projection(status: "future"), previous: running, now: now) == nil, "unknown terminal is not success")
        expect(NativeActivityEvidence.project(try projection(source: ["internal": "memory_consolidation"]), previous: nil, now: now) == nil, "memory task excluded")
        let local = LocalSessionSnapshot(sessionID: "thread", turnID: "turn", cwd: "/Example", model: "gpt-6.1-sol", isActive: true,
            updatedAt: now, activities: [.init(id: "tool", kind: .command, title: "测试", isRunning: true, updatedAt: now)], startedAt: now.addingTimeInterval(-100))
        expect(running.applying(to: local)?.nativePhase == .usingTool, "running native turn preserves local live tool")
        expect(waiting.applying(to: local)?.nativePhase == .waitingApproval, "native wait takes precedence over unfinished tool")
        let newer = LocalSessionSnapshot(sessionID: "thread", turnID: "new", cwd: "/Example", model: nil, isActive: true,
            updatedAt: now, activities: [], startedAt: now)
        expect(running.applying(to: newer) == nil, "old native turn cannot overwrite a newer local start")
        expect(CodexDesktopIPCClient.observationMethods == ["initialize", "thread-owner-discovery", "thread-stream-following-changed"], "transport has no submission verbs")
        expect(CodexDesktopIPCClient.permitsObservationMessage(.object(["type": .string("client-discovery-response"), "requestId": .string("r"), "response": .object(["canHandle": .bool(false)])])), "observer can refuse thread ownership")
        expect(!CodexDesktopIPCClient.permitsObservationMessage(.object(["type": .string("request"), "method": .string("thread-follower-command-approval-decision")])), "approval egress is blocked")
        expect(!CodexDesktopIPCClient.permitsObservationMessage(.object(["type": .string("response"), "requestId": .string("r"), "resultType": .string("success"), "result": .object(["decision": .string("accept")])])), "direct successful approval response is blocked")
        var decoder = CodexDesktopIPCFrameDecoder(maximumFrameBytes: 1024)
        let framed = try CodexDesktopIPCFrameDecoder.frame(Data("{}".utf8), maximumFrameBytes: 1024)
        let partial = try decoder.append(framed.prefix(2))
        expect(partial.isEmpty, "fragmented length waits for remainder")
        let complete = try decoder.append(framed.dropFirst(2))
        expect(complete == [Data("{}".utf8)], "fragmented frame reassembles")
        let temporary = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".tmp/native-activity-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = temporary.appendingPathComponent("rollout.jsonl")
        let reader = SessionActivityService()
        func record(_ type: String, _ payload: [String: Any]) throws -> Data {
            var data = try JSONSerialization.data(withJSONObject: ["timestamp": ISO8601DateFormatter().string(from: Date()), "type": type, "payload": payload], options: [.sortedKeys])
            data.append(10); return data
        }
        func append(_ data: Data) throws {
            let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        }
        var initial = try record("session_meta", ["id": "native-fixture", "source": "vscode", "cwd": "/Example"])
        initial.append(try record("event_msg", ["type": "task_started", "turn_id": "one"]))
        try initial.write(to: file)
        expect(reader.readSnapshot(from: file)?.isActive == true, "log starts task with no Hook")
        let tool = try record("response_item", ["type": "function_call", "name": "exec_command", "call_id": "call", "arguments": "{}"])
        let split = tool.count / 2
        try append(tool.prefix(split))
        expect(reader.readSnapshot(from: file)?.activities.isEmpty == true, "half-written tool event stays buffered")
        try append(tool.dropFirst(split))
        expect(reader.readSnapshot(from: file)?.activities.first?.isRunning == true, "completed fragment creates one tool event")
        expect(reader.readSnapshot(from: file)?.activities.count == 1, "unchanged EOF neither duplicates nor loses tool state")
        try append(record("response_item", ["type": "function_call_output", "call_id": "call"]))
        expect(reader.readSnapshot(from: file)?.activities.first?.isRunning == false, "incremental output closes exact tool")
        try append(record("event_msg", ["type": "task_complete", "turn_id": "one"]))
        expect(reader.readSnapshot(from: file)?.evidence?.endReason == .completed, "incremental terminal completes exact turn")
        try record("session_meta", ["id": "replacement", "source": ["internal": "memory_consolidation"]]).write(to: file)
        expect(reader.readSnapshot(from: file)?.sessionID == "replacement", "truncated file resets cursor identity")
        expect(reader.readSnapshot(from: file)?.sessionKind == .memoryConsolidation, "copied classifier identifies internal memory tasks")
        var lifecycle = ActivitySessionState()
        let liveNative = running.applying(to: local)!
        let projects = ProjectActivityAggregator.projects(snapshots: [liveNative], hookTasks: [], now: now, catalog: .empty)
        lifecycle.update(projects: projects, snapshots: [liveNative], hookTasks: [], usages: [:], now: now, completionHold: 8)
        expect(lifecycle.rows.first?.phase == .usingTool, "no-Hook native/local pipeline produces active card")
        let terminalNative = NativeActivityEvidence.project(try projection(status: "completed"), previous: running, now: now.addingTimeInterval(1))!.applying(to: local)!
        lifecycle.update(projects: [], snapshots: [terminalNative], hookTasks: [], usages: [:], now: now.addingTimeInterval(1), completionHold: 8)
        expect(lifecycle.rows.first?.phase == .completed && lifecycle.rows.first?.endReason == .completed, "native terminal creates completion receipt with zero Hook input")
        let fixtureState: [String: Any] = ["id": "thread", "source": "appServer", "title": "Native title", "requests": [request],
            "threadRuntimeStatus": ["type": "active", "activeFlags": ["waitingOnApproval"]],
            "turns": [["turnId": "turn", "status": "inProgress", "turnStartedAtMs": 1000000, "items": []]]]
        let fixture = CodexDesktopIPCFixture(state: fixtureState)
        let fixtureClient = fixture.client()
        let monitor = NativeActivityObserver(client: fixtureClient)
        monitor.observe([local])
        for _ in 0..<100 where monitor.acceptedSnapshots == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        let conflictingHook = MonitoredTask(id: "thread", turnID: "turn", projectName: "Example", projectPath: "/Example", phase: .completed, updatedAt: now, confirmsTurnEnd: true)
        var merged = monitor.merge([local], names: [:], hooks: [conflictingHook])
        expect(merged.snapshots.first?.nativePhase == .waitingApproval, "real adapter accepts owner-validated fixture stream")
        expect(merged.names["thread"] == "Native title", "desktop title hydrates local task")
        expect(merged.hooks.isEmpty, "late Hook completion cannot override native current wait")
        fixture.emitRawPayload(try JSONSerialization.data(withJSONObject: ["type": "client-discovery-request", "requestId": "discovery"]), chunkBytes: 128)
        try await Task.sleep(nanoseconds: 100_000_000)
        expect(monitor.state == .connected, "protocol ownership refusal keeps observation connection alive")
        expect(fixture.submissions.isEmpty, "observation sends no approval or response operation")
        var terminalState = fixtureState
        terminalState["requests"] = []
        terminalState["turns"] = [["turnId": "turn", "status": "completed", "items": []]]
        fixture.setState(terminalState, revision: 8)
        for _ in 0..<100 where monitor.acceptedSnapshots < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(monitor.merge([local], names: [:], hooks: []).snapshots.first?.nativePhase == .completed, "terminal stream settles current turn")
        fixture.setState(fixtureState, revision: 9)
        for _ in 0..<100 where monitor.acceptedSnapshots < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(monitor.merge([local], names: [:], hooks: []).snapshots.first?.nativePhase == .completed, "later stale active evidence cannot reopen settled turn")
        fixture.emitState(version: 99)
        for _ in 0..<100 where monitor.state != .disconnected { try await Task.sleep(nanoseconds: 10_000_000) }
        merged = monitor.merge([local], names: [:], hooks: [conflictingHook])
        expect(merged.snapshots.first?.nativePhase == .completed && merged.hooks.isEmpty, "disconnect preserves previously proved terminal against stale Hook")
        await monitor.stop()
        merged = monitor.merge([local], names: [:], hooks: [conflictingHook])
        expect(merged.snapshots.first?.nativePhase == nil && merged.hooks.count == 1, "without native evidence existing local/Hook pipeline remains available")
        print("Native activity tests: \(checks) passed")
        if ProcessInfo.processInfo.environment["CODEX_NATIVE_ACTIVITY_PROBE"] == "1" {
            let service = SessionActivityService()
            let client = CodexDesktopIPCClient()
            let observer = NativeActivityObserver(client: client)
            var phases = Set<String>()
            var refreshes = 0
            let expires = Date().addingTimeInterval(25)
            while Date() < expires {
                let (locals, names) = await withCheckedContinuation { continuation in service.fetch { continuation.resume(returning: ($0, $1)) } }
                observer.observe(locals)
                let result = observer.merge(locals, names: names, hooks: [])
                let native = result.snapshots.filter { $0.nativePhase != nil }
                let current = Set(native.compactMap { $0.nativePhase?.rawValue })
                phases.formUnion(current); refreshes += 1
                if refreshes == 1 || refreshes % 5 == 0 { print("Probe: connection=\(observer.state), nativeSnapshots=\(observer.acceptedSnapshots), nativeRows=\(native.count), locals=\(locals.count), kinds=\(Dictionary(grouping: locals, by: { $0.sessionKind.rawValue }).mapValues { $0.count }), phases=\(current.sorted()), hooks=0") }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            print("Connection diagnostic: \(await client.lastConnectionError ?? "none")")
            print("Probe result: observed=\(phases.sorted()), accepted=\(observer.acceptedSnapshots), hooks=0")
            let accepted = observer.acceptedSnapshots
            await observer.stop()
            if accepted == 0 { print("FAIL: no owner-validated desktop snapshots"); exit(1) }
        }
    }
}
