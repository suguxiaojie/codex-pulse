import Foundation
import Darwin

struct ProjectRenameRecord: Equatable, Identifiable {
    let id: String
    let name: String
    let roots: [String]
    let metadata: [String: String]
}

enum ProjectRenameError: LocalizedError {
    case invalidName, unavailable, notRegistered, ambiguous, changed, linkedProject, uncertain
    var errorDescription: String? {
        switch self {
        case .invalidName: return "项目名称须为 1 至 200 个字符，不能包含换行或控制字符。"
        case .unavailable: return "无法连接当前 Codex 桌面项目服务，请打开 Codex 后重试。"
        case .notRegistered: return "该目录没有对应的 Codex 项目登记，可设置 Pulse 历史分组显示名称。"
        case .ambiguous: return "该路径没有唯一对应的 Codex 项目，无法安全重命名。"
        case .changed: return "项目名称、路径或归属已变化，请关闭窗口后重新选择项目。"
        case .linkedProject: return "此本地项目关联了 ChatGPT 云端项目，请在 Codex 的编辑项目入口重命名，以保持关联名称一致。"
        case .uncertain: return "重命名结果尚未确认，请到 Codex 核对；本次请求不会自动重发。"
        }
    }
}

final class ProjectRenameEngine {
    typealias JSON = [String: Any]
    private let request: (String, JSON) throws -> JSON
    private var submitted = false
    init(request: @escaping (String, JSON) throws -> JSON) { self.request = request }

    static func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ProjectRenameError.invalidName
        }
        return value
    }

    private func record(_ value: Any?) throws -> ProjectRenameRecord {
        guard let value = value as? JSON, let id = value["id"] as? String, !id.isEmpty,
              let name = value["name"] as? String, let roots = value["roots"] as? [JSON],
              let metadata = value["metadata"] as? [String: String] else { throw ProjectRenameError.unavailable }
        let paths = try roots.map { root -> String in
            guard let path = root["path"] as? String, path.hasPrefix("/") else { throw ProjectRenameError.unavailable }
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return .init(id: id, name: name, roots: paths, metadata: metadata)
    }

    func list() throws -> [ProjectRenameRecord] {
        var result: [ProjectRenameRecord] = [], cursor: String?, seen = Set<String>()
        for _ in 0..<50 {
            var params: JSON = ["limit": 100]
            if let cursor { params["cursor"] = cursor }
            let page = try request("project/list", params)
            guard let data = page["data"] as? [JSON] else { throw ProjectRenameError.unavailable }
            result += try data.map { try record($0) }
            guard let next = page["nextCursor"] as? String else {
                guard Set(result.map(\.id)).count == result.count else { throw ProjectRenameError.ambiguous }
                return result
            }
            guard !next.isEmpty, seen.insert(next).inserted else { throw ProjectRenameError.unavailable }
            cursor = next
        }
        throw ProjectRenameError.unavailable
    }

    func select(path: String) throws -> ProjectRenameRecord {
        guard path.hasPrefix("/") else { throw ProjectRenameError.ambiguous }
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        let matches = try list().filter { $0.roots.contains(path) }
        guard !matches.isEmpty else { throw ProjectRenameError.notRegistered }
        guard matches.count == 1 else { throw ProjectRenameError.ambiguous }
        let selected = matches[0]
        guard selected.metadata["codex.chatGptBacking"] == nil,
              selected.metadata["codex.chatGptBackingCreation"] == nil else { throw ProjectRenameError.linkedProject }
        return selected
    }

    func rename(_ expected: ProjectRenameRecord, to rawName: String) throws -> ProjectRenameRecord {
        let name = try Self.validatedName(rawName)
        guard !submitted else { throw ProjectRenameError.uncertain }
        let current = try record(request("project/read", ["projectId": expected.id])["project"])
        guard current == expected else { throw ProjectRenameError.changed }
        if name == current.name { return current }
        // No roots, metadata or thread membership fields are sent. Never retry a write.
        submitted = true
        do {
            let response = try record(request("project/update", ["projectId": current.id, "name": name])["project"])
            let after = try record(request("project/read", ["projectId": current.id])["project"])
            let desired = ProjectRenameRecord(id: current.id, name: name, roots: current.roots, metadata: current.metadata)
            guard response == desired, after == desired else { throw ProjectRenameError.uncertain }
            return after
        } catch { throw ProjectRenameError.uncertain }
    }
}

struct ProjectDisplayNameDraft: Identifiable, Equatable {
    let id: String
    let name: String
}

enum ProjectDisplayNames {
    static let key = "sessionProjectDisplayNames"
    static func load(from defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
    static func save(_ name: String, for path: String, to defaults: UserDefaults = .standard) throws {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw ProjectRenameError.ambiguous
        }
        let name = try ProjectRenameEngine.validatedName(name)
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        var names = load(from: defaults)
        names[path] = name
        defaults.set(names, forKey: key)
    }
}

enum ProjectRenameService {
    static func connect() throws -> CodexProxyTransport {
        let socket = FileManager.default.temporaryDirectory.appendingPathComponent("cli-agents-\(getuid())/codex-app.sock")
        // Desktop publishes a user-owned symlink to its daemon socket on current versions.
        let resolved = socket.resolvingSymlinksInPath()
        guard let entry = try? FileManager.default.attributesOfItem(atPath: socket.path),
              (entry[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeSocket,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let executable = CodexExecutableLocator.resolve() else { throw ProjectRenameError.unavailable }
        return try CodexProxyTransport(executable: executable, scope: .projects, socketURL: resolved)
    }

    static func namesByPath() -> [String: String] {
        guard let transport = try? connect() else { return [:] }
        defer { transport.close() }
        guard let projects = try? ProjectRenameEngine(request: transport.request).list() else { return [:] }
        let entries = projects.flatMap { project in project.roots.map { ($0, project.name) } }
        return Dictionary(grouping: entries, by: { $0.0 }).compactMapValues { $0.count == 1 ? $0[0].1 : nil }
    }
}
