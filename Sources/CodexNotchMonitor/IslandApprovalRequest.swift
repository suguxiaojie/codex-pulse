// Restricted option mapping adapted from QuotaView f779531 IslandApprovalProtocol (MIT).
import Foundation

struct IslandCodexApproval {
    let handle: CodexDesktopIPCRequestHandle
    let params: DesktopIPCJSON
    let context: DesktopIPCJSON?
    init?(_ handle: CodexDesktopIPCRequestHandle, context: Data? = nil) {
        guard let raw = try? DesktopIPCJSON.decode(handle.rawRequest, limit: 1_048_576), let params = raw["params"] else { return nil }
        self.handle = handle; self.params = params
        self.context = context.flatMap { try? DesktopIPCJSON.decode($0, limit: 1_048_576) }
    }
    var title: String {
        switch handle.method {
        case "item/commandExecution/requestApproval": return "执行命令"
        case "item/fileChange/requestApproval": return "修改文件"
        case "item/permissions/requestApproval": return "申请权限"
        default: return "需要回答"
        }
    }
    var decisions: [String] {
        guard ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(handle.method) else { return [] }
        let allowed = ["accept", "acceptForSession", "decline", "cancel"]
        if let explicit = params["availableDecisions"] { return allowed.filter { explicit.array?.contains(.string($0)) == true } }
        return allowed
    }
    var questions: [IslandApprovalContent.Question] {
        guard ["item/tool/requestUserInput", "desktop/tool/requestUserInputAsync"].contains(handle.method),
              let list = params["questions"]?.array, !list.isEmpty, list.count <= 4 else { return [] }
        var result: [IslandApprovalContent.Question] = []
        for q in list {
            guard q["isSecret"]?.bool != true, q["multiSelect"]?.bool != true,
                  let id = q["id"]?.string, !id.isEmpty, !result.contains(where: { $0.id == id }),
                  let title = q["question"]?.string, !title.isEmpty else { return [] }
            guard q["options"] == nil || q["options"]?.array != nil else { return [] }
            let options = q["options"]?.array ?? []
            let labels = options.compactMap { $0["label"]?.string }
            guard labels.count == options.count, labels.allSatisfy({ !$0.isEmpty }), Set(labels).count == labels.count else { return [] }
            result.append(.init(id: id, title: title, options: labels, allowsText: q["isOther"]?.bool == true || labels.isEmpty))
        }
        return result
    }
    var permissionGrant: CodexDesktopPermissionGrant? {
        guard handle.method == "item/permissions/requestApproval" else { return nil }
        return CodexDesktopPermissionGrant(params["permissions"])
    }
    var summary: String {
        if handle.method == "item/commandExecution/requestApproval" { return params["command"]?.string ?? "请在 Codex 中查看命令详情" }
        if handle.method == "item/fileChange/requestApproval" {
            let paths = context?["changes"]?.array?.compactMap { $0["path"]?.string } ?? []
            return paths.isEmpty ? "未提供文件清单，请查看详情" : "\(paths.count) 个文件\n" + paths.prefix(3).joined(separator: "\n")
        }
        if handle.method == "item/permissions/requestApproval" {
            guard let grant = permissionGrant else { return "请在 Codex 中处理" }
            return grant.titles.isEmpty ? "没有可授予的已识别权限" : grant.titles.joined(separator: "\n")
        }
        return ""
    }
    func response(_ action: String, answers: [String: String]) -> Data? {
        let value: DesktopIPCJSON
        if decisions.contains(action) { value = .object(["decision": .string(action)]) }
        else if let grant = permissionGrant, ["turn", "session", "deny"].contains(action) {
            guard action == "deny" || grant.permissions != .object([:]) else { return nil }
            value = .object(["permissions": action == "deny" ? .object([:]) : grant.permissions, "scope": .string(action == "session" ? "session" : "turn")])
        } else if action == "answers", !questions.isEmpty, Set(answers.keys) == Set(questions.map(\.id)),
                  questions.allSatisfy({ $0.validatedAnswer(answers[$0.id] ?? "") != nil }) {
            let normalized = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0.validatedAnswer(answers[$0.id]!)!) })
            value = .object(["answers": .object(normalized.mapValues { .object(["answers": .array([.string($0)])]) })])
        } else { return nil }
        return try? value.encode()
    }
    var actions: [IslandApprovalContent.Action] {
        if let grant = permissionGrant {
            let deny = IslandApprovalContent.Action(id: "deny", title: "拒绝", destructive: true)
            return grant.permissions == .object([:]) ? [deny]
                : [.init(id: "turn", title: "本轮允许"), .init(id: "session", title: "本会话允许"), deny]
        }
        let titles = ["accept": "允许一次", "acceptForSession": "本会话允许", "decline": "拒绝", "cancel": "取消任务"]
        return decisions.map { .init(id: $0, title: titles[$0]!, destructive: ["decline", "cancel"].contains($0)) }
    }
}
