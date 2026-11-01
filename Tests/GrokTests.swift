import Foundation
import Darwin

@main
struct GrokTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("Grok: " + message) }
    }
    static func event(_ kind: String, _ seconds: Double, prompt: String? = nil, fields: [String: Any] = [:]) -> [String: Any] {
        var update = fields; update["sessionUpdate"] = kind
        var meta: [String: Any] = ["agentTimestampMs": seconds * 1000]
        if let prompt { meta["promptId"] = prompt }
        return ["timestamp": seconds, "method": "session/update", "params": ["update": update, "_meta": meta]]
    }
    static func encoded(_ objects: [[String: Any]]) throws -> Data {
        var result = Data()
        for object in objects { result.append(try JSONSerialization.data(withJSONObject: object)); result.append(10) }
        return result
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period: [String: Any] = ["type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "2027-01-01T00:00:00Z", "end": "2028-01-01T00:00:00Z"]
        let config: [String: Any] = ["creditUsagePercent": 23.5, "currentPeriod": period, "prepaidBalance": [:], "isUnifiedBillingUser": true]
        let quota = GrokQuotaSnapshot.decode(["config": config, "subscription_tier": "SuperGrok Plus"], now: now)!
        expect(quota.remainingPercent == 77, "remaining percentage comes from service usage")
        expect(quota.prepaidCents == 0 && quota.sharedPool == true, "proto zero cents and shared pool are separate")
        expect(quota.title == "每周额度", "typed period")
        expect(quota.isAvailable(at: now) && !quota.isStale(at: now), "fresh quota")
        expect(quota.isStale(at: now.addingTimeInterval(301)), "stale snapshot is explicit")
        expect(!quota.isAvailable(at: now.addingTimeInterval(-61)), "future capture rejected")
        let retainedViewTime = now.addingTimeInterval(-120)
        expect(!quota.isAvailable(at: retainedViewTime), "reproduces old UI clock rejecting a newly captured quota")
        expect(quota.isAvailable(at: GrokDisplayClock.now(sampled: retainedViewTime, current: now)), "current render clock restores a real fresh quota")
        expect(!quota.isAvailable(at: GrokDisplayClock.now(sampled: retainedViewTime, current: Date(timeIntervalSince1970: 2_000_000_000))), "clock correction never revives an expired period")
        expect(!quota.isAvailable(at: Date(timeIntervalSince1970: 2_000_000_000)), "expired period hidden")
        for invalid: Any in [true, -1, 101, "23", NSNull()] {
            var c = config; c["creditUsagePercent"] = invalid
            expect(GrokQuotaSnapshot.decode(["config": c], now: now) == nil, "invalid percentage rejected")
        }
        expect(GrokQuotaSnapshot.decode(["config": NSNull()], now: now) == nil, "no quota stays unavailable")
        expect(GrokQuotaSnapshot.decode(["config": ["monthlyLimit": ["val": 100], "used": ["val": 25]]], now: now)?.remainingPercent == 75, "legacy budget uses real values")
        expect(GrokQuotaSnapshot.decode(["config": ["monthlyLimit": ["val": 0], "used": [:]]], now: now) == nil, "zero budget unknown")
        expect(GrokSpend.decode(["totalTokens": 100, "costUsdTicks": 1_000_000_000])?.cost == 0.1, "fixed point cost scale")
        expect(GrokSpend.decode(["totalTokens": 100, "costUsdTicks": 1, "costIsPartial": true])?.cost == nil, "partial cost not complete bill")
        expect(GrokSpend.decode(["totalTokens": 100])?.cost == nil, "missing cost not zero")
        for invalid: Any in [true, -1, 1.5, Double(Int.max)] { expect(GrokJSON.integer(invalid) == nil, "invalid count rejected") }
        expect(GrokJSON.eventDate(["timestamp": 1e300]) == nil, "huge timestamp rejected before Calendar use")
        expect(GrokJSON.eventDate(event("user_message_chunk", Date().timeIntervalSince1970 + 100)) == nil, "future task cannot appear live")

        var turn = GrokTurnState()
        _ = turn.consume(event("user_message_chunk", 100))
        _ = turn.consume(event("agent_thought_chunk", 101, prompt: "p1", fields: ["content": ["type": "text", "text": "private reasoning"]]))
        expect(turn.active && turn.promptID == "p1" && turn.text.isEmpty, "thought content never becomes summary")
        _ = turn.consume(event("tool_call", 102, prompt: "p1", fields: ["toolCallId": "t1", "title": "grep"]))
        expect(turn.phase == .tool && turn.steps.count == 1, "tool start is activity, not approval")
        _ = turn.consume(event("agent_message_chunk", 102.5, prompt: "p1", fields: ["content": ["type": "text", "text": "公开进度"]]))
        expect(turn.phase == .tool, "public progress does not hide a running parallel tool")
        _ = turn.consume(event("tool_call_update", 103, prompt: "p1", fields: ["toolCallId": "t1", "status": "completed"]))
        expect(turn.steps[0].status == "completed" && turn.phase == .working, "tool completion preserved")
        let spend: [String: Any] = ["totalTokens": 100, "inputTokens": 80, "cachedReadTokens": 40, "outputTokens": 20, "costUsdTicks": 1_000_000_000]
        let complete = event("turn_completed", 104, fields: ["prompt_id": "p1", "stop_reason": "end_turn", "usage": spend])
        expect(turn.consume(complete)?.2.tokens == 100 && turn.phase == .completed, "cached tokens are not counted twice")
        _ = turn.consume(event("tool_call", 105, prompt: "p1", fields: ["toolCallId": "late", "title": "late tool"]))
        expect(turn.phase == .completed && turn.steps.count == 1, "late tool does not resurrect completed task")
        _ = turn.consume(event("user_message_chunk", 106))
        _ = turn.consume(event("agent_message_chunk", 107, prompt: "p2", fields: ["content": ["type": "text", "text": "公开进度\n第二行"]]))
        _ = turn.consume(complete)
        expect(turn.promptID == "p2" && turn.active && turn.text == "公开进度", "old completion cannot end new turn")
        _ = turn.consume(event("turn_completed", 108, fields: ["prompt_id": "p2", "stop_reason": "cancelled"]))
        expect(turn.phase == .cancelled && turn.tokens == nil, "cancel without usage still ends task")

        let sessions = root.appendingPathComponent("sessions/group")
        let id = UUID().uuidString, fork = UUID().uuidString, child = UUID().uuidString
        for sessionID in [id, fork, child] {
            let dir = sessions.appendingPathComponent(sessionID)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var info: [String: Any] = ["id": sessionID, "cwd": "/fixture/project"]
            if sessionID == child { info["subagentType"] = "explore" }
            try JSONSerialization.data(withJSONObject: ["info": info, "generated_title": "Fixture", "current_model_id": "grok-test"]).write(to: dir.appendingPathComponent("summary.json"))
            try encoded([event("user_message_chunk", 100), event("agent_message_chunk", 101, prompt: "p1"), complete]).write(to: dir.appendingPathComponent("updates.jsonl"))
        }
        let reader = GrokSessionReader(home: root)
        var scan = await reader.scan(now: now)
        expect(scan.usage.sessionCount == 2, "subagents excluded from parent rollup")
        expect(scan.usage.lifetimeTokens == 100 && scan.usage.days.first?.cost == 0.1, "inherited fork prompts deduplicated globally")
        expect(scan.usage.complete, "complete initial scan")
        let path = sessions.appendingPathComponent(id).appendingPathComponent("updates.jsonl")
        let handle = try FileHandle(forWritingTo: path); try handle.seekToEnd()
        let partial = try JSONSerialization.data(withJSONObject: event("user_message_chunk", 200))
        try handle.write(contentsOf: partial); try handle.close()
        scan = await reader.scan(now: now.addingTimeInterval(31))
        expect(!scan.usage.complete && scan.sessions.first { $0.id == id }?.caughtUp == false, "partial final line not published as live task")
        let append = try FileHandle(forWritingTo: path); try append.seekToEnd(); try append.write(contentsOf: Data([10])); try append.close()
        scan = await reader.scan(now: now.addingTimeInterval(62))
        expect(scan.usage.complete && scan.sessions.first { $0.id == id }?.turn.active == true, "partial line completes on next scan")
        try Data("malformed\n".utf8).write(to: path, options: .atomic)
        scan = await reader.scan(now: now.addingTimeInterval(93))
        expect(!scan.usage.complete && scan.sessions.first { $0.id == id }?.turn.phase == .idle, "inode replacement resets live evidence and marks corrupt history")
        try Data().write(to: path)
        scan = await reader.scan(now: now.addingTimeInterval(124))
        expect(scan.usage.complete, "truncation clears old malformed state")
        try JSONSerialization.data(withJSONObject: [["session_id": id, "pid": 123, "pid_start": 10_000_000]]).write(to: root.appendingPathComponent("active_sessions.json"))
        expect(GrokSessionReader.liveIDs(home: root, lookup: { $0 == 123 && $1 == 10 }).contains(id), "registry validates process identity")
        expect(GrokSessionReader.liveIDs(home: root, lookup: { _, _ in false }).isEmpty, "dead or reused process rejected")

        let fixture = root.appendingPathComponent("fake-grok")
        let script = """
        #!/usr/bin/env python3
        import sys,json,pathlib,time
        mode=pathlib.Path('mode').read_text()
        r=json.loads(sys.stdin.readline())
        assert r['method']=='_x.ai/billing' and r['params']=={} and sys.argv[1:]==['agent','--no-leader','stdio']
        if mode=='timeout':time.sleep(5)
        if mode=='auth':v={'error':{'code':-32000,'message':'Authentication required'}}
        elif mode=='unsupported':v={'error':{'code':-32601,'message':'Method not found'}}
        elif mode=='empty':v={'result':{'config':None}}
        elif mode in ['flaky','upstream','network']:
            counter=pathlib.Path('attempts');n=int(counter.read_text())+1 if counter.exists() else 1;counter.write_text(str(n))
            if mode=='flaky' and n>=3:v={'result':{'config':{'creditUsagePercent':1}}}
            else:v={'error':{'code':-32603,'message':'Internal error','data':'Failed to fetch billing data: network' if mode=='network' else 'Billing service error: cursor billing: snapshot failed'}}
        else:v={'result':{'config':{'creditUsagePercent':1}}}
        print(json.dumps({'jsonrpc':'2.0','id':99,**v}),flush=True)
        print(json.dumps({'jsonrpc':'2.0','id':r['id'],**v}),flush=True)
        time.sleep(10)
        """
        try script.write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        for (mode, failure) in [("valid", nil), ("auth", GrokBillingClient.Failure.authentication), ("unsupported", .unsupported), ("empty", .noQuota), ("timeout", .timeout)] {
            try mode.write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
            do {
                let q = try GrokBillingClient().fetch(executable: fixture, home: root, timeout: mode == "timeout" ? 0.1 : 3)
                expect(failure == nil && q.remainingPercent == 99, "valid matching response only")
            } catch { expect(error as? GrokBillingClient.Failure == failure, "transport failure classified: " + mode) }
        }
        let cancelled = GrokBillingClient(); cancelled.cancel()
        do { _ = try cancelled.fetch(executable: fixture, home: root); expect(false, "cancel prevents launch") }
        catch { expect(error as? GrokBillingClient.Failure == .cancelled, "cancel before launch") }
        for (mode, failure) in [("flaky", nil), ("upstream", GrokBillingClient.Failure.upstreamUnavailable), ("network", .network)] {
            try mode.write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
            try "0".write(to: root.appendingPathComponent("attempts"), atomically: true, encoding: .utf8)
            do {
                let value = try GrokBillingClient().fetch(executable: fixture, home: root, timeout: 5)
                expect(failure == nil && value.remainingPercent == 99, "transient upstream error recovers with real quota")
            } catch { expect(error as? GrokBillingClient.Failure == failure, "upstream/network error classification") }
            let attempts = try String(contentsOf: root.appendingPathComponent("attempts"), encoding: .utf8)
            expect(attempts == "3", "read-only retries are bounded at three attempts")
        }
        print("PASS Grok core: \(checks) checks")
    }
}
