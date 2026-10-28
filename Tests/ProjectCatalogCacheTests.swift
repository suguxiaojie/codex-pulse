import Foundation

@main enum ProjectCatalogCacheTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/project-catalog-cache-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        func bytes(_ name: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["local-projects": ["p": ["id": "p", "name": name, "rootPaths": ["/fixture"]]],
                "thread-project-assignments": ["thread": ["projectKind": "local", "projectId": "p"]]], options: [.sortedKeys])
        }
        try bytes("Alpha").write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let first = CodexProjectCatalog.loadState(from: url)
        precondition(first.namesByPath["/fixture"] == "Alpha" && first.assignmentsByThread["thread"]?.projectName == "Alpha")
        precondition(CodexProjectCatalog.loadState(from: url) == first)
        let oldInode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as! NSNumber
        try bytes("Bravo").write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let newInode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as! NSNumber
        let sameSize = try bytes("Alpha").count == bytes("Bravo").count
        precondition(oldInode != newInode && sameSize)
        let renamed = CodexProjectCatalog.loadState(from: url)
        precondition(renamed.namesByPath["/fixture"] == "Bravo" && renamed.assignmentsByThread["thread"]?.projectName == "Bravo")
        try Data("invalid".utf8).write(to: url)
        precondition(CodexProjectCatalog.loadState(from: url) == .empty)
        try bytes("Alpha").write(to: url)
        precondition(CodexProjectCatalog.loadState(from: url) == first)
        try FileManager.default.removeItem(at: url)
        precondition(CodexProjectCatalog.loadState(from: url) == .empty)
        print("Project catalog cache: repeat, atomic replacement with equal size/date, assignments, invalid JSON, recovery and deletion passed")
    }
}
