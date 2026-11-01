import Foundation

/// Destructive filesystem permission is derived from fresh evidence, never a display label.
enum ProjectDeletionSafety {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message + "。未移动项目文件；可选择只删除会话。" }
    }

    struct ThreadPath {
        let id: String
        let path: String
        let originalPath: String?
    }

    struct Plan: Equatable {
        let projectID: String
        let directory: URL
        let device: UInt64
        let inode: UInt64
        let threadIDs: Set<String>
    }

    private struct Project {
        let id: String
        let name: String
        let roots: [URL]
    }

    static func prepare(
        projectPath: String,
        projectName: String,
        threadIDs: Set<String>,
        threads: [ThreadPath],
        catalogData: Data,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Plan {
        let target = try absoluteURL(projectPath)
        guard target.resolvingSymlinksInPath().path == target.path else {
            throw Failure(message: "项目目录或其父路径包含符号链接，请先核对真实项目目录")
        }
        let protected = ["/", "/Users", "/Applications", "/System", "/Library", "/Volumes",
                         "/private", "/private/tmp", "/usr", "/bin", "/sbin", "/dev"]
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            + [home] + ["Desktop", "Documents", "Downloads", "Library", "Pictures", "Movies",
                        "Music", "Public", ".codex", ".claude", ".Trash"]
                .map { home.appendingPathComponent($0).resolvingSymlinksInPath() }
        guard !protected.contains(where: { contains(target, $0) }),
              !["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/dev"]
                .contains(where: { contains(URL(fileURLWithPath: $0), target) }),
              !["Library", ".codex", ".claude", ".Trash"].contains(where: {
                  contains(home.appendingPathComponent($0).resolvingSymlinksInPath(), target)
              }) else {
            throw Failure(message: "拒绝删除工作区容器、用户目录或系统数据目录：\(target.path)")
        }
        guard let root = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
              let rawProjects = root["local-projects"] as? [String: Any] else {
            throw Failure(message: "无法读取完整项目登记，不能确定目录归属")
        }
        let projects = try rawProjects.map { key, value -> Project in
            guard let raw = value as? [String: Any],
                  let paths = raw["rootPaths"] as? [String], !paths.isEmpty else {
                throw Failure(message: "项目登记中有无法识别的目录，不能确定删除范围")
            }
            return Project(id: raw["id"] as? String ?? key,
                           name: (raw["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           roots: try paths.map { try absoluteURL($0) })
        }
        guard Set(projects.map(\.id)).count == projects.count else {
            throw Failure(message: "项目登记存在重复标识，不能确定唯一目录归属")
        }
        let owners = projects.filter { $0.roots.contains(where: { $0.resolvingSymlinksInPath().path == target.path }) }
        guard owners.count == 1, let owner = owners.first,
              owner.roots.count == 1, owner.roots[0].path == target.path else {
            throw Failure(message: "所选路径不是唯一登记项目的独立目录，可能是共享工作区、父目录或多根目录项目")
        }
        for other in projects where other.id != owner.id {
            guard !other.roots.contains(where: {
                contains(target, $0) || contains($0, target)
                    || contains(target, $0.resolvingSymlinksInPath())
                    || contains($0.resolvingSymlinksInPath(), target)
            }) else {
                throw Failure(message: "目录与其他项目「\(other.name)」重叠，拒绝删除父目录或共享目录")
            }
        }
        guard !threadIDs.isEmpty else { throw Failure(message: "没有可核对的项目会话") }
        for id in threadIDs {
            guard let thread = threads.first(where: { $0.id == id }),
                  try absoluteURL(thread.path) == target,
                  let original = thread.originalPath,
                  try absoluteURL(original) == target else {
                throw Failure(message: "会话的原始工作目录与所选项目目录不一致，不能把回退路径或父目录当作项目文件夹")
            }
        }
        for thread in threads where !threadIDs.contains(thread.id) {
            for path in [thread.path, thread.originalPath].compactMap({ $0 }) where !path.isEmpty {
                let url = try absoluteURL(path)
                if contains(target, url) || contains(target, url.resolvingSymlinksInPath()) {
                    throw Failure(message: "该目录还包含未选中的会话或其他项目，拒绝扩大删除范围")
                }
            }
        }
        if let rawAssignments = root["thread-project-assignments"],
           !(rawAssignments is [String: Any]) {
            throw Failure(message: "会话项目绑定格式异常，无法确认删除范围")
        }
        for (id, value) in root["thread-project-assignments"] as? [String: Any] ?? [:] {
            guard let assignment = value as? [String: Any] else {
                throw Failure(message: "存在无法识别的会话项目绑定")
            }
            let kind = assignment["projectKind"] as? String
            if threadIDs.contains(id), kind != "local" {
                throw Failure(message: "所选会话不再绑定本地项目，请刷新后重试")
            }
            guard kind == "local" else { continue }
            guard let assignedID = assignment["projectId"] as? String,
                  projects.contains(where: { $0.id == assignedID }) else {
                throw Failure(message: "存在无法确定归属的本地项目绑定，请先刷新项目登记")
            }
            if threadIDs.contains(id), assignedID != owner.id {
                throw Failure(message: "所选会话已移动到其他项目，请刷新后重试")
            }
            if !threadIDs.contains(id), assignedID == owner.id {
                throw Failure(message: "项目登记中还有未选中的会话，请刷新完整列表后重试")
            }
            if !threadIDs.contains(id),
               let path = (assignment["cwd"] as? String) ?? (assignment["path"] as? String) {
                let url = try absoluteURL(path)
                if contains(target, url) || contains(target, url.resolvingSymlinksInPath()) {
                    throw Failure(message: "其他会话仍使用该目录，拒绝移动共享项目文件夹")
                }
            }
        }
        let identity = try directoryIdentity(target)
        return Plan(projectID: owner.id, directory: target, device: identity.device,
                    inode: identity.inode, threadIDs: threadIDs)
    }

    static func revalidate(_ plan: Plan, current: Plan) throws {
        guard current == plan else {
            throw Failure(message: "确认后项目目录、目录身份或会话范围已变化，请重新确认")
        }
    }

    static func moveToTrash(_ plan: Plan, current: Plan, move: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) throws {
        try revalidate(plan, current: current)
        let identity = try directoryIdentity(plan.directory)
        guard identity.device == plan.device, identity.inode == plan.inode,
                  plan.directory.resolvingSymlinksInPath().path == plan.directory.path else {
            throw Failure(message: "项目文件夹已被替换或变为符号链接，请重新确认")
        }
        try move(plan.directory)
    }

    private static func absoluteURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else {
            throw Failure(message: "项目目录必须是明确的绝对路径")
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        // Conservative on case-sensitive volumes too: never permit a case alias to bypass protection.
        let parentPath = parent.standardizedFileURL.path.lowercased()
        let childPath = child.standardizedFileURL.path.lowercased()
        return parentPath == "/" || childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private static func directoryIdentity(_ url: URL) throws -> (device: UInt64, inode: UInt64) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw Failure(message: "项目路径不存在或不是普通文件夹")
        }
        return (device.uint64Value, inode.uint64Value)
    }
}
