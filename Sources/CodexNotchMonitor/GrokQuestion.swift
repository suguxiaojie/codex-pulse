import Foundation
import CoreFoundation
import CryptoKit

struct GrokQuestionRequest: Equatable, Identifiable {
    struct Permission: Equatable {
        let title: String
        let input: String
        let allowOnce: String?
        let rejectOnce: String?
        func response(_ action: String) -> [String: Any]? {
            guard let option = action == "once" ? allowOnce : action == "deny" ? rejectOnce : nil else { return nil }
            return ["outcome": ["outcome": "selected", "optionId": option]]
        }
    }
    struct Question: Equatable {
        struct Option: Equatable { let label: String; let description: String; let preview: String? }
        let text: String
        let options: [Option]
        let multiple: Bool
    }
    let id: String
    let epoch: UUID
    let rpcID: Data
    let sessionID: String
    let toolCallID: String
    let turnID: String
    let questions: [Question]
    let rawParams: Data
    var permission: Permission? = nil

    static func decode(_ object: [String: Any], epoch: UUID, turnID: String) -> Self? {
        guard !turnID.isEmpty, let wireID = object["id"], !(wireID is NSNull),
              (wireID is String && !(wireID as! String).isEmpty) || GrokJSON.integer(wireID) != nil,
              let rpcID = try? JSONSerialization.data(withJSONObject: wireID, options: [.fragmentsAllowed]), rpcID.count <= 256,
              var params = object["params"] as? [String: Any], var method = object["method"] as? String else { return nil }
        if let inner = params["method"] as? String, let nested = params["params"] as? [String: Any] { method = inner; params = nested }
        if method.hasPrefix("_") { method.removeFirst() }
        let call = params["toolCall"] as? [String: Any]
        guard ["x.ai/ask_user_question", "session/request_permission"].contains(method),
              let session = params["sessionId"] as? String, UUID(uuidString: session) != nil,
              let tool = (params["toolCallId"] ?? call?["toolCallId"]) as? String, !tool.isEmpty, tool.utf8.count <= 256,
              let raw = try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys]), raw.count <= 131_072 else { return nil }
        let digest = SHA256.hash(data: raw + rpcID + Data(turnID.utf8)).map { String(format: "%02x", $0) }.joined()
        if method == "session/request_permission" {
            guard let call, let title = call["title"] as? String, !title.isEmpty, title.count <= 160,
                  let options = params["options"] as? [[String: Any]], (1...16).contains(options.count),
                  let rawInput = call["rawInput"], !(rawInput is NSNull) else { return nil }
            var review: [String: Any] = ["rawInput": rawInput]
            for key in ["kind", "locations", "content"] { if let value = call[key] { review[key] = value } }
            guard let input = try? JSONSerialization.data(withJSONObject: review, options: [.sortedKeys]), input.count <= 4000 else { return nil }
            var allow: String?, reject: String?, seen = Set<String>()
            for option in options {
                guard let id = option["optionId"] as? String, !id.isEmpty, id.utf8.count <= 256, seen.insert(id).inserted else { return nil }
                if option["kind"] as? String == "allow_once" { guard allow == nil else { return nil }; allow = id }
                if option["kind"] as? String == "reject_once" { guard reject == nil else { return nil }; reject = id }
            }
            guard allow != nil || reject != nil else { return nil }
            return .init(id: epoch.uuidString + ":" + digest, epoch: epoch, rpcID: rpcID, sessionID: session, toolCallID: tool,
                turnID: turnID, questions: [], rawParams: raw, permission: .init(title: title, input: String(decoding: input, as: UTF8.self), allowOnce: allow, rejectOnce: reject))
        }
        guard let list = params["questions"] as? [[String: Any]], (1...4).contains(list.count) else { return nil }
        var questions: [Question] = []
        for q in list {
            guard let text = q["question"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 4000, let options = q["options"] as? [[String: Any]], options.count <= 16 else { return nil }
            let multi = q["multiSelect"] ?? q["multi_select"]
            if let multi, !(multi is NSNumber && CFGetTypeID(multi as! NSNumber) == CFBooleanGetTypeID()) { return nil }
            var choices: [Question.Option] = []
            for option in options {
                guard let label = option["label"] as? String, !label.isEmpty, label.count <= 500 else { return nil }
                let description = option["description"] as? String ?? ""
                let preview = option["preview"] as? String
                guard description.count <= 4000, (preview?.utf8.count ?? 0) <= 16_384 else { return nil }
                choices.append(.init(label: label, description: description, preview: preview))
            }
            guard Set(choices.map(\.label)).count == choices.count else { return nil }
            questions.append(.init(text: text, options: choices, multiple: (multi as? NSNumber)?.boolValue == true))
        }
        guard Set(questions.map(\.text)).count == questions.count else { return nil }
        return .init(id: epoch.uuidString + ":" + digest, epoch: epoch, rpcID: rpcID, sessionID: session,
            toolCallID: tool, turnID: turnID, questions: questions, rawParams: raw)
    }
    func response(selections: [String: [String]], texts: [String: String]) -> [String: Any]? {
        var answers: [String: [String]] = [:], annotations: [String: [String: String]] = [:]
        let allowed = Set(questions.map(\.text))
        guard Set(selections.keys).isSubset(of: allowed), Set(texts.keys).isSubset(of: allowed) else { return nil }
        for question in questions {
            let selected = selections[question.text] ?? []
            let text = texts[question.text] ?? ""
            if !text.isEmpty {
                guard selected.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      text.count <= 4000, text.utf8.count <= 65_536 else { return nil }
                answers[question.text] = ["Other"]; annotations[question.text] = ["notes": text]
            } else {
                guard !selected.isEmpty, question.multiple || selected.count == 1,
                      Set(selected).count == selected.count, Set(selected).isSubset(of: Set(question.options.map(\.label))) else { return nil }
                answers[question.text] = question.options.filter { selected.contains($0.label) }.map(\.label)
                if !question.multiple, let preview = question.options.first(where: { $0.label == selected.first })?.preview {
                    annotations[question.text] = ["preview": preview]
                }
            }
        }
        var result: [String: Any] = ["outcome": "accepted", "answers": answers]
        if !annotations.isEmpty { result["annotations"] = annotations }
        return result
    }
}

