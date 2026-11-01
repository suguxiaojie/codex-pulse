import Foundation
import Darwin

@main struct GrokQuestionTests {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; if !value { fatalError("Grok interaction: " + message) } }
    final class Box: @unchecked Sendable {
        let lock = NSLock(); var value = GrokSharedClient.Snapshot()
        func put(_ v: GrokSharedClient.Snapshot) { lock.lock(); value = v; lock.unlock() }
        func get() -> GrokSharedClient.Snapshot { lock.lock(); defer { lock.unlock() }; return value }
    }
    static func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition() && Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        expect(condition(), "expected asynchronous transport state")
    }
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sid = UUID().uuidString
        let nativeInfo: [String: Any] = ["result": ["result": ["sessionId": sid, "cwd": "/fixture", "turns": 1]]]
        expect(GrokSharedClient.confirmsSession(nativeInfo, id: sid, cwd: "/fixture"), "official ExtMethodResult wrapper and flattened SessionInfoResponse")
        expect(!GrokSharedClient.confirmsSession(nativeInfo, id: sid, cwd: "/other"), "mismatched cwd is not subscribed")
        expect(!GrokSharedClient.confirmsSession(["result": ["result": [:]]], id: sid, cwd: "/fixture"), "real empty resident lookup is not a session")
        expect(!GrokSharedClient.confirmsSession(["result": ["success": true, "data": ["sessionId": sid, "cwd": "/fixture"]]], id: sid, cwd: "/fixture"), "incorrect guessed envelope rejected")
        func tool(_ id: String = "tool", turn: String = "turn") -> [String: Any] {
            ["method": "session/update", "params": ["sessionId": sid, "_meta": ["promptId": turn], "update": ["sessionUpdate": "tool_call", "toolCallId": id]]]
        }
        let params: [String: Any] = ["sessionId": sid, "toolCallId": "tool", "mode": "default", "questions": [
            ["question": "选择？", "multiSelect": true, "options": [["label": "A, B", "description": "含逗号"], ["label": "C", "description": "第二项"]]]]]
        let question: [String: Any] = ["jsonrpc": "2.0", "id": "native-1", "method": "_x.ai/ask_user_question", "params": params]
        var state = GrokQuestionState(); state.allowedSessions = [sid]
        state.consume(question); expect(state.requests.isEmpty, "question without current tool/turn evidence is not actionable")
        state.consume(tool()); state.consume(question)
        expect(state.requests.count == 1, "native question with matching tool and turn")
        let request = state.requests.values.first!
        expect(request.turnID == "turn", "bound turn")
        expect(request.response(selections: ["选择？": ["A, B", "C"]], texts: [:])?["answers"] as? [String: [String]] == ["选择？": ["A, B", "C"]], "commas preserved in multi-select labels")
        expect(request.response(selections: [:], texts: ["选择？": "中文回答\n第二行"]) != nil, "free text and newlines")
        for selections in [["选择？": ["invalid"]], ["选择？": ["C", "C"]], ["extra": ["C"]], [:]] {
            expect(request.response(selections: selections, texts: [:]) == nil, "invalid or missing selection rejected")
        }
        expect(request.response(selections: [:], texts: ["选择？": "   "]) == nil, "blank text rejected")
        expect(request.response(selections: ["选择？": ["C"]], texts: ["选择？": "mixed"]) == nil, "mixed text and choice rejected")
        expect(request.response(selections: [:], texts: ["选择？": String(repeating: "文", count: 4001)]) == nil, "oversized answer rejected")
        let reply = state.submit(request, selections: ["选择？": ["C"]], texts: [:])!
        expect(reply["id"] as? String == "native-1", "original RPC identity preserved")
        expect(state.submit(request, selections: ["选择？": ["C"]], texts: [:]) == nil, "first submit locks retry")
        state.consume(question); expect(state.submit(request, selections: ["选择？": ["C"]], texts: [:]) == nil, "duplicate wire request cannot unlock submit")
        state.reset(); state.allowedSessions = [sid]; state.consume(tool()); state.consume(question)
        expect(state.submit(request, selections: ["选择？": ["C"]], texts: [:]) == nil, "old connection epoch rejected")
        let fresh = state.requests.values.first!
        state.consume(["method": "_x.ai/session_notification", "params": ["sessionId": sid, "update": ["sessionUpdate": "interaction_resolved", "tool_call_id": "tool"]]])
        expect(state.requests.isEmpty && state.submit(fresh, selections: ["选择？": ["C"]], texts: [:]) == nil, "terminal first answer revokes island control")
        state.consume(question); expect(state.requests.isEmpty, "resolved duplicate not replayed")
        state.reset(); state.allowedSessions = [sid]; state.consume(tool()); state.consume(question); state.consume(tool("next", turn: "new-turn"))
        state.consume(["method": "session/update", "params": ["sessionId": sid, "update": ["sessionUpdate": "turn_completed", "prompt_id": "turn"]]])
        state.consume(tool()); expect(state.requests.isEmpty, "retired turn cannot resurrect after new turn")
        var bad = question; bad["id"] = true
        expect(GrokQuestionRequest.decode(bad, epoch: UUID(), turnID: "turn") == nil, "boolean RPC id rejected")
        bad = question; bad["method"] = "_x.ai/ask_user_question_"
        expect(GrokQuestionRequest.decode(bad, epoch: UUID(), turnID: "turn") == nil, "method must match exactly")
        var permission: [String: Any] = ["jsonrpc": "2.0", "id": 9, "method": "session/request_permission", "params": [
            "sessionId": sid, "toolCall": ["toolCallId": "tool", "title": "运行命令", "rawInput": ["command": "echo fixture"]],
            "options": [["optionId": "opaque-once", "kind": "allow_once"], ["optionId": "opaque-deny", "kind": "reject_once"], ["optionId": "opaque-always", "kind": "allow_always"]]]]
        state.reset(); state.allowedSessions = [sid]; state.consume(tool()); state.consume(permission)
        let approval = state.requests.values.first!
        expect(approval.permission?.allowOnce == "opaque-once" && approval.questions.isEmpty, "permission distinct from question")
        expect(approval.permission?.response("always") == nil, "persistent grants never synthesized")
        let decision = state.submit(approval, action: "once", selections: [:], texts: [:])!
        let selected = (decision["result"] as? [String: Any])?["outcome"] as? [String: String]
        expect(selected == ["outcome": "selected", "optionId": "opaque-once"], "ACP permission result uses exact native option ID")
        expect(approval.permission?.response("deny") != nil, "explicit deny supported")
        permission["method"] = "_x.ai/exit_plan_mode"
        expect(GrokQuestionRequest.decode(permission, epoch: UUID(), turnID: "turn") == nil, "plan approval is not tool permission")
        expect(GrokLauncher.sharedSocket(home: directory).lastPathComponent == "leader.sock", "automatic mode uses the official default endpoint")
        do { _ = try GrokLauncher.enable(home: URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 110))); expect(false, "overlong native socket refused before config write") }
        catch { expect(error as? GrokLauncher.Failure == .unsupported, "automatic setup cannot break native socket startup") }
        for input in [nil, "", "# existing\n", "[models]\ndefault = 'fixture'\n", "[cli]\nother = 1\n", "cli.other = 1\n[models]\ndefault='fixture'\n"] as [String?] {
            let data = input.map { Data($0.utf8) }, plan = try GrokLauncher.plan(data)
            expect(plan.changed && plan.previous == nil, "absent shared flag is inserted")
            expect(try GrokLauncher.plan(plan.updated).previous == true, "inserted shared flag recognized")
        }
        let original = Data("# keep\r\n[cli] # table\r\n  use_leader = false # retain comment\r\n[model.fixture]\nvalue = 'metadata'\n".replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let edited = try GrokLauncher.plan(original)
        expect(edited.updated == Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "use_leader = false", with: "use_leader = true").utf8), "only boolean changes; comments, CRLF and other settings preserved")
        let dotted = try GrokLauncher.plan(Data("cli.use_leader=false # keep\n".utf8))
        expect(String(decoding: dotted.updated, as: UTF8.self) == "cli.use_leader=true # keep\n", "root dotted key preserved")
        for bad in ["[cli]\nuse_leader='false'", "[cli]\nuse_leader=false\nuse_leader=true", "[cli]\n[cli]\n", "cli={use_leader=false}", "value='''multiline'''\n"] {
            do { _ = try GrokLauncher.plan(Data(bad.utf8)); expect(false, "ambiguous settings refused") }
            catch { expect(error as? GrokLauncher.Failure == .unsupported, "unsupported TOML fails closed") }
        }
        // Native Unix sockets require a short home path; only these OS-specific fixtures use /tmp.
        let settingsRoot = URL(fileURLWithPath: "/tmp/gpcs-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: settingsRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: settingsRoot) }
        let settingsHome = settingsRoot.appendingPathComponent("settings")
        try FileManager.default.createDirectory(at: settingsHome, withIntermediateDirectories: true)
        let config = settingsHome.appendingPathComponent("config.toml")
        let configData = Data("[cli]\nuse_leader = false\n[model.fixture]\nvalue = 'keep-private-model-setting'\n".utf8)
        try configData.write(to: config)
        let originalMode = (try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as! NSNumber).intValue
        let applied = try GrokLauncher.enable(home: settingsHome)
        expect(applied.changed && applied.backupURL != nil, "one-time setup records previous setting")
        expect(try GrokLauncher.isEnabled(home: settingsHome), "atomic setup readback")
        let backupData = try Data(contentsOf: applied.backupURL!)
        expect(!String(decoding: backupData, as: UTF8.self).contains("keep-private-model-setting"), "backup does not copy other settings or credentials")
        expect(GrokJSON.object(backupData)?["previousValue"] as? Bool == false, "backup preserves original boolean")
        let resultingMode = (try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as! NSNumber).intValue
        expect(resultingMode == originalMode, "configuration mode is preserved during atomic replacement")
        expect((try FileManager.default.attributesOfItem(atPath: applied.backupURL!.path)[.posixPermissions] as! NSNumber).intValue == 0o600, "setting backup is private")
        expect(try GrokLauncher.enable(home: settingsHome).changed == false, "already-enabled setup is byte-preserving and idempotent")
        try configData.write(to: config)
        do {
            _ = try GrokLauncher.enable(home: settingsHome, beforeCommit: { try! Data("# concurrent edit\n".utf8).write(to: config) })
            expect(false, "concurrent config edit rejected")
        } catch { expect(error as? GrokLauncher.Failure == .concurrentChange, "concurrent edit not overwritten") }
        expect(try String(contentsOf: config, encoding: .utf8) == "# concurrent edit\n", "new user data retained")
        let linkHome = settingsRoot.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linkHome, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkHome.appendingPathComponent("config.toml"), withDestinationURL: config)
        do { _ = try GrokLauncher.enable(home: linkHome); expect(false, "symlink settings refused") }
        catch { expect(error as? GrokLauncher.Failure == .unreadable, "symlink not replaced") }

        let socketFolder = URL(fileURLWithPath: "/tmp/gpq-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: socketFolder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: socketFolder) }
        let socketURL = socketFolder.appendingPathComponent("leader.sock"), resultURL = directory.appendingPathComponent("server-result.json")
        let script = directory.appendingPathComponent("fixture.py")
        try """
        import socket,struct,json,sys,os
        s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);os.chmod(sys.argv[1],0o600);s.listen(1);c,_=s.accept();sid=sys.argv[3]
        def get(n):
            b=b''
            while len(b)<n:
                v=c.recv(n-len(b))
                if not v:raise EOFError()
                b+=v
            return b
        def read():return json.loads(get(struct.unpack('>I',get(4))[0]))
        def send(a):
            b=json.dumps(a).encode();c.sendall(struct.pack('>I',len(b))+b)
        def acp(a):send({'type':'acp','payload':json.dumps(a)})
        r=read();assert r['type']=='register' and not r['capabilities']['yolo_mode']
        send({'type':'registered','ready':True,'leader_protocol_version':1})
        r=json.loads(read()['payload']);assert r['method']=='_x.ai/session/info'
        acp({'jsonrpc':'2.0','id':r['id'],'result':{'result':{'sessionId':sid,'cwd':'/fixture','turns':1}}})
        def tool(id):acp({'method':'session/update','params':{'sessionId':sid,'_meta':{'promptId':'live-turn'},'update':{'sessionUpdate':'tool_call','toolCallId':id}}})
        tool('q');acp({'jsonrpc':'2.0','id':101,'method':'_x.ai/ask_user_question','params':{'sessionId':sid,'toolCallId':'q','questions':[{'question':'Q?','options':[{'label':'A, B'},{'label':'C'}],'multiSelect':True}]}})
        answer=json.loads(read()['payload']);assert answer['id']==101 and answer['result']['answers']['Q?']==['A, B','C']
        acp({'method':'_x.ai/session_notification','params':{'sessionId':sid,'update':{'sessionUpdate':'interaction_resolved','tool_call_id':'q'}}})
        tool('p');acp({'jsonrpc':'2.0','id':102,'method':'session/request_permission','params':{'sessionId':sid,'toolCall':{'toolCallId':'p','title':'Echo','rawInput':{'command':'echo fixture'}},'options':[{'optionId':'exact-once','kind':'allow_once'}]}})
        approval=json.loads(read()['payload']);assert approval['id']==102 and approval['result']['outcome']['optionId']=='exact-once'
        tool('pending');acp({'jsonrpc':'2.0','id':103,'method':'_x.ai/ask_user_question','params':{'sessionId':sid,'toolCallId':'pending','questions':[{'question':'Leave pending?','options':[]}]}})
        trailing=b''
        while True:
            x=c.recv(65536)
            if not x:break
            trailing+=x
        assert not trailing,'disconnect must not send cancelled or duplicate responses'
        open(sys.argv[2],'w').write(json.dumps({'question':answer,'permission':approval,'disconnectDidNotCancel':True}))
        """.write(to: script, atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["python3", script.path, socketURL.path, resultURL.path, sid]
        process.standardError = FileHandle.standardError; try process.run()
        try await wait { FileManager.default.fileExists(atPath: socketURL.path) }
        let client = GrokSharedClient(socketURL: socketURL), box = Box()
        client.onSnapshot = { box.put($0) }; client.updateSessions([sid: "/fixture"]); client.start()
        try await wait { box.get().requests.first?.toolCallID == "q" }
        let nativeQuestion = box.get().requests.first!
        _ = await client.submit(nativeQuestion, selections: ["Q?": ["A, B", "C"]], texts: [:])
        try await wait { box.get().requests.contains { $0.toolCallID == "p" } }
        let nativePermission = box.get().requests.first { $0.toolCallID == "p" }!
        _ = await client.submit(nativePermission, action: "once", selections: [:], texts: [:])
        try await wait { box.get().requests.contains { $0.toolCallID == "pending" } }
        client.stop()
        try await wait { FileManager.default.fileExists(atPath: resultURL.path) }
        process.waitUntilExit(); expect(process.terminationStatus == 0, "native-shaped frame round trip and disconnect fallback")
        if let socket = ProcessInfo.processInfo.environment["GROK_OFFICIAL_TEST_SOCKET"] {
            let official = GrokSharedClient(socketURL: URL(fileURLWithPath: socket)), observed = Box()
            official.onSnapshot = { observed.put($0) }; official.updateSessions([sid: "/fixture"]); official.start()
            try await wait { observed.get().status.contains("已连接") }
            expect(observed.get().requests.isEmpty, "official CLI handshake does not create a model session")
            official.stop(); print("Official Grok 1.0.70 shared handshake passed")
        }
        print("PASS Grok question/permission: \(checks) checks; framed round trips and no cancel-on-disconnect")
    }
}
