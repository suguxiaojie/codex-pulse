import Foundation
import CryptoKit

struct CodexSharedQuestionSnapshot: Equatable {
    let epoch: UUID
    let threadID: String
    let turnID: String
    let status: String
    let startedAt: Date?
    let questions: [CodexDesktopProjectedAsyncQuestion]
    var requestKey: String {
        let fields = pending.map { [$0.questionItemID, $0.question] + $0.options }
        let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        return "\(threadID):\(turnID):" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var identity: String { "shared:\(epoch):\(requestKey)" }
    var pending: [CodexDesktopProjectedAsyncQuestion] { questions.filter { $0.resolvedAnswer == nil } }
}

/// Protocol-only engine. Its request closure is replaced by an isolated fixture in tests.
final class CodexSharedQuestionEngine {
    typealias JSON = [String: Any]
    let epoch: UUID
    private let request: (String, JSON) throws -> JSON
    private struct ItemCache { var turnID: String; var ids: [String]; var items: [String: JSON] }
    private var cache: [String: ItemCache] = [:]
    private(set) var uncertainSubmissions: Set<String> = []

    init(epoch: UUID = UUID(), request: @escaping (String, JSON) throws -> JSON) {
        self.epoch = epoch; self.request = request
    }
    func loadedIDs() throws -> Set<String> {
        var ids = Set<String>(), cursor: String?, seen = Set<String>()
        for _ in 0..<16 {
            let value = try request("thread/loaded/list", cursor.map { ["cursor": $0] } ?? [:])
            guard let page = value["data"] as? [String], page.count <= 1000 else { throw CodexProxyTransport.Failure.protocolViolation }
            ids.formUnion(page)
            guard let next = value["nextCursor"] as? String else { return ids }
            guard !next.isEmpty, seen.insert(next).inserted else { throw CodexProxyTransport.Failure.protocolViolation }
            cursor = next
        }
        throw CodexProxyTransport.Failure.protocolViolation
    }
    func poll(threadIDs: Set<String>) throws -> [String: CodexSharedQuestionSnapshot] {
        let loaded = try loadedIDs().intersection(threadIDs)
        guard loaded.count <= 64 else { throw CodexProxyTransport.Failure.protocolViolation }
        cache = cache.filter { loaded.contains($0.key) }
        var result: [String: CodexSharedQuestionSnapshot] = [:]
        for id in loaded.sorted() {
            if let snapshot = try read(id), !snapshot.pending.isEmpty { result[id] = snapshot }
        }
        return result
    }
    private func latestTurn(_ threadID: String) throws -> JSON? {
        let result = try request("thread/turns/list", ["threadId": threadID, "limit": 1, "sortDirection": "desc", "itemsView": "summary"])
        guard let turns = result["data"] as? [JSON], turns.count <= 1 else { throw CodexProxyTransport.Failure.protocolViolation }
        return turns.first
    }
    func read(_ threadID: String, fresh: Bool = false) throws -> CodexSharedQuestionSnapshot? {
        let result = try request("thread/read", ["threadId": threadID, "includeTurns": false])
        guard let thread = result["thread"] as? JSON, thread["id"] as? String == threadID,
              thread["canAcceptDirectInput"] as? Bool == true,
              let state = thread["status"] as? JSON, ["active", "idle"].contains(state["type"] as? String ?? ""),
              CodexActivitySessionKind.classify(metadata: thread) == .user,
              let turn = try latestTurn(threadID), let turnID = turn["id"] as? String,
              let status = turn["status"] as? String, ["inProgress", "completed"].contains(status) else { return nil }
        var prior = cache[threadID]
        if fresh || prior?.turnID != turnID { prior = nil }
        let previousIDs = Set(prior?.ids ?? [])
        var entries: [JSON] = [], cursor: String?, cursors = Set<String>(), complete = false
        for _ in 0..<32 {
            var params: JSON = ["threadId": threadID, "turnId": turnID, "limit": 100, "sortDirection": "desc"]
            if let cursor { params["cursor"] = cursor }
            let value = try request("thread/items/list", params)
            guard let page = value["data"] as? [JSON], page.count <= 100 else { throw CodexProxyTransport.Failure.protocolViolation }
            var overlap = false
            for entry in page {
                guard entry["turnId"] as? String == turnID, let item = entry["item"] as? JSON,
                      let id = item["id"] as? String, !id.isEmpty else { throw CodexProxyTransport.Failure.protocolViolation }
                overlap = overlap || previousIDs.contains(id)
                entries.append(item)
            }
            if overlap || value["nextCursor"] == nil || value["nextCursor"] is NSNull { complete = true; break }
            guard let next = value["nextCursor"] as? String, !next.isEmpty, cursors.insert(next).inserted else { throw CodexProxyTransport.Failure.protocolViolation }
            cursor = next
        }
        guard complete else { throw CodexProxyTransport.Failure.protocolViolation }
        var updated = prior ?? ItemCache(turnID: turnID, ids: [], items: [:])
        var known = Set(updated.ids)
        for item in entries.reversed() {
            let id = item["id"] as! String
            if known.insert(id).inserted { updated.ids.append(id) }
            let type = item["type"] as? String
            // Discard commands and their outputs, retaining only question/reply evidence.
            if type == "userMessage" || type == "steeringUserMessage" || (type == "agentMessage" && item["questions"] is [JSON]) {
                updated.items[id] = item
            } else { updated.items.removeValue(forKey: id) }
        }
        guard updated.ids.count <= 20_000 else { throw CodexProxyTransport.Failure.protocolViolation }
        let items = updated.ids.compactMap { updated.items[$0] }
        var projectedTurn: JSON = ["turnId": turnID, "status": status, "items": items]
        if let started = turn["startedAt"] as? Double { projectedTurn["turnStartedAtMs"] = started * 1000 }
        let data = try JSONSerialization.data(withJSONObject: ["id": threadID, "source": "cli", "requests": [], "turns": [projectedTurn]])
        let projection = try CodexDesktopRequestProjector.project(conversationID: threadID, conversationStateData: data)
        // A turn may change while paging; never publish a mixed-turn snapshot.
        guard let after = try latestTurn(threadID), after["id"] as? String == turnID,
              after["status"] as? String == status else { cache.removeValue(forKey: threadID); return nil }
        cache[threadID] = updated
        return .init(epoch: epoch, threadID: threadID, turnID: turnID, status: status,
                     startedAt: projection.startedAt, questions: projection.asyncQuestions)
    }
    static func replyText(_ questions: [CodexDesktopProjectedAsyncQuestion], answers: [String: String]) throws -> String {
        guard !questions.isEmpty, Set(answers.keys) == Set(questions.map(\.questionItemID)) else { throw CodexProxyTransport.Failure.rejected }
        let replies = try questions.map { question -> JSON in
            guard let answer = answers[question.questionItemID], !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  answer.count <= 4000, answer.utf8.count <= 65_536 else { throw CodexProxyTransport.Failure.rejected }
            return ["questionItemId": question.questionItemID, "question": question.question, "answer": answer]
        }
        let data = try JSONSerialization.data(withJSONObject: replies, options: [.sortedKeys, .withoutEscapingSlashes])
        return CodexDesktopRequestProjector.asyncReplyOpeningTag + "\n" + String(decoding: data, as: UTF8.self)
            + "\n" + CodexDesktopRequestProjector.asyncReplyClosingTag
    }
    func submit(_ expected: CodexSharedQuestionSnapshot, answers: [String: String]) throws -> String {
        guard expected.epoch == epoch, expected.status == "inProgress", !uncertainSubmissions.contains(expected.identity),
              try loadedIDs().contains(expected.threadID),
              let current = try read(expected.threadID, fresh: true), current == expected else { return "问题或轮次已变化，请在 One Native 中查看" }
        let text = try Self.replyText(current.pending, answers: answers)
        // Once a write is attempted its outcome can be unknown. Never retry it automatically.
        uncertainSubmissions.insert(expected.identity)
        let response: JSON
        do {
            response = try request("turn/steer", ["threadId": current.threadID, "expectedTurnId": current.turnID,
                "clientUserMessageId": UUID().uuidString,
                "input": [["type": "text", "text": text, "text_elements": []]]])
        } catch { return "发送结果未确认，请到 One Native 查看；不会自动重发" }
        guard response["turnId"] as? String == current.turnID else { return "回执不匹配，请到 One Native 查看" }
        // Acceptance alone isn't delivery. Verify the exact reply in the native history.
        if let after = try? read(current.threadID, fresh: true), current.pending.allSatisfy({ question in
            after.questions.contains { $0.questionItemID == question.questionItemID && $0.question == question.question && $0.resolvedAnswer == answers[question.questionItemID] }
        }) { return "回答已确认送达 One Native 会话" }
        return "回答已受理，等待会话确认；请勿重复发送"
    }
}

/// Main-thread presentation state; all socket work stays on a single utility queue.
final class CodexSharedQuestions {
    var onChange: (() -> Void)?
    private(set) var snapshots: [String: CodexSharedQuestionSnapshot] = [:]
    private var candidates = Set<String>()
    private var busy = false
    private var nextPoll = Date.distantPast
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.coverai.codex-pulse.shared-questions", qos: .utility)
    private var transport: CodexProxyTransport?
    private var engine: CodexSharedQuestionEngine?
    private var blocked: Set<String> = []
    private var messages: [String: String] = [:]
    private var lastSuccess = Date.distantPast
    var isConnected: Bool { Date().timeIntervalSince(lastSuccess) < 15 }

