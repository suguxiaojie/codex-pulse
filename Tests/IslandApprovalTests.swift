// Submission/lifecycle cases adapted from QuotaView f779531 (MIT).
import AppKit
import Foundation

@MainActor enum IslandApprovalTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do { if try !condition() { fatalError(message) } } catch { fatalError("\(message): \(error)") }
    }
    static func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func request(_ method: String = "item/commandExecution/requestApproval", params: [String: Any] = [:]) -> [String: Any] {
        ["id": 42, "method": method, "params": ["threadId": "conversation", "turnId": "turn", "command": "echo fixture"].merging(params) { _, new in new }]
    }
    static func state(_ requests: [[String: Any]], items: [[String: Any]] = []) -> [String: Any] {
        ["id": "conversation", "source": "appServer", "requests": requests, "turns": [["turnId": "turn", "status": "inProgress", "items": items]]]
    }
    static func fails(_ client: CodexDesktopIPCClient, _ handle: CodexDesktopIPCRequestHandle, _ response: Data, _ error: CodexDesktopIPCError) async {
        do { _ = try await client.submit(handle: handle, result: response); fatalError("expected \(error)") }
        catch let actual { expect(actual as? CodexDesktopIPCError == error, "expected \(error), got \(actual)") }
    }
    static func run() async throws {
        expect(!IslandAnswerEditor.canSynchronize(markedText: true), "IME composition blocks binding and measurement writes")
        expect(IslandAnswerEditor.canSynchronize(markedText: false), "committed text synchronizes")
        expect(!IslandAnswerEditor.shouldActivate(userClick: false, enabled: true), "refresh and programmatic focus never activate app")
        expect(!IslandAnswerEditor.shouldActivate(userClick: true, enabled: false), "disabled input never activates")
        expect(IslandAnswerEditor.shouldActivate(userClick: true, enabled: true), "editable click activates")
        expect(IslandAnswerEditor.shouldRestore(hasFocus: false, appIsActive: true, previousAppRunning: true), "loss of focus returns live previous app")
        expect(!IslandAnswerEditor.shouldRestore(hasFocus: true, appIsActive: true, previousAppRunning: true), "editor navigation retains foreground")
        expect(!IslandAnswerEditor.shouldRestore(hasFocus: false, appIsActive: false, previousAppRunning: true), "user app switch is not stolen back")
        expect(!IslandAnswerEditor.shouldRestore(hasFocus: false, appIsActive: true, previousAppRunning: false), "terminated app is not relaunched")
        expect(IslandAnswerEditor.Editor.submitsReturn(keyCode: 36, shift: false, markedText: false), "Return submits")
        expect(IslandAnswerEditor.Editor.submitsReturn(keyCode: 76, shift: false, markedText: false), "keypad Return submits")
        expect(!IslandAnswerEditor.Editor.submitsReturn(keyCode: 36, shift: true, markedText: false), "Shift Return stays in editor")
        expect(!IslandAnswerEditor.Editor.submitsReturn(keyCode: 36, shift: false, markedText: true), "marked text Return never submits")
        expect(!IslandAnswerEditor.Editor.submitsReturn(keyCode: 0, shift: false, markedText: false), "ordinary typing never submits")
        let methods = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval", "item/tool/requestUserInput", "mcpServer/elicitation/request"]
        let verbs = ["thread-follower-command-approval-decision", "thread-follower-file-approval-decision", "thread-follower-permissions-request-approval-response", "thread-follower-submit-user-input", "thread-follower-submit-mcp-server-elicitation-response"]
        let permissions: [String: Any] = ["network": ["enabled": true], "fileSystem": ["read": ["/fixture"]]]
        let question: [String: Any] = ["id": "q", "question": "Choose?", "options": [["label": "A"], ["label": "B"]]]
        let responses: [[String: Any]] = [["decision": "accept"], ["decision": "decline"], ["permissions": permissions, "scope": "turn"], ["answers": ["q": ["answers": ["A"]]]], ["action": "cancel"]]
        for i in methods.indices {
            let fixture = CodexDesktopIPCFixture(state: state([request(methods[i], params: ["permissions": permissions, "questions": [question]])]))
            let (client, recorder, snapshot) = try await fixture.connectedClient()
            let handle = snapshot.requests[0], wire = IslandCodexApproval(handle)!
            if i < 2 { expect(wire.decisions == ["accept", "acceptForSession", "decline", "cancel"], "schema decisions") }
            if i == 2 {
                expect(wire.actions.map(\.id) == ["turn", "session", "deny"], "permission options")
                expect(wire.response("session", answers: [:]) == data(["permissions": permissions, "scope": "session"]), "permissions unchanged")
                await fails(client, handle, data(["permissions": ["fileSystem": ["write": ["/"]]], "scope": "session"]), .invalidResponse)
            }
            if i == 3 { expect(wire.questions.count == 1 && wire.response("answers", answers: ["q": "invented"]) == nil, "only real choices accepted") }
            if i == 4 { expect(wire.actions.isEmpty && wire.questions.isEmpty, "MCP stays native only") }
            let result = try await client.submit(handle: handle, result: data(responses[i]))
            expect(result == .acceptedForDispatch, "ack is dispatch only")
            let sent = fixture.submissions[0]
            expect(sent["method"] as? String == verbs[i] && sent["targetClientIds"] == nil && sent["targetClientId"] as? String == "fixture-owner", "upstream request shape uses only singular owner target")
            let latest = await recorder.latest
            expect(latest?.requests == snapshot.requests, "ack retains pending request")
            await fails(client, handle, data(responses[i]), .alreadySubmitted)
            expect(fixture.submissions.count == 1, "no duplicate dispatch")
            fixture.setState(state([]), revision: 8)
            _ = try await recorder.wait(after: 1)
            await fails(client, handle, data(responses[i]), .staleRequest)
            await client.stop()
        }
        let entries: [[String: Any]] = [
            ["access": "read", "path": ["path": "/fixture/path"]],
            ["access": "write", "path": ["pattern": "/fixture/*.txt"]],
            ["access": "read", "path": ["value": "/fixture/value"]]
        ]
        let permissionCases: [([String: Any], [String: Any], String)] = [
            (["network": ["enabled": true], "fileSystem": ["read": [], "write": [], "entries": []]],
             ["network": ["enabled": true]], "Network"),
            (["network": ["enabled": false], "fileSystem": ["read": ["/fixture/read"], "write": ["/fixture/write"], "entries": entries]],
             ["fileSystem": ["read": ["/fixture/read"], "write": ["/fixture/write"], "entries": entries]],
             "read · /fixture/read\nwrite · /fixture/write\nread · /fixture/path\nwrite · /fixture/*.txt\nread · /fixture/value")
        ]
        for (requested, expected, summary) in permissionCases {
            for scope in ["turn", "session"] {
                let fixture = CodexDesktopIPCFixture(state: state([request(methods[2], params: ["permissions": requested])]))
                let (client, _, snapshot) = try await fixture.connectedClient()
                let wire = IslandCodexApproval(snapshot.requests[0])!
                let response = wire.response(scope, answers: [:])!
                expect(response == data(["permissions": expected, "scope": scope]), "grant reconstructs only recognized nonempty items")
                expect(wire.summary == summary, "permission summary uses upstream titles, never raw JSON")
                await fails(client, wire.handle, data(["permissions": requested, "scope": scope]), .invalidResponse)
                await fails(client, wire.handle, data(["permissions": ["network": ["enabled": true], "fileSystem": ["write": ["/"]]], "scope": scope]), .invalidResponse)
                let accepted = try await client.submit(handle: wire.handle, result: response)
                expect(accepted == .acceptedForDispatch && fixture.submissions.count == 1, "UI grant and IPC boundary agree")
                await client.stop()
            }
        }
        for requested: [String: Any] in [
            ["network": ["enabled": true], "futurePermission": true],
            ["fileSystem": ["read": ["/fixture"], "futureAccess": ["/"]]]
        ] {
            let fixture = CodexDesktopIPCFixture(state: state([request(methods[2], params: ["permissions": requested])]))
            let (client, _, snapshot) = try await fixture.connectedClient()
            let wire = IslandCodexApproval(snapshot.requests[0])!
            expect(wire.actions.isEmpty && wire.questions.isEmpty && wire.response("turn", answers: [:]) == nil, "unknown permission keys give native handoff only")
            expect(wire.summary == "请在 Codex 中处理", "unknown permission schema does not render raw JSON")
            await fails(client, wire.handle, data(["permissions": requested, "scope": "turn"]), .invalidResponse)
            await fails(client, wire.handle, data(["permissions": permissions, "scope": "turn"]), .invalidResponse)
            expect(fixture.submissions.isEmpty, "unknown schema cannot dispatch any nonempty grant")
            _ = try await client.submit(handle: wire.handle, result: data(["permissions": [:], "scope": "turn"]))
            expect(fixture.submissions.count == 1, "IPC can still explicitly deny unknown permissions with empty grant")
            await client.stop()
        }
        let disabledNetwork: [String: Any] = ["network": ["enabled": false], "fileSystem": ["read": [], "entries": []]]
        let disabledFixture = CodexDesktopIPCFixture(state: state([request(methods[2], params: ["permissions": disabledNetwork])]))
        let (disabledClient, _, disabledSnapshot) = try await disabledFixture.connectedClient()
        let disabledWire = IslandCodexApproval(disabledSnapshot.requests[0])!
        expect(disabledWire.permissionGrant?.permissions == .object([:]), "disabled network is never granted")
        expect(disabledWire.actions.map(\.id) == ["deny"] && disabledWire.response("turn", answers: [:]) == nil, "empty identified set cannot claim approval")
        await fails(disabledClient, disabledWire.handle, data(["permissions": disabledNetwork, "scope": "turn"]), .invalidResponse)
        _ = try await disabledClient.submit(handle: disabledWire.handle, result: disabledWire.response("deny", answers: [:])!)
        expect(disabledFixture.submissions.count == 1, "empty recognized grant agrees with explicit denial at IPC boundary")
        await disabledClient.stop()
        for params: [String: Any] in [["isSecret": true], ["multiSelect": true]] {
            let q = question.merging(params) { _, v in v }
            let fixture = CodexDesktopIPCFixture(state: state([request(methods[3], params: ["questions": [q]])]))
            let (client, _, snapshot) = try await fixture.connectedClient()
            expect(IslandCodexApproval(snapshot.requests[0])!.questions.isEmpty, "unsupported question returns to Codex")
            await client.stop()
        }
        for params: [String: Any] in [["options": []], ["isOther": true], ["isOther": true, "options": []]] {
            let q = question.merging(params) { _, v in v }
            let fixture = CodexDesktopIPCFixture(state: state([request(methods[3], params: ["questions": [q]])]))
            let (client, _, snapshot) = try await fixture.connectedClient()
            let wire = IslandCodexApproval(snapshot.requests[0])!
            expect(wire.questions.count == 1 && wire.questions[0].allowsText, "empty options or Other allows text")
            for invalid in [" \n\t", String(repeating: "a", count: 4_001), "a" + String(repeating: "\u{0301}", count: 32_768)] {
                expect(wire.response("answers", answers: ["q": invalid]) == nil, "blank, character and UTF8 limits")
            }
            let boundary = "a" + String(repeating: "\u{0301}", count: 32_767) + "b"
            expect(boundary.utf8.count == 65_536 && wire.response("answers", answers: ["q": boundary]) != nil, "UTF8 boundary accepted independently of grapheme count")
            expect(wire.response("answers", answers: ["q": String(repeating: "字", count: 4_000)]) != nil, "4000 characters accepted")
            let draft = IslandAnswerDraft()
            draft.select("A", for: "q"); draft.type(" 自由回答\n第二行 ", for: "q")
            expect(draft.options.isEmpty && draft.isInteracting, "typing clears choice and blocks interruptions")
            let response = wire.response("answers", answers: draft.answers)!
            expect(response == data(["answers": ["q": ["answers": ["自由回答\n第二行"]]]]), "trim outer whitespace only")
            draft.select("A", for: "q")
            expect(draft.texts.isEmpty && !draft.isInteracting && draft.answers == ["q": "A"], "choice clears draft")
            draft.focusedQuestion = "q"
            expect(draft.isInteracting, "empty focused editor still blocks alerts")
            let model = ActivityIslandViewModel()
            model.answerDrafts = [wire.handle.identity: draft]
            model.discardAnswerDrafts(except: [wire.handle.identity])
            expect(model.answerDrafts[wire.handle.identity] === draft, "same nonce preserves draft")
            model.discardAnswerDrafts(except: [])
            expect(model.answerDrafts.isEmpty && !model.isAnswerInteracting, "request disappearance clears draft and protection")
            _ = try await client.submit(handle: wire.handle, result: response)
            expect(fixture.submissions.count == 1, "free text uses existing guarded submit")
            await client.stop()
        }
        let duplicate = CodexDesktopIPCFixture(state: state([request(methods[3], params: ["questions": [question, question]])]))
        let (duplicateClient, _, duplicateSnapshot) = try await duplicate.connectedClient()
        expect(IslandCodexApproval(duplicateSnapshot.requests[0])!.questions.isEmpty, "duplicate question ids rejected")
        await duplicateClient.stop()
        let tooMany = (0..<5).map { question.merging(["id": "q\($0)"]) { _, v in v } }
        let many = CodexDesktopIPCFixture(state: state([request(methods[3], params: ["questions": tooMany])]))
        let (manyClient, _, manySnapshot) = try await many.connectedClient()
        expect(IslandCodexApproval(manySnapshot.requests[0])!.questions.isEmpty, "more than four questions native only")
        await manyClient.stop()
        let unsupported = CodexDesktopIPCFixture(state: state([request()]), supportsInput: false)
        let (noClient, _, noSnapshot) = try await unsupported.connectedClient()
        await fails(noClient, noSnapshot.requests[0], data(["decision": "accept"]), .staleRequest)
        expect(unsupported.submissions.isEmpty, "no capability no write")
        await noClient.stop()
        for ack in [false, true] {
            let fixture = CodexDesktopIPCFixture(state: state([request()]))
            fixture.setSubmissionAcknowledgement(ack, owner: "foreign")
            let (client, _, snapshot) = try await fixture.connectedClient(timeout: 0.05)
            await fails(client, snapshot.requests[0], data(["decision": "accept"]), .outcomeUnknown)
            await fails(client, snapshot.requests[0], data(["decision": "accept"]), .alreadySubmitted)
            expect(fixture.submissions.count == 1, "timeout/foreign acknowledgement never retries")
            await client.stop()
        }
        let fixture = CodexDesktopIPCFixture(state: state([request()]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let old = snapshot.requests[0]
        for response in [["decision": "unknown"], ["decision": ["acceptWithExecpolicyAmendment": [:]]], ["decision": ["applyNetworkPolicyAmendment": [:]]]] as [[String: Any]] {
            await fails(client, old, data(response), .invalidResponse)
        }
        fixture.setState(state([request(params: ["command": "changed", "availableDecisions": ["decline", "future"]])]), revision: 8)
        let changed = try await recorder.wait(after: 1)
        await fails(client, old, data(["decision": "accept"]), .staleRequest)
        expect(IslandCodexApproval(changed.requests[0])!.decisions == ["decline"], "explicit decisions constrain island")
        fixture.setAutomaticSnapshots(false)
        fixture.patch([["op": "replace", "path": ["title"], "value": "gap"]], baseRevision: 99, revision: 100)
        try await fixture.waitForFollowingCount(2)
        await fails(client, changed.requests[0], data(["decision": "decline"]), .staleRequest)
        fixture.setState(state([request()]), revision: 101)
        let renewed = try await recorder.wait(after: 2)
        expect(renewed.requests[0] != old, "stream gap remints nonce")
        await fails(client, old, data(["decision": "accept"]), .staleRequest)
        _ = try await client.submit(handle: renewed.requests[0], result: data(["decision": "accept"]))
        fixture.patch([["op": "replace", "path": ["title"], "value": "gap"]], baseRevision: 0, revision: 102)
        try await fixture.waitForFollowingCount(3)
        fixture.setState(state([request()]), revision: 103)
        let restored = try await recorder.wait(after: 3)
        await fails(client, restored.requests[0], data(["decision": "accept"]), .alreadySubmitted)
        await client.stop()
        fixture.setAutomaticSnapshots(true)
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await client.follow(conversationID: "conversation")
        _ = try await recorder.wait(after: 4)
        await fails(client, restored.requests[0], data(["decision": "accept"]), .staleRequest)
        await client.stop()
        let foreignFixture = CodexDesktopIPCFixture(state: state([request()]))
        let (foreignClient, _, ownedSnapshot) = try await foreignFixture.connectedClient()
        foreignFixture.emitRawPayload(data(["type": "broadcast", "method": "thread-stream-state-changed",
            "sourceClientId": "foreign-owner", "version": 11,
            "params": ["conversationId": "conversation", "hostId": "local",
                "change": ["type": "snapshot", "revision": 8, "conversationState": state([request()])]]]), chunkBytes: 64)
        for _ in 0..<100 {
            if !(await foreignClient.isCurrent(ownedSnapshot)) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await fails(foreignClient, ownedSnapshot.requests[0], data(["decision": "accept"]), .staleRequest)
        expect(foreignFixture.submissions.isEmpty, "owner change revokes prior handle without dispatch")
        await foreignClient.stop()
        let item: [String: Any] = ["type": "agentMessage", "id": "source", "questions": [["title": "Which?", "options": ["A", "B"]]]]
        let asyncFixture = CodexDesktopIPCFixture(state: state([], items: [item]))
        let (asyncClient, _, asyncSnapshot) = try await asyncFixture.connectedClient()
        let asyncWire = IslandCodexApproval(asyncSnapshot.requests[0])!
        let q = asyncWire.questions[0]
        let freeResponse = asyncWire.response("answers", answers: [q.id: "自己的答案"])!
        let decodedFreeResponse = try DesktopIPCJSON.decode(freeResponse, limit: 1_048_576)
        expect(q.allowsText && CodexDesktopIPCClient.validResponse(decodedFreeResponse, method: "item/tool/requestUserInput"), "async text passes wire response validator")
        _ = try await asyncClient.submit(handle: asyncWire.handle, result: freeResponse)
        expect(asyncFixture.followingCount == 2, "async refreshes before steering")
        expect(asyncFixture.submissions[0]["method"] as? String == "thread-follower-steer-turn", "async uses native steering")
        expect(asyncFixture.submissions[0]["targetClientId"] as? String == "fixture-owner"
            && asyncFixture.submissions[0]["targetClientIds"] == nil, "steer request also uses singular target only")
        await asyncClient.stop()
        for mode in ["resolved", "gone", "pending", "empty", "running"] {
            var initial = state([], items: [item])
            if mode != "running" { initial["turns"] = [["turnId": "turn", "status": "completed", "items": [item]]] }
            let fixture = CodexDesktopIPCFixture(state: initial)
            fixture.setSteerResultTurn(mode == "empty" ? "" : "new-turn")
            let (client, _, snapshot) = try await fixture.connectedClient()
            expect(snapshot.requests.count == 1, "ended turn still offers one exact question handle")
            let wire = IslandCodexApproval(snapshot.requests[0])!
            let question = wire.questions[0]
            let response = wire.response("answers", answers: [question.id: "回答"])!
            if mode == "resolved" {
                let reply = CodexDesktopRequestProjector.asyncReplyOpeningTag
                    + String(decoding: data([["questionItemId": question.id, "question": question.title, "answer": "回答"]]), as: UTF8.self)
                    + CodexDesktopRequestProjector.asyncReplyClosingTag
                var next = initial
                next["turns"] = [["turnId": "turn", "status": "completed", "items": [item,
                    ["type": "steeringUserMessage", "status": "accepted", "input": [["type": "text", "text": reply]]]]]]
                fixture.setStateAfterSteer(next)
            } else if mode == "gone" { fixture.setStateAfterSteer(state([], items: [])) }
            else if mode == "pending" { fixture.setStateAfterSteer(initial) }
            if mode == "resolved" || mode == "gone" {
                let outcome = try await client.submit(handle: wire.handle, result: response)
                expect(outcome == .confirmedResolved, "resolved post-turn answer reports confirmed success")
                expect(fixture.followingCount == 3, "ended answer confirms a post-dispatch snapshot")
            } else {
                await fails(client, wire.handle, response, .outcomeUnknown)
                await fails(client, wire.handle, response, .alreadySubmitted)
            }
            expect(fixture.submissions.count == 1, "ended and uncertain answers never dispatch twice")
            await client.stop()
        }
        let observedFixture = CodexDesktopIPCFixture(state: state([request()]))
        let observedClient = observedFixture.client(timeout: 0.05)
        let observer = NativeActivityObserver(client: observedClient)
        observer.observe([LocalSessionSnapshot(sessionID: "conversation", turnID: "turn", cwd: "/fixture", model: nil,
            isActive: true, updatedAt: Date(), activities: [])])
        for _ in 0..<100 {
            if observer.approvalSnapshots["conversation"] != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let observedHandle = observer.approvalSnapshots["conversation"]!.requests[0]
        observedFixture.setSubmissionAcknowledgement(false)
        let unknown = await observer.submit(observedHandle, result: data(["decision": "accept"]))
        expect(unknown == "结果未知，请在 Codex 中确认", "observer keeps uncertain dispatch explicit")
        observedFixture.emitState(version: 12)
        for _ in 0..<100 {
            if observer.state == .disconnected { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(observer.approvalSnapshots["conversation"]?.supportsUntrustedAppInput == false, "disconnect revokes presentation capability")
        expect(observer.submissionMessages[observedHandle.identity] == unknown, "disconnect preserves unknown result inline")
        await observer.stop()
        for method in CodexDesktopIPCClient.submissionMethods {
            let message: DesktopIPCJSON = .object(["type": .string("request"), "method": .string(method), "targetClientId": .string("owner")])
            expect(!CodexDesktopIPCClient.permitsObservationMessage(message), "ordinary writes cannot submit")
            expect(CodexDesktopIPCClient.permitsSubmissionMessage(message, owner: "owner"), "submission gate permits exact owner")
            expect(!CodexDesktopIPCClient.permitsSubmissionMessage(message, owner: "other"), "wrong owner blocked")
            for audience in [DesktopIPCJSON.array([.string("owner")]), .array([]), .null] {
                var malformed = message.object!; malformed["targetClientIds"] = audience
                expect(!CodexDesktopIPCClient.permitsSubmissionMessage(.object(malformed), owner: "owner"), "request must reject any plural audience field")
            }
        }
        expect(!CodexDesktopIPCClient.permitsSubmissionMessage(.object(["type": .string("request"), "method": .string("turn/start"), "targetClientId": .string("owner")]), owner: "owner"), "unknown method blocked")
        expect(NativeActivityObserver.submissionMessage(for: nil) == "已发送，等待 Codex 确认", "accepted result copy")
        for error in [CodexDesktopIPCError.staleRequest, .alreadySubmitted] {
            expect(NativeActivityObserver.submissionMessage(for: error) == "这个提问已在 Codex 中处理或已过期", "stale result copy")
        }
        expect(NativeActivityObserver.submissionMessage(for: CodexDesktopIPCError.outcomeUnknown) == "结果未知，请在 Codex 中确认", "unknown result copy")
        let content = IslandApprovalContent(id: "private", provider: "Codex", title: "执行命令", summary: "secret command",
            actions: [.init(id: "accept", title: "允许一次")], submit: { _, _ in fatalError("no automatic submission") })
        let hidden = content.presentation(privacy: true)
        expect(hidden.actions.isEmpty && hidden.questions.isEmpty && hidden.submit == nil && hidden.details == nil, "privacy removes approval capabilities")
        expect(hidden.summary == "有待处理请求", "privacy strips sensitive content")
        var changedContent = content; changedContent.summary = "changed"
        expect(changedContent.guardIdentity != content.guardIdentity, "content changes reset accidental-click guard")
        for id in ["accept", "once", "turn", "answers"] { expect(IslandApprovalActionKind.classify(id) == .primary, "primary capsule mapping") }
        for id in ["acceptForSession", "session"] { expect(IslandApprovalActionKind.classify(id) == .secondary, "secondary capsule mapping") }
        for id in ["decline", "deny"] { expect(IslandApprovalActionKind.classify(id) == .danger, "danger capsule mapping") }
        for id in ["cancel", "terminal", "native"] { expect(IslandApprovalActionKind.classify(id) == .fallback, "fallback capsule mapping") }
        func luminance(_ components: [Double]) -> Double {
            let c = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722
        }
        let contrast = (luminance([224.0 / 255, 130.0 / 255, 100.0 / 255]) + 0.05) / (luminance([21.0 / 255, 21.0 / 255, 21.0 / 255]) + 0.05)
        expect(contrast >= 4.5, "accent capsule and darkSurface text exceed WCAG 4.5:1")
        let flow = IslandApprovalActionFlow.arrangement(sizes: [80, 100, 60, 80, 70].map { CGSize(width: $0, height: 28) }, width: 260, trailingLast: true)
        expect(flow.height == 64, "actions wrap into two 28-point lines with 8-point gap")
        expect(flow.frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 260 }, "wrapped capsules do not truncate or overflow")
        expect(!flow.frames.enumerated().contains { i, a in flow.frames.dropFirst(i + 1).contains { a.intersects($0) } }, "wrapped actions never overlap")
        expect(flow.frames.last?.maxX == 260, "detail link remains trailing on final row")
        expect(IslandApprovalQuestionViewport.height(for: 600) == 200 && IslandApprovalQuestionViewport.height(for: 60) == 60, "question viewport is natural up to 200 points")
        let now = Date(timeIntervalSince1970: 100)
        var interaction = IslandApprovalInteraction(appearedAt: now)
        expect(interaction.disabled(now: now.addingTimeInterval(0.599), deadline: nil, message: nil), "guard covers first 0.6 seconds")
        expect(!interaction.disabled(now: now.addingTimeInterval(0.601), deadline: nil, message: nil), "guard expires")
        interaction.submitted = true
        expect(interaction.disabled(now: now.addingTimeInterval(2), deadline: nil, message: nil), "submitting blocks buttons")
        var layout = ActivityIslandListLayout(sessionIDs: ["a", "b"], rowHeight: 62)
        layout.extraHeights["a"] = 198
        expect(layout.offset(for: .init(sessionID: "b", inset: 0)) == 280, "approval height participates in scroll anchors")
        print("Island approval tests: \(checks) checks passed")
    }
}
