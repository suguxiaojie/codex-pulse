// Permission mapping adapted from QuotaView ClaudeCodeApproval (f779531, MIT).
import Foundation

struct ClaudePermissionRequest: Identifiable {
    struct Question: Identifiable {
        var id: String { text }
        let text: String
        let options: [String]
    }
    enum Choice { case once, session, always, deny, cancel }
    let id: String
    let sessionID: String
    let toolUseID: String?
    let tool: String
    let cwd: String
    let input: [String: Any]
    let suggestions: [[String: Any]]
    let questions: [Question]
    var receivedAt = Date()
    var deadline: Date { receivedAt.addingTimeInterval(TimeInterval(ClaudeCodeInstaller.decisionTimeoutSeconds)) }
    var detail: String {
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func decode(_ message: ClaudeCodeBridgeMessage, sessionID: String) -> Self? {
        guard message.awaitsDecision,
              let object = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              object["hook_event_name"] as? String == "PermissionRequest",
              let tool = object["tool_name"] as? String, !tool.isEmpty,
              let input = object["tool_input"] as? [String: Any], input["_quotaViewTruncated"] == nil else { return nil }
        var questions: [Question] = []
        if tool == "AskUserQuestion" {
            guard let list = input["questions"] as? [[String: Any]], !list.isEmpty, list.count <= 4 else { return nil }
            for question in list {
                guard question["multiSelect"] as? Bool != true,
                      let text = question["question"] as? String, !text.isEmpty,
                      !questions.contains(where: { $0.text == text }),
                      let options = question["options"] as? [[String: Any]], !options.isEmpty else { return nil }
                let labels = options.compactMap { $0["label"] as? String }
                guard labels.count == options.count, labels.allSatisfy({ !$0.isEmpty }) else { return nil }
                questions.append(.init(text: text, options: labels))
            }
        }
        // Broad mode/directory updates are handled in the original client only.
        let suggestions = (object["permission_suggestions"] as? [[String: Any]] ?? []).filter {
            $0["type"] as? String == "addRules" && $0["behavior"] as? String == "allow"
                && ($0["rules"] as? [[String: Any]])?.isEmpty == false
        }
        return .init(id: message.eventID, sessionID: sessionID, toolUseID: object["tool_use_id"] as? String,
            tool: tool, cwd: object["cwd"] as? String ?? "", input: input,
            suggestions: suggestions, questions: questions)
    }
    func decision(_ choice: Choice, answers: [String: String] = [:]) -> [String: Any]? {
        if choice == .deny { return ["behavior": "deny", "message": "The user declined this request in Codex Pulse."] }
        if choice == .cancel { return ["behavior": "deny", "message": "The user cancelled this request in Codex Pulse.", "interrupt": true] }
        if !questions.isEmpty {
            guard choice == .once, questions.allSatisfy({ !(answers[$0.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
            var updated = input; updated["answers"] = answers
            return ["behavior": "allow", "updatedInput": updated]
        }
        switch choice {
        case .once: return ["behavior": "allow"]
        case .session, .always:
            guard !suggestions.isEmpty else { return nil }
            return ["behavior": "allow", "updatedPermissions": suggestions.map { original in
                var value = original; value["destination"] = choice == .session ? "session" : "userSettings"; return value
            }]
        default: return nil
        }
    }
    func permitsIslandAnswers(_ answers: [String: String]) -> Bool {
        Set(answers.keys) == Set(questions.map(\.text))
            && questions.allSatisfy { $0.options.contains(answers[$0.text] ?? "") }
    }
}
