import Foundation
import CryptoKit
import Darwin

/// Configures future normal `grok` launches; never launches or migrates a terminal.
enum GrokLauncher {
    struct Plan { let updated: Data; let previous: Bool?; let changed: Bool }
    struct Outcome { let changed: Bool; let backupURL: URL? }
    enum Failure: Error, Equatable { case unreadable, unsupported, concurrentChange, write }
    static func sharedSocket(home: URL) -> URL { home.appendingPathComponent("leader.sock") }

    static func plan(_ original: Data?) throws -> Plan {
        guard let text = original.flatMap({ String(data: $0, encoding: .utf8) }) ?? (original == nil ? "" : nil),
              !text.contains("\0"), !text.hasPrefix("\u{feff}"), !text.contains("\"\"\""), !text.contains("'''"),
              !text.replacingOccurrences(of: "\r\n", with: "").contains("\r") else { throw Failure.unsupported }
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        if newline == "\r\n", text.replacingOccurrences(of: "\r\n", with: "").contains("\n") { throw Failure.unsupported }
        var lines = text.components(separatedBy: newline)
        var section = "", cliStart: Int?, cliEnd: Int?, firstHeader: Int?, rootDotted = false
        var target: (index: Int, prefix: String, previous: Bool, suffix: String)?
        func match(_ pattern: String, _ line: String) -> NSTextCheckingResult? {
            try? NSRegularExpression(pattern: pattern).firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        }
        for (index, line) in lines.enumerated() {
            let trim = line.trimmingCharacters(in: .whitespaces)
            if trim.isEmpty || trim.hasPrefix("#") { continue }
            if trim.hasPrefix("[") {
                if section == "cli" && cliEnd == nil { cliEnd = index }
                if firstHeader == nil { firstHeader = index }
                guard let header = match("^\\[\\s*([^\\[\\]]+)\\s*\\]\\s*(?:#.*)?$", trim) else {
                    if trim.contains("cli") { throw Failure.unsupported }
                    section = "other"; continue
                }
                section = (trim as NSString).substring(with: header.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if ["cli", "\"cli\"", "'cli'"].contains(section) {
                    guard cliStart == nil else { throw Failure.unsupported }; cliStart = index; section = "cli"
                }
                continue
            }
            if section.isEmpty, match("^(?:cli|\"cli\"|'cli')\\s*=", trim) != nil { throw Failure.unsupported }
            if section.isEmpty && trim.hasPrefix("cli.") { rootDotted = true }
            let key = section == "cli" ? "use_leader" : section.isEmpty ? "cli\\.use_leader" : nil
            guard let key else { continue }
            if let value = match("^([ \\t]*" + key + "[ \\t]*=[ \\t]*)(true|false)([ \\t]*(?:#.*)?)$", line) {
                guard target == nil else { throw Failure.unsupported }
                let valueLine = line as NSString
                target = (index, valueLine.substring(with: value.range(at: 1)), valueLine.substring(with: value.range(at: 2)) == "true", valueLine.substring(with: value.range(at: 3)))
            } else if trim.contains("use_leader") { throw Failure.unsupported }
        }
        if let target {
            if target.previous { return .init(updated: original ?? Data(), previous: true, changed: false) }
            lines[target.index] = target.prefix + "true" + target.suffix
            return .init(updated: Data(lines.joined(separator: newline).utf8), previous: false, changed: true)
        }
        let marker = "# Codex Pulse: shared IPC for automatic island interactions"
        if let cliStart {
            let insertion = cliEnd ?? (lines.last == "" ? lines.count - 1 : lines.count)
            lines.insert(contentsOf: [marker, "use_leader = true"], at: max(cliStart + 1, insertion))
            return .init(updated: Data(lines.joined(separator: newline).utf8), previous: nil, changed: true)
        }
        if rootDotted {
            let insertion = firstHeader ?? (lines.last == "" ? lines.count - 1 : lines.count)
            lines.insert(contentsOf: [marker, "cli.use_leader = true"], at: insertion)
            return .init(updated: Data(lines.joined(separator: newline).utf8), previous: nil, changed: true)
        }
        let prefix = text.isEmpty ? "" : text.hasSuffix(newline) ? newline : newline + newline
        return .init(updated: Data((text + prefix + "[cli]" + newline + marker + newline + "use_leader = true" + newline).utf8), previous: nil, changed: true)
    }
    static func isEnabled(home: URL) throws -> Bool { try plan(readConfiguration(home.appendingPathComponent("config.toml"))).previous == true }
    static func enable(home: URL, beforeCommit: (() -> Void)? = nil) throws -> Outcome {
        guard sharedSocket(home: home).path.utf8.count < 104 else { throw Failure.unsupported }
        let file = home.appendingPathComponent("config.toml")
        let original = try readConfiguration(file), change = try plan(original)
        guard change.changed else { return .init(changed: false, backupURL: nil) }
        if original != nil && !FileManager.default.isWritableFile(atPath: file.path) { throw Failure.unreadable }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var directoryInfo = stat()
        guard lstat(home.path, &directoryInfo) == 0, directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o022 == 0 else { throw Failure.unreadable }
        let backup = home.appendingPathComponent("config.toml.codex-pulse-shared-" + String(Int(Date().timeIntervalSince1970)) + "-" + String(UUID().uuidString.prefix(8)) + ".json")
        // Only the managed setting is backed up. Other model settings may contain credentials.
        let metadata: [String: Any] = ["version": 1, "setting": "cli.use_leader", "originalFileExisted": original != nil,
            "previousValue": change.previous.map { $0 as Any } ?? NSNull(),
            "originalSHA256": SHA256.hash(data: original ?? Data()).map { String(format: "%02x", $0) }.joined()]
        try writePrivate(try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), to: backup)
        let temporary = home.appendingPathComponent(".codex-pulse-shared-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try writePrivate(change.updated, to: temporary)
        beforeCommit?()
        guard try readConfiguration(file) == original else { throw Failure.concurrentChange }
        if original != nil { _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: file) }
        guard try readConfiguration(file) == change.updated else { throw Failure.write }
        return .init(changed: true, backupURL: backup)
    }
    private static func readConfiguration(_ file: URL) throws -> Data? {
        var info = stat()
        if lstat(file.path, &info) != 0 { if errno == ENOENT { return nil }; throw Failure.unreadable }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              let data = GrokJSON.read(file, maximum: 262_144) else { throw Failure.unreadable }
        return data
    }
    private static func writePrivate(_ data: Data, to file: URL) throws {
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.write }; defer { close(fd) }
        var offset = 0
        try data.withUnsafeBytes { bytes in
            while offset < data.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                guard count > 0 else { throw Failure.write }; offset += count
            }
        }
        guard fsync(fd) == 0 else { throw Failure.write }
    }
}