/// Per-connection authority. Log text never creates a request here.
struct GrokQuestionState {
    private(set) var epoch = UUID()
    private(set) var requests: [String: GrokQuestionRequest] = [:]
    private(set) var submitted: Set<String> = []
    private var tools: [String: (session: String, turn: String)] = [:]
    private var turns: [String: String] = [:]
    private var retiredTurns: [String: [String]] = [:]
    private var resolved: [String] = []
    var allowedSessions: Set<String> = []
    mutating func restrict(to sessions: Set<String>) {
        allowedSessions = sessions
        requests = requests.filter { sessions.contains($0.value.sessionID) }
        submitted.formIntersection(requests.keys)
        tools = tools.filter { sessions.contains($0.value.session) }; turns = turns.filter { sessions.contains($0.key) }
        retiredTurns = retiredTurns.filter { sessions.contains($0.key) }
    }
    mutating func reset() { epoch = UUID(); requests = [:]; submitted = []; tools = [:]; turns = [:]; retiredTurns = [:]; resolved = []; allowedSessions = [] }
    mutating func consume(_ object: [String: Any]) {
        guard var method = object["method"] as? String, var params = object["params"] as? [String: Any] else { return }
        if let inner = params["method"] as? String, let nested = params["params"] as? [String: Any] { method = inner; params = nested }
        if method.hasPrefix("_") { method.removeFirst() }
        guard let session = params["sessionId"] as? String, allowedSessions.contains(session) else { return }
        let update = params["update"] as? [String: Any] ?? [:]
        if method == "session/update" {
            let meta = params["_meta"] as? [String: Any] ?? [:]
            if let turn = meta["promptId"] as? String, !turn.isEmpty {
                guard !(retiredTurns[session] ?? []).contains(turn) else { return }
                if turns[session] != turn {
                    if let old = turns[session] { retiredTurns[session, default: []].append(old); retiredTurns[session] = Array(retiredTurns[session]!.suffix(128)) }
                    requests = requests.filter { $0.value.sessionID != session }; turns[session] = turn
                    tools = tools.filter { $0.value.session != session }
                }
                if let tool = update["toolCallId"] as? String, update["sessionUpdate"] as? String == "tool_call" {
                    if tools.count >= 256 { tools = [:] }
                    tools[session + ":" + tool] = (session, turn)
                }
            }
            if update["sessionUpdate"] as? String == "turn_completed" {
                guard let ended = (update["prompt_id"] ?? meta["promptId"]) as? String, ended == turns[session] else { return }
                retiredTurns[session, default: []].append(ended); retiredTurns[session] = Array(retiredTurns[session]!.suffix(128))
                requests = requests.filter { $0.value.sessionID != session }; turns[session] = nil
                tools = tools.filter { $0.value.session != session }
            }
        } else if method == "x.ai/session_notification", update["sessionUpdate"] as? String == "interaction_resolved",
                  let tool = (update["tool_call_id"] ?? update["toolCallId"]) as? String {
            requests = requests.filter { !($0.value.sessionID == session && $0.value.toolCallID == tool) }
            resolved.append(session + ":" + tool); resolved = Array(resolved.suffix(256))
        } else if ["x.ai/ask_user_question", "session/request_permission"].contains(method),
                  let tool = (params["toolCallId"] ?? (params["toolCall"] as? [String: Any])?["toolCallId"]) as? String,
                  let known = tools[session + ":" + tool], known.session == session, known.turn == turns[session],
                  !resolved.contains(session + ":" + tool), requests.count < 32,
                  let request = GrokQuestionRequest.decode(object, epoch: epoch, turnID: known.turn) {
            requests = requests.filter { !($0.value.sessionID == session && $0.value.toolCallID == tool) }
            requests[request.id] = request
        }
    }
    mutating func submit(_ request: GrokQuestionRequest, action: String = "answers", selections: [String: [String]], texts: [String: String]) -> [String: Any]? {
        guard request.epoch == epoch, allowedSessions.contains(request.sessionID), requests[request.id] == request,
              !submitted.contains(request.id), turns[request.sessionID] == request.turnID,
              let result = request.permission != nil ? request.permission?.response(action) : action == "answers" ? request.response(selections: selections, texts: texts) : nil,
              let id = try? JSONSerialization.jsonObject(with: request.rpcID, options: [.fragmentsAllowed]) else { return nil }
        submitted.insert(request.id)
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }
}
