import Foundation

@main
enum CodexSharedQuestionTests {
    typealias JSON = [String: Any]
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError("FAIL: " + message) }
    }
    final class Fixture {
        var loaded = true, direct = true, source = "cli", turn = "turn-1", status = "inProgress"
        var items: [JSON] = [["type": "agentMessage", "id": "q1", "questions": [["title": "继续吗？", "options": ["继续", "停止"]]]]]
        var writes: [JSON] = []
        var rejectWrite = false, confirm = true, mismatchReceipt = false, badPage = false
        var nextCursor: String?
        func call(_ method: String, _ params: JSON) throws -> JSON {
            switch method {
            case "thread/loaded/list": return ["data": loaded ? ["thread"] : []]
            case "thread/read": return ["thread": ["id": "thread", "source": source, "canAcceptDirectInput": direct, "status": ["type": "active"]]]
            case "thread/turns/list": return ["data": [["id": turn, "status": status, "startedAt": 1.0]]]
            case "thread/items/list":
                var result: JSON = ["data": items.reversed().map { ["turnId": badPage ? "foreign" : turn, "item": $0] as JSON }]
                if let nextCursor { result["nextCursor"] = nextCursor }
                return result
            case "turn/steer":
                writes.append(params)
                if rejectWrite { throw CodexProxyTransport.Failure.unavailable }
                if confirm { items.append(["id": "reply", "type": "userMessage", "content": params["input"]!]) }
                return ["turnId": mismatchReceipt ? "foreign" : turn]
            default: throw CodexProxyTransport.Failure.protocolViolation
            }
        }
    }
    static func engine(_ fixture: Fixture) -> CodexSharedQuestionEngine { .init(request: fixture.call) }
    static func snapshot(_ engine: CodexSharedQuestionEngine) throws -> CodexSharedQuestionSnapshot {
        guard let value = try engine.poll(threadIDs: ["thread"])["thread"] else { fatalError("missing question") }
        return value
    }
    static func main() throws {
        if CommandLine.arguments.contains("--live") {
            let transport = try CodexProxyTransport(executable: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex"))
            defer { transport.close() }
            let engine = CodexSharedQuestionEngine { try transport.request($0, $1) }
            let result = try engine.poll(threadIDs: engine.loadedIDs())
            print("Read-only production engine: \(result.count) sessions, \(result.values.reduce(0) { $0 + $1.pending.count }) pending questions")
            if !result.isEmpty {
                let service = SessionActivityService()
                var locals: [LocalSessionSnapshot] = []
                let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").path + "/"
                for id in result.keys {
                    let metadata = try transport.request("thread/read", ["threadId": id, "includeTurns": false])
                    if let thread = metadata["thread"] as? JSON, let path = thread["path"] as? String, path.hasPrefix(root),
                       let local = service.readSnapshot(from: URL(fileURLWithPath: path)) { locals.append(local) }
                }
                let runtime = CodexSharedQuestions()
                runtime.observe(locals)
                let deadline = Date().addingTimeInterval(12)
                while runtime.snapshots.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
                let merged = runtime.merge(locals)
                let projects = ProjectActivityAggregator.projects(snapshots: merged, catalog: .empty)
                var state = ActivitySessionState()
                state.update(projects: projects, snapshots: merged, usages: [:], now: Date(), completionHold: 15)
                let rows = state.rows.filter { $0.waitReason == .userInput && $0.replyRequestIDs.contains(where: { $0.hasPrefix("shared:") }) }
                expect(!rows.isEmpty, "live read-only pipeline exposes an answerable island row")
                print("Read-only production island model: \(rows.count) waiting-for-input rows with shared request identities")
            }
            return
        }
        let f = Fixture(), e = engine(f), s = try snapshot(e)
        expect(s.pending.count == 1, "reads native pending question")
        expect(s.pending[0].options == ["继续", "停止"], "preserves options")
        expect(f.writes.isEmpty, "poll never writes")
        let answers = [s.pending[0].questionItemID: "自定义回答"]
        let delivered = try e.submit(s, answers: answers)
        expect(delivered.contains("确认送达"), "requires exact native accepted answer")
        expect(f.writes.count == 1, "one write on explicit action")
        expect(f.writes[0]["expectedTurnId"] as? String == "turn-1", "atomic active-turn precondition")
        expect(try e.poll(threadIDs: ["thread"]).isEmpty, "answered question disappears")
        _ = try e.submit(s, answers: answers)
        expect(f.writes.count == 1, "no duplicate write")
        for mode in ["unloaded", "foreign", "changed", "completed", "disabled", "subagent"] {
            let f = Fixture(), e = engine(f), s = try snapshot(e)
            switch mode {
            case "unloaded": f.loaded = false
            case "foreign": f.turn = "new-turn"
            case "changed": f.items[0]["questions"] = [["title": "不同的问题", "options": []]]
            case "completed": f.status = "completed"
            case "disabled": f.direct = false
            default: f.source = "subagent"
            }
            _ = try e.submit(s, answers: [s.pending[0].questionItemID: "继续"])
            expect(f.writes.isEmpty, "reject stale request: " + mode)
        }
        let other = engine(Fixture())
        _ = try other.submit(s, answers: answers)
        expect(other.uncertainSubmissions.isEmpty, "reject old connection epoch")
        for mode in ["timeout", "no-confirmation", "bad-receipt"] {
            let f = Fixture(), e = engine(f), s = try snapshot(e)
            f.rejectWrite = mode == "timeout"; f.confirm = false; f.mismatchReceipt = mode == "bad-receipt"
            let message = try e.submit(s, answers: [s.pending[0].questionItemID: "继续"])
            expect(!message.contains("确认送达"), "never invent delivery: " + mode)
            _ = try e.submit(s, answers: [s.pending[0].questionItemID: "继续"])
            expect(f.writes.count == 1, "no resend after uncertain outcome: " + mode)
        }
        for value in ["", " \n ", String(repeating: "字", count: 4001)] {
            do { _ = try CodexSharedQuestionEngine.replyText(s.pending, answers: [s.pending[0].questionItemID: value]); fatalError("invalid answer accepted") }
            catch { checks += 1 }
        }
        do { _ = try CodexSharedQuestionEngine.replyText(s.pending, answers: [:]); fatalError("missing answer") } catch { checks += 1 }
        let escaped = try CodexSharedQuestionEngine.replyText(s.pending, answers: [s.pending[0].questionItemID: "引号\"与\n换行"])
        expect(escaped.contains("\\\""), "answer is JSON encoded")
        for mode in ["foreign-page", "cursor-loop"] {
            let f = Fixture(), e = engine(f)
            f.badPage = mode == "foreign-page"; f.nextCursor = mode == "cursor-loop" ? "loop" : nil
            do { _ = try snapshot(e); fatalError("invalid page accepted") } catch { checks += 1 }
        }
        let completed = Fixture(); completed.status = "completed"
        let ce = engine(completed), cs = try snapshot(ce)
        expect(cs.pending.count == 1, "completed-turn question can be shown with fallback")
        _ = try ce.submit(cs, answers: [cs.pending[0].questionItemID: "继续"])
        expect(completed.writes.isEmpty, "never start a new turn implicitly")
        let multiple = Fixture()
        multiple.items[0]["questions"] = [["title": "第一题", "options": []], ["title": "第二题", "options": ["A"]]]
        let me = engine(multiple), ms = try snapshot(me)
        expect(ms.pending.count == 2, "multiple questions keep separate IDs")
        let ma = Dictionary(uniqueKeysWithValues: ms.pending.map { ($0.questionItemID, "回答") })
        expect(try me.submit(ms, answers: ma).contains("确认送达"), "multiple answers confirmed together")
        print("Shared Codex question tests: \(checks) passed")
    }
}
