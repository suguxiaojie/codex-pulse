import Foundation
import Darwin

@main enum ClaudeCodeTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ title: String) {
        checks += 1
        if !condition { fatalError("Claude check failed: " + title) }
    }
    static func json(_ value: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    static func line(_ value: [String: Any]) -> Data { var result = json(value); result.append(10); return result }
    static func response(_ id: String, output: Int = 20, model: String = "claude-sonnet-5-5") -> [String: Any] {
        ["type": "assistant", "requestId": "request-" + id, "timestamp": "2026-10-21T12:00:00Z",
         "message": ["id": id, "model": model, "content": [], "usage": ["input_tokens": 100, "output_tokens": output, "cache_read_input_tokens": 50]]]
    }
    static func completionEvidenceTests() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func record(_ reason: String, at offset: Double, tool: Bool = false) -> Data {
            json(["type": "assistant", "timestamp": ISO8601DateFormatter().string(from: start.addingTimeInterval(offset)),
                  "message": ["id": "end", "stop_reason": reason, "content": tool
                    ? [["type": "tool_use", "id": "t", "name": "Bash"]]
                    : [["type": "text", "text": "Finished"]]]])
        }
        for reason in ["end_turn", "stop_sequence", "max_tokens"] {
            let line = record(reason, at: 2)
            let records = ClaudeCodeTranscriptDecoder.records(line)
            expect(records.contains(.turnEnded(interrupted: false, timestamp: start.addingTimeInterval(2))), "terminal stop reason: " + reason)
            var evidence = ClaudeTranscriptCompletionEvidence()
            evidence.consume(records, at: start.addingTimeInterval(2), since: start)
            expect(evidence.terminal(after: start, now: start.addingTimeInterval(5)) == nil, "five-second grace is strict")
            expect(evidence.terminal(after: start, now: start.addingTimeInterval(6))?.interrupted == false, "fresh terminal evidence completes")
            expect(evidence.assistantText == "Finished", "final assistant text retained")
            expect(evidence.terminal(after: start.addingTimeInterval(3), now: start.addingTimeInterval(10)) == nil, "later Hook supersedes old ending")
            evidence.consume([.toolUse(id: "new", name: "Bash", input: "")], at: start.addingTimeInterval(3), since: start)
            expect(evidence.terminal(after: start, now: start.addingTimeInterval(6)) == nil, "later tool invalidates completion")
        }
        expect(!ClaudeCodeTranscriptDecoder.records(record("tool_use", at: 2)).contains { if case .turnEnded = $0 { return true }; return false }, "nonterminal reason cannot finish")
        expect(!ClaudeCodeTranscriptDecoder.records(record("end_turn", at: 2, tool: true)).contains { if case .turnEnded = $0 { return true }; return false }, "same-message tool conservatively blocks terminal")
        let interrupted = ClaudeCodeTranscriptDecoder.records(json(["type": "user", "timestamp": ISO8601DateFormatter().string(from: start.addingTimeInterval(2)),
            "message": ["content": "[Request interrupted by user for tool use]"]]))
        var evidence = ClaudeTranscriptCompletionEvidence()
        evidence.consume(interrupted, at: start.addingTimeInterval(2), since: start)
        expect(evidence.terminal(after: start, now: start.addingTimeInterval(6))?.interrupted == true, "interrupt produces cancelled evidence")
        evidence = .init()
        evidence.consume(ClaudeCodeTranscriptDecoder.records(record("end_turn", at: -1)), at: start.addingTimeInterval(-1), since: start)
        expect(evidence.terminal(after: start, now: start.addingTimeInterval(6)) == nil, "pre-turn history excluded")
        evidence.consume(interrupted, at: nil, since: start)
        expect(evidence.terminal(after: start, now: start.addingTimeInterval(6)) == nil, "missing timestamp cannot prove completion")
        evidence.consume(interrupted, at: start.addingTimeInterval(2), since: start)
        evidence.consume([.userPrompt("next")], at: start.addingTimeInterval(3), since: start)
        expect(evidence.terminal(after: start, now: start.addingTimeInterval(6)) == nil, "later prompt invalidates old ending")
        print("Claude completion evidence: \(checks) checks passed")
    }

    static func liveRegistryTests() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/claude-registry-tests/\(UUID().uuidString)")
        let registryURL = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: registryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(3600)
        let id = UUID().uuidString.lowercased()
        let reader = ClaudeLiveSessionRegistry(configurationDirectory: root)
        let process = ClaudeLiveSessionRegistry.ProcessInfo(name: "claude", startedAt: start, uid: getuid())
        var object: [String: Any] = ["pid": 101, "pidDomain": "darwin", "kind": "interactive",
            "sessionId": id, "cwd": "/fixture", "procStart": ClaudeLiveSessionRegistry.processStamp(start),
            "status": "busy", "statusUpdatedAt": start.addingTimeInterval(1).timeIntervalSince1970 * 1000]
        let file = registryURL.appendingPathComponent("101.json")
        func write(_ value: [String: Any]) throws { try json(value).write(to: file) }
        try write(object)
        expect(reader.read(now: now, lookup: { _ in process }).first?.status == "busy", "long-running owned busy registry remains valid")
        object["status"] = "idle"; try write(object)
        expect(reader.read(now: now, lookup: { _ in process }).first?.status == "idle", "idle status stays distinct from busy")
        object["status"] = "busy"; try write(object)
        expect(reader.read(now: now, lookup: { _ in nil }).isEmpty, "dead PID cannot restore a session")
        expect(reader.read(now: now, lookup: { _ in .init(name: "claude", startedAt: start.addingTimeInterval(1), uid: getuid()) }).isEmpty,
            "reused PID with a different start time is rejected")
        expect(reader.read(now: now, lookup: { _ in .init(name: "sh", startedAt: start, uid: getuid()) }).isEmpty,
            "shell is not a Claude owner")
        expect(reader.read(now: now, lookup: { _ in .init(name: "claude", startedAt: start, uid: getuid() + 1) }).isEmpty,
            "foreign UID is rejected")
        for (key, value) in [("kind", "subagent" as Any), ("pidDomain", "linux"), ("pid", 102),
                             ("sessionId", "../escape"), ("cwd", "relative"), ("statusUpdatedAt", true),
                             ("statusUpdatedAt", now.addingTimeInterval(60).timeIntervalSince1970 * 1000)] {
            var invalid = object; invalid[key] = value; try write(invalid)
            expect(reader.read(now: now, lookup: { _ in process }).isEmpty, "invalid registry field rejected: " + key)
        }
        try write(object)
        let project = root.appendingPathComponent("projects/project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let transcript = project.appendingPathComponent(id + ".jsonl")
        try Data().write(to: transcript)
        expect(reader.read(includeTranscripts: true, now: now, lookup: { _ in process }).first?.transcriptPath == transcript.path,
            "exact session transcript is discovered without scanning its contents")
        var duplicate = object; duplicate["pid"] = 102
        let duplicateURL = registryURL.appendingPathComponent("102.json")
        try json(duplicate).write(to: duplicateURL)
        expect(reader.read(now: now, lookup: { _ in process }).isEmpty, "multiple owners of one session are ambiguous")
        try FileManager.default.removeItem(at: duplicateURL)
        try Data(repeating: 32, count: 65_537).write(to: file)
        expect(reader.read(now: now, lookup: { _ in process }).isEmpty, "oversized registry entry is bounded")
        try FileManager.default.removeItem(at: file)
        let outside = root.appendingPathComponent("outside.json"); try json(object).write(to: outside)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        expect(reader.read(now: now, lookup: { _ in process }).isEmpty, "registry symlink cannot escape its directory")
    }
    static func main() async throws {
        try liveRegistryTests()
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--scan" {
            let scanner = ClaudeCodeUsageScanner(projectsURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            var result = await scanner.scan()
            for _ in 0..<40 where !result.complete { result = await scanner.scan() }
            print("Claude real logs: files=\(result.fileCount), days=\(result.days.count), tokens=\(result.lifetimeTokens), complete=\(result.complete), unpricedDays=\(result.days.filter { $0.estimatedCost == nil }.count)")
            return
        }
        completionEvidenceTests()
        if CommandLine.arguments.contains("--completion-only") { return }
        let root = URL(fileURLWithPath: "/tmp/claude-pulse-test-" + String(UUID().uuidString.prefix(8)), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        expect(ClaudeCodeTokenUsage(usage: ["input_tokens": true]) == nil, "boolean counter rejected")
        expect(ClaudeCodeTokenUsage(usage: ["input_tokens": -1]) == nil, "negative counter rejected")
        expect(ClaudeCodeTokenUsage(usage: ["input_tokens": 1.1]) == nil, "fractional counter rejected")
        expect(ClaudeCodeTokenUsage(usage: ["input_tokens": NSNumber(value: UInt64.max)]) == nil, "overflow rejected")
        expect(ClaudeCodeTokenUsage(usage: ["cache_creation": ["ephemeral_1h_input_tokens": -1]]) == nil, "bad cache split rejected")
        expect(ClaudeCodeTokenUsage(usage: ["cache_creation_input_tokens": 8, "cache_creation": ["ephemeral_5m_input_tokens": 3, "ephemeral_1h_input_tokens": 5]])?.total == 8, "cache split does not double count")
        // Inconsistent splits retain the authoritative total instead of dropping usage.
        expect(ClaudeCodeTokenUsage(usage: ["cache_creation_input_tokens": 8, "cache_creation": ["ephemeral_5m_input_tokens": 3]])?.cacheWrite5m == 8, "inconsistent split preserves total")
        let clamped = ClaudeCodeTokenUsage(usage: ["cache_creation_input_tokens": 8, "cache_creation": ["ephemeral_5m_input_tokens": 3, "ephemeral_1h_input_tokens": 12]])!
        expect(clamped.total == 8 && clamped.cacheWrite1h == 8 && clamped.cacheWrite5m == 0, "long cache split clamps to total")
        let repaired = ClaudeCodeTokenUsage(usage: ["cache_creation_input_tokens": 8, "cache_creation": ["ephemeral_5m_input_tokens": 1, "ephemeral_1h_input_tokens": 3]])!
        expect(repaired.total == 8 && repaired.cacheWrite1h == 3 && repaired.cacheWrite5m == 5, "short cache split takes remainder")
        let standard = ClaudeCodeTokenUsage(input: 100_001, output: 20, cacheWrite5m: 30, cacheWrite1h: 40, cacheRead: 50)
        var fast = standard; fast.speed = "fast"
        for model in ["claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"] {
            expect(ClaudeCodePricing.cost(model: model, usage: fast) == ClaudeCodePricing.cost(model: model, usage: standard)! * 2, "fast doubles all rates: " + model)
        }
        expect(ClaudeCodePricing.cost(model: "claude-sonnet-5-5", usage: fast) == nil, "unsupported fast is unknown")
        fast.speed = "turbo"
        expect(ClaudeCodePricing.cost(model: "claude-opus-5-5", usage: fast) == nil, "unknown speed is unknown")
        var us = standard; us.inferenceGeo = "us"
        for model in ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-5-5", "claude-fable-5-1", "claude-mythos-5"] {
            expect(ClaudeCodePricing.cost(model: model, usage: us) == ClaudeCodePricing.cost(model: model, usage: standard)! * 1.1, "US residency including long Haiku: " + model)
        }
        expect(ClaudeCodePricing.cost(model: "claude-opus-4-5", usage: us) == nil, "old model US residency unknown")
        us.inferenceGeo = "eu"
        expect(ClaudeCodePricing.cost(model: "claude-opus-5-5", usage: us) == nil, "unknown geo is unknown")
        var explicit = standard; explicit.speed = "standard"; explicit.inferenceGeo = "global"
        expect(ClaudeCodePricing.cost(model: "claude-opus-5-5", usage: explicit) == ClaudeCodePricing.cost(model: "claude-opus-5-5", usage: standard), "default equals explicit standard global")
        let decoded = ClaudeCodeTranscriptDecoder.records(json(["type": "assistant", "message": ["id": "priced", "model": "claude-opus-5-5", "usage": ["speed": "fast", "inference_geo": "us", "cache_creation_input_tokens": 8, "cache_creation": ["ephemeral_1h_input_tokens": 3]]]]))
        if case .usage(_, _, let value, _) = decoded.first {
            expect(value.speed == "fast" && value.inferenceGeo == "us" && value.total == 8, "transcript preserves pricing context and cache total")
            expect((value + value).total == 16, "pricing context does not alter token addition")
        } else { fatalError("usage record missing") }
        expect(ClaudeCodePricing.rates(for: "claude-sonnet-5-5")?.cacheRead == 0.1, "current Sonnet 5.5 cache rate")
        expect(ClaudeCodePricing.rates(for: "claude-sonnet-99") == nil, "unknown future model has no guessed price")
        expect(ClaudeCodePricing.cost(model: "claude-haiku-5-5", usage: .init(input: 100_001)) == 100_001 * 0.5 / 1_000_000, "Haiku long input tier")
        let privateBlocks = json(["type": "assistant", "message": ["id": "x", "content": [["type": "thinking", "thinking": "private"]]]])
        expect(ClaudeCodeTranscriptDecoder.records(privateBlocks).isEmpty, "private reasoning excluded")
        expect(ClaudeCodeRateLimits.decode(snapshot: json(["capturedAt": 1, "rate_limits": ["five_hour": ["used_percentage": 101]]])) == nil, "invalid quota rejected")
        expect(ClaudeCodeRateLimits.decode(snapshot: json(["capturedAt": 1, "rate_limits": ["five_hour": ["used_percentage": true]]])) == nil, "boolean quota rejected")
        let limits = ClaudeCodeRateLimits.decode(snapshot: json(["capturedAt": 1, "rate_limits": ["five_hour": ["used_percentage": 25, "resets_at": 1_800_000_000_000]]]))
        expect(limits?.fiveHour?.remainingPercent == 75 && limits?.fiveHour?.resetsAt?.timeIntervalSince1970 == 1_800_000_000, "quota percentage and milliseconds")

        let projects = root.appendingPathComponent("projects"); try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let transcript = projects.appendingPathComponent("one.jsonl")
        try (line(response("a")) + line(response("a", output: 30))).write(to: transcript)
        let scanner = ClaudeCodeUsageScanner(projectsURL: projects)
        let first = await scanner.scan()
        expect(first.lifetimeTokens == 180 && first.complete, "streamed duplicate uses largest usage")
        try line(response("a", output: 30)).write(to: projects.appendingPathComponent("copy.jsonl"))
        let duplicate = await scanner.scan(); expect(duplicate.lifetimeTokens == 180, "cross-file dedup")
        try FileManager.default.removeItem(at: projects.appendingPathComponent("copy.jsonl"))
        let replacement = projects.appendingPathComponent("new.tmp")
        try line(response("b", model: "unknown")).write(to: replacement)
        _ = Darwin.rename(replacement.path, transcript.path)
        let replaced = await scanner.scan()
        expect(replaced.lifetimeTokens == 170 && replaced.days.first?.estimatedCost == nil, "replacement drops old cache and unknown prices stay unknown")
        try Data().write(to: transcript)
        let truncated = await scanner.scan(); expect(truncated.lifetimeTokens == 0, "truncated file removes usage")
        try line(response("c")).dropLast().write(to: transcript)
        let incomplete = await scanner.scan(); expect(incomplete.lifetimeTokens == 0, "partial line deferred")
        let handle = try FileHandle(forWritingTo: transcript); try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        let completed = await scanner.scan(); expect(completed.lifetimeTokens == 170, "partial line completes once")
        try FileManager.default.createSymbolicLink(at: projects.appendingPathComponent("linked.jsonl"), withDestinationURL: transcript)
        expect(ClaudeCodeTranscriptTail.headLines(projects.appendingPathComponent("linked.jsonl").path).isEmpty, "no-follow transcript")
        let budgeted = ClaudeCodeUsageScanner(projectsURL: projects, readBudgetBytes: 10)
        let partial = await budgeted.scan(); expect(!partial.complete, "budget exhaustion explicit")

        let helper = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = root.appendingPathComponent("config's"); try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let settings = config.appendingPathComponent("settings.json")
        let original: [String: Any] = ["theme": "dark", "hooks": ["Stop": [["hooks": [["type": "command", "command": "foreign-command"]]]]],
                                     "statusLine": ["type": "command", "command": "printf ORIGINAL", "padding": 2]]
        try json(original).write(to: settings)
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("b.sock"), authenticationToken: "fixture-only",
            configurationDirectory: config, supportDirectory: root.appendingPathComponent("support's"), helperURL: helper)
        try installer.install(.init(interactiveApprovals: true, statusLine: true))
        expect(installer.state().hooksInstalled && installer.state().statusLineInstalled, "install with quoted path")
        expect(FileManager.default.fileExists(atPath: settings.appendingPathExtension("codex-pulse-backup").path), "backup exists")
        // Preserve even noncanonical whitespace during an enabled route migration.
        let installedSettings = try Data(contentsOf: settings) + Data("\n\n".utf8)
        try installedSettings.write(to: settings)
        var oldRoute = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.routeURL)) as! [String: Any]
        oldRoute["decisionTimeoutSeconds"] = 3540
        try json(oldRoute).write(to: installer.routeURL)
        try installer.install(.init(interactiveApprovals: true, statusLine: true))
        expect(try Data(contentsOf: settings) == installedSettings, "enabled reinstall preserves settings bytes")
        let migratedRoute = try Data(contentsOf: installer.routeURL)
        expect((try JSONSerialization.jsonObject(with: migratedRoute) as? [String: Any])?["decisionTimeoutSeconds"] as? Int == 120, "route migrates to 120 seconds")
        let routeModified = try FileManager.default.attributesOfItem(atPath: installer.routeURL.path)[.modificationDate] as! Date
        try installer.install(.init(interactiveApprovals: true, statusLine: true))
        expect(try FileManager.default.attributesOfItem(atPath: installer.routeURL.path)[.modificationDate] as? Date == routeModified, "unchanged route is not rewritten")
        expect(ClaudeCodeInstaller.permissionTimeoutSeconds == 3600, "hook timeout remains unchanged")
        expect(installer.state().hooksInstalled, "idempotent install")
        expect(!installer.owns(installer.hookCommand + " ; echo changed"), "ownership rejects compound command")
        let bridge = ClaudeCodeBridge(socketURL: installer.socketURL, authenticationToken: installer.authenticationToken)
        try bridge.start(onMessage: { message in
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: ["behavior": "deny", "message": "fixture"]) }
        }, onDisconnect: { _ in })
        let permission: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "fixture", "tool_name": "Bash", "tool_input": ["command": "echo fixture"]]
        let output = try run(helper: installer.installedHelperURL, args: ["--claude-code", "--configuration", installer.routeURL.path], input: json(permission))
        let answer = try JSONSerialization.jsonObject(with: output) as! [String: Any]
        let decision = (answer["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        expect(decision?["behavior"] as? String == "deny", "real helper/bridge roundtrip returns explicit deny")
        let forwarded = try run(helper: installer.installedHelperURL, args: ["--claude-statusline", "--configuration", installer.routeURL.path], input: json(["rate_limits": ["five_hour": ["used_percentage": 42]]]))
        expect(String(decoding: forwarded, as: UTF8.self) == "ORIGINAL", "existing statusLine output forwarded")
        expect(ClaudeCodeRateLimits.decode(snapshot: try Data(contentsOf: installer.statusLineSnapshotURL))?.fiveHour?.remainingPercent == 58, "statusLine writes bounded usage")
        bridge.stop()
        expect(try run(helper: installer.installedHelperURL, args: ["--claude-code", "--configuration", installer.routeURL.path], input: json(permission)).isEmpty, "disconnected helper outputs no decision")
        try installer.uninstall()
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        expect(NSDictionary(dictionary: restored).isEqual(to: original), "uninstall restores foreign hooks and original statusLine")
        try Data("invalid".utf8).write(to: settings)
        do { try installer.install(.init(interactiveApprovals: false, statusLine: false)); fatalError("invalid settings accepted") } catch { checks += 1 }
        expect(try Data(contentsOf: settings) == Data("invalid".utf8), "invalid settings untouched")

        try json(["statusLine": "unrecognized"]).write(to: settings)
        do { try installer.install(.init(interactiveApprovals: false, statusLine: true)); fatalError("opaque statusLine overwritten") } catch { checks += 1 }
        expect((try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])?["statusLine"] as? String == "unrecognized", "opaque statusLine preserved")
        let request = ClaudePermissionRequest.decode(.init(eventID: "event", kind: "hook", awaitsDecision: true, payload: json(permission)), sessionID: "claude:fixture")!
        expect(request.decision(.once)?["behavior"] as? String == "allow", "once permission")
        expect(request.decision(.always) == nil, "no suggestions cannot persist broad permission")
        expect(request.decision(.cancel)?["interrupt"] as? Bool == true, "cancel interrupts")
        var question = permission; question["tool_name"] = "AskUserQuestion"
        question["tool_input"] = ["questions": [["question": "Choose?", "options": [["label": "A"]], "multiSelect": true]]]
        let multiple = ClaudePermissionRequest.decode(.init(eventID: "q", kind: "hook", awaitsDecision: true, payload: json(question)), sessionID: "claude:fixture")!
        expect(multiple.questions[0].multiSelect, "multi-select decoded")
        question["tool_input"] = ["questions": [["question": "Choose?", "options": [["label": "A"], ["label": "B"]]]], "preserved": "value"]
        let single = ClaudePermissionRequest.decode(.init(eventID: "q", kind: "hook", awaitsDecision: true, payload: json(question)), sessionID: "claude:fixture")!
        let updated = single.decision(.once, answers: ["Choose?": "B"])?["updatedInput"] as? [String: Any]
        expect(updated?["answers"] as? [String: String] == ["Choose?": "B"] && updated?["preserved"] as? String == "value", "single selection preserves original input and exact answers")
        expect(single.permitsIslandAnswers(["Choose?": "custom"]), "island permits custom answers")
        expect(!single.permitsIslandAnswers(["Choose?": " "]), "blank answer rejected")
        expect(!single.permitsIslandAnswers(["Choose?": "A", "extra": "B"]), "extra question rejected")
        expect(single.decision(.once, answers: ["Choose?": String(repeating: "a", count: 4001)]) == nil, "overlong answer rejected")
        question["hook_event_name"] = "PreToolUse"
        let pretool = ClaudePermissionRequest.decode(.init(eventID: "q", kind: "hook", awaitsDecision: true, payload: json(question)), sessionID: "claude:fixture")
        expect(pretool?.questions.count == 1, "ordinary question intercepted before tool execution")
        question["tool_name"] = "Bash"
        expect(ClaudePermissionRequest.decode(.init(eventID: "q", kind: "hook", awaitsDecision: true, payload: json(question)), sessionID: "claude:fixture") == nil, "ordinary pretool not an approval")
        expect(single.decision(.once, answers: ["Choose?": "custom"]) != nil, "detail window retains custom answers")
        print("Claude integration tests: \(checks) checks passed")
    }
    static func run(helper: URL, args: [String], input: Data) throws -> Data {
        let process = Process(); process.executableURL = helper; process.arguments = args
        let stdin = Pipe(), stdout = Pipe(); process.standardInput = stdin; process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run(); try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        expect(process.terminationStatus == 0, "helper exit zero")
        return data
    }
}
