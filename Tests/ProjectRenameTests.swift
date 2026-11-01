import Foundation

@main enum ProjectRenameTests {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func reject(_ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected rejection") } catch { checks += 1 }
    }
    static func main() throws {
        typealias JSON = [String: Any]
        func project(_ id: String = "p", _ name: String = "Before", _ roots: [String] = ["/project"]) -> JSON {
            ["id": id, "name": name, "roots": roots.map { ["path": $0] }, "metadata": ["kept": "yes"]]
        }
        var stored = project(), writes = 0
        let engine = ProjectRenameEngine { method, params in
            switch method {
            case "project/list": return ["data": [stored], "nextCursor": NSNull()]
            case "project/read": return ["project": stored]
            case "project/update":
                expect(Set(params.keys) == ["projectId", "name"], "Only name and exact ID may be written")
                expect(params["projectId"] as? String == "p", "Stable identity")
                writes += 1; stored["name"] = params["name"]
                return ["project": stored]
            default: fatalError("Unexpected method")
            }
        }
        let original = try engine.select(path: "/project")
        let result = try engine.rename(original, to: "  新项目 🚀  ")
        expect(result.name == "新项目 🚀", "Trim and preserve Unicode")
        expect(result.roots == original.roots && result.metadata == original.metadata, "No folder or metadata changes")
        expect(writes == 1, "One write")
        reject { _ = try engine.rename(original, to: "Again") }
        for name in ["", "  ", "a\nb", "a\0b", String(repeating: "a", count: 201)] {
            reject { _ = try ProjectRenameEngine.validatedName(name) }
        }
        for candidates in [[JSON](), [project(), project("other")], [project("p", "Before", ["/project/child"])]] {
            let e = ProjectRenameEngine { _, _ in ["data": candidates] }
            reject { _ = try e.select(path: "/project") }
        }
        var linked = project(); linked["metadata"] = ["codex.chatGptBacking": "{}"]
        reject { _ = try ProjectRenameEngine { _, _ in ["data": [linked]] }.select(path: "/project") }
        let changed = ProjectRenameEngine { method, _ in
            expect(method == "project/read", "Stale selection must never write")
            return ["project": project("p", "Changed elsewhere")]
        }
        reject { _ = try changed.rename(original, to: "New") }
        var noOpWrites = 0
        let noOp = ProjectRenameEngine { method, _ in
            if method == "project/update" { noOpWrites += 1 }
            return ["project": project()]
        }
        _ = try noOp.rename(original, to: original.name)
        expect(noOpWrites == 0, "Same-name submit is read-only")
        for mode in ["timeout", "wrongID", "changedRoots", "failedReadback"] {
            var attempted = 0
            let e = ProjectRenameEngine { method, _ in
                if method == "project/update" {
                    attempted += 1
                    if mode == "timeout" { throw ProjectRenameError.unavailable }
                    return ["project": project(mode == "wrongID" ? "other" : "p", "New", mode == "changedRoots" ? ["/other"] : ["/project"])]
                }
                if attempted > 0 && mode == "failedReadback" { throw ProjectRenameError.unavailable }
                return ["project": project("p", attempted > 0 ? "New" : "Before")]
            }
            reject { _ = try e.rename(original, to: "New") }
            reject { _ = try e.rename(original, to: "New") }
            expect(attempted == 1, "Unknown outcomes cannot be resent")
        }
        let loop = ProjectRenameEngine { _, _ in ["data": [project()], "nextCursor": "repeat"] }
        reject { _ = try loop.list() }
        var pages = 0
        let paged = ProjectRenameEngine { _, _ in
            pages += 1
            return pages == 1 ? ["data": [project("other", "Other", ["/other"])], "nextCursor": "next"] : ["data": [project()], "nextCursor": NSNull()]
        }
        expect(try paged.select(path: "/project").id == "p", "Resolve all pages, not the first match only")
        do {
            _ = try ProjectRenameEngine { _, _ in ["data": []] }.select(path: "/history")
            fatalError("Missing registration must be distinguished")
        } catch ProjectRenameError.notRegistered { checks += 1 }
        do {
            _ = try ProjectRenameEngine { _, _ in ["data": [project(), project("other")]] }.select(path: "/project")
            fatalError("Duplicate registration must be distinguished")
        } catch ProjectRenameError.ambiguous { checks += 1 }
        let suite = "ProjectDisplayNamesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("untouched", forKey: "otherPreference")
        try ProjectDisplayNames.save("Other", for: "/other", to: defaults)
        try ProjectDisplayNames.save(" CoverAI Store ", for: "/history/store/", to: defaults)
        expect(ProjectDisplayNames.load(from: UserDefaults(suiteName: suite)!)["/history/store"] == "CoverAI Store", "Display name survives reopening preference store")
        expect(ProjectDisplayNames.load(from: defaults)["/other"] == "Other", "Other aliases preserved")
        expect(defaults.string(forKey: "otherPreference") == "untouched", "Unrelated settings preserved")
        expect(ProjectDisplayNames.load(from: defaults)["/history"] == nil, "No parent matching")
        let saved = ProjectDisplayNames.load(from: defaults)
        for path in ["", "relative", "/a/../b"] {
            reject { try ProjectDisplayNames.save("Name", for: path, to: defaults) }
        }
        reject { try ProjectDisplayNames.save("\n ", for: "/history/store", to: defaults) }
        expect(ProjectDisplayNames.load(from: defaults) == saved, "Invalid requests do not mutate aliases")
        print("Project rename: \(checks) checks passed")
    }
}
