import Foundation

@main
enum ProjectDeletionSafetyTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { fatalError(message) }
    }

    static func rejected(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Must reject: \(label)") }
        catch { checks += 1 }
    }

    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: ".tmp/project-deletion-tests/\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let workspace = home.appendingPathComponent("Workspace")
        let project = workspace.appendingPathComponent("Selected")
        let sibling = workspace.appendingPathComponent("Other")
        let nested = project.appendingPathComponent("Nested")
        for directory in [nested, sibling] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = project.appendingPathComponent(".hidden")
        let siblingFile = sibling.appendingPathComponent("keep.txt")
        let childFile = nested.appendingPathComponent("source.txt")
        for file in [source, siblingFile, childFile] { try Data("original".utf8).write(to: file) }

        func catalog(_ paths: [String: [String]], assignments: [String: Any] = [:]) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "local-projects": paths.mapValues { ["name": "Selected", "rootPaths": $0] as [String: Any] },
                "thread-project-assignments": assignments,
            ])
        }
        let normal = try catalog(["selected": [project.path], "other": [sibling.path]])
        let selected = ProjectDeletionSafety.ThreadPath(id: "t", path: project.path, originalPath: project.path)
        func prepare(_ path: String? = nil, data: Data? = nil,
                     threads: [ProjectDeletionSafety.ThreadPath]? = nil) throws -> ProjectDeletionSafety.Plan {
            try ProjectDeletionSafety.prepare(projectPath: path ?? project.path, projectName: "Selected",
                threadIDs: ["t"], threads: threads ?? [selected], catalogData: data ?? normal, home: home)
        }
        let plan = try prepare()
        let renamed = try ProjectDeletionSafety.prepare(projectPath: project.path, projectName: "Renamed",
            threadIDs: ["t"], threads: [selected], catalogData: normal, home: home)
        expect(renamed == plan, "Display name changes must not change directory identity or deletion scope")
        expect(plan.directory.path == project.path, "Exact independent project must remain deletable")
        rejected("workspace parent") { _ = try prepare(workspace.path) }
        rejected("empty") { _ = try prepare("") }
        rejected("relative") { _ = try prepare("Selected") }
        rejected("parent traversal") { _ = try prepare(project.path + "/../") }
        for path in ["/", home.path, home.appendingPathComponent("Documents").path,
                     home.appendingPathComponent(".codex/sessions").path, "/Applications/Anything.app"] {
            rejected("protected \(path)") { _ = try prepare(path) }
        }
        rejected("duplicate root") {
            _ = try prepare(data: catalog(["selected": [project.path], "duplicate": [project.path]]))
        }
        rejected("multiple roots") {
            _ = try prepare(data: catalog(["selected": [project.path, sibling.path]]))
        }
        rejected("nested registered project") {
            _ = try prepare(data: catalog(["selected": [project.path], "nested": [nested.path]]))
        }
        rejected("registered ancestor") {
            _ = try prepare(data: catalog(["selected": [project.path], "parent": [workspace.path]]))
        }
        rejected("unregistered project") { _ = try prepare(data: catalog([:])) }
        rejected("invalid JSON") { _ = try prepare(data: Data("broken".utf8)) }
        rejected("missing original cwd") {
            _ = try prepare(threads: [.init(id: "t", path: project.path, originalPath: nil)])
        }
        rejected("fallback enlarged original cwd") {
            _ = try prepare(threads: [.init(id: "t", path: project.path, originalPath: nested.path)])
        }
        rejected("other local nested session") {
            _ = try prepare(threads: [selected, .init(id: "other", path: nested.path, originalPath: nested.path)])
        }
        rejected("other session historical cwd") {
            _ = try prepare(threads: [selected, .init(id: "other", path: sibling.path, originalPath: nested.path)])
        }
        rejected("unlisted assignment") {
            _ = try prepare(data: catalog(["selected": [project.path]], assignments: [
                "unlisted": ["projectKind": "local", "projectId": "selected"],
            ]))
        }
        rejected("selected assignment moved") {
            _ = try prepare(data: catalog(["selected": [project.path], "other": [sibling.path]], assignments: [
                "t": ["projectKind": "local", "projectId": "other"],
            ]))
        }
        rejected("selected assignment is remote") {
            _ = try prepare(data: catalog(["selected": [project.path]], assignments: [
                "t": ["projectKind": "remote", "projectId": "remote"],
            ]))
        }
        rejected("other assignment uses nested cwd") {
            _ = try prepare(data: catalog(["selected": [project.path], "other": [sibling.path]], assignments: [
                "other": ["projectKind": "local", "projectId": "other", "cwd": nested.path],
            ]))
        }
        let alias = workspace.appendingPathComponent("Alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: project)
        rejected("symlink target") { _ = try prepare(alias.path) }
        rejected("other project symlink alias") {
            _ = try prepare(data: catalog(["selected": [project.path], "alias": [alias.path]]))
        }
        let childLink = project.appendingPathComponent("linked-other")
        try fm.createSymbolicLink(at: childLink, withDestinationURL: sibling)
        rejected("other project registered through a child symlink") {
            _ = try prepare(data: catalog(["selected": [project.path], "other": [childLink.path]]))
        }
        rejected("other session uses a child symlink") {
            _ = try prepare(threads: [selected, .init(id: "other", path: childLink.path, originalPath: childLink.path)])
        }
        rejected("case alias overlap") {
            _ = try prepare(data: catalog(["selected": [project.path], "alias": [project.path.uppercased()]]))
        }
        let changed = try catalog(["new-id": [project.path], "other": [sibling.path]])
        rejected("registration changed after confirmation") {
            try ProjectDeletionSafety.revalidate(plan, current: prepare(data: changed))
        }
        var moves = 0
        rejected("new nested project after confirmation") {
            let current = try prepare(data: catalog(["selected": [project.path], "new": [nested.path]]))
            try ProjectDeletionSafety.moveToTrash(plan, current: current) { _ in moves += 1 }
        }
        let saved = workspace.appendingPathComponent("Selected-original")
        try fm.moveItem(at: project, to: saved)
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        rejected("directory replacement after confirmation") {
            try ProjectDeletionSafety.moveToTrash(plan, current: prepare()) { _ in moves += 1 }
        }
        rejected("directory replacement between final check and trash") {
            try ProjectDeletionSafety.moveToTrash(plan, current: plan) { _ in moves += 1 }
        }
        expect(moves == 0, "Rejected plans must never reach filesystem mutation")
        try fm.removeItem(at: project) // Only the empty directory created by this test.
        try fm.moveItem(at: saved, to: project)
        let current = try prepare()
        let trash = root.appendingPathComponent("simulated-trash")
        try ProjectDeletionSafety.moveToTrash(current, current: prepare()) { target in
            expect(target.path == project.path, "Move only the selected exact directory")
            try fm.moveItem(at: target, to: trash)
        }
        expect(fm.fileExists(atPath: workspace.path), "Workspace parent survives")
        expect(try Data(contentsOf: siblingFile) == Data("original".utf8), "Sibling content survives")
        expect(fm.fileExists(atPath: trash.appendingPathComponent(".hidden").path), "Selected hidden content moves")
        expect(fm.fileExists(atPath: trash.appendingPathComponent("Nested/source.txt").path), "Selected subtree moves")
        expect(!fm.fileExists(atPath: project.path), "Selected directory has moved")
        print("Project deletion safety: \(checks) checks passed; real Trash and user sessions untouched")
    }
}