    func observe(_ sessions: [LocalSessionSnapshot]) {
        candidates = Set(sessions.filter { $0.sessionKind == .user }.map(\.sessionID))
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        }
        poll()
    }
    deinit { timer?.invalidate() }
    private func poll() {
        guard !busy, Date() >= nextPoll else { return }
        busy = true; nextPoll = Date().addingTimeInterval(5)
        let ids = candidates
        queue.async { [weak self] in
            guard let self else { return }
            var result: [String: CodexSharedQuestionSnapshot] = [:]
            var success = false
            do {
                if self.engine == nil {
                    // One Native's standalone launcher owns this shared daemon. No new daemon is started.
                    let executable = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex")
                    guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw CodexProxyTransport.Failure.unavailable }
                    let transport = try CodexProxyTransport(executable: executable)
                    self.transport = transport
                    self.engine = CodexSharedQuestionEngine { try transport.request($0, $1) }
                }
                result = try self.engine!.poll(threadIDs: ids); success = true
            } catch {
                self.transport?.close(); self.transport = nil; self.engine = nil
            }
            DispatchQueue.main.async {
                self.busy = false
                if success { self.lastSuccess = Date() }
                else { self.nextPoll = Date().addingTimeInterval(15); self.lastSuccess = .distantPast }
                if self.snapshots != result { self.snapshots = result; self.onChange?() }
            }
        }
    }
    func available(_ snapshot: CodexSharedQuestionSnapshot) -> Bool {
        Date().timeIntervalSince(lastSuccess) < 15 && snapshots[snapshot.threadID] == snapshot
            && snapshot.status == "inProgress" && !blocked.contains(snapshot.requestKey)
    }
    func message(for snapshot: CodexSharedQuestionSnapshot) -> String? { messages[snapshot.requestKey] }
    @MainActor func submit(_ snapshot: CodexSharedQuestionSnapshot, answers: [String: String]) async -> String {
        guard available(snapshot), !busy else { return "状态刷新中或请求已变化，请稍后再试" }
        busy = true; blocked.insert(snapshot.requestKey)
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.resume(returning: "连接已关闭"); return }
                let result: String
                do { result = try self.engine?.submit(snapshot, answers: answers) ?? "连接已关闭，请到 One Native 查看" }
                catch { result = "请求未能确认，请到 One Native 查看" }
                DispatchQueue.main.async {
                    self.busy = false; self.messages[snapshot.requestKey] = result
                    self.nextPoll = .distantPast; self.onChange?(); self.poll()
                    continuation.resume(returning: result)
                }
            }
        }
    }
    func merge(_ sessions: [LocalSessionSnapshot]) -> [LocalSessionSnapshot] {
        guard Date().timeIntervalSince(lastSuccess) < 15 else { return sessions }
        return sessions.map { local in
            guard let value = snapshots[local.sessionID], value.turnID == local.turnID, !value.pending.isEmpty,
                  local.nativeWaitReason == nil else { return local }
            var copy = local
            copy.isActive = true; copy.nativePhase = .waitingApproval; copy.nativeWaitReason = .userInput
            copy.nativeReplyRequestIDs = Set(value.pending.map { value.identity + ":" + $0.questionItemID })
            copy.nativeSuppressCompletion = true
            return copy
        }
    }
}
