// Adapted from QuotaView f7795311 (MIT), Copyright (c) 2026 Duoasa.
import Darwin
import Foundation
import CryptoKit

/// Owns QuotaView's entries in Claude Code's user `settings.json`. Entries are
/// identified only by this channel's installed helper path plus a Claude mode
/// flag; unrelated hooks and settings are preserved.
struct ClaudeCodeInstaller: Sendable {
    enum InstallationError: LocalizedError {
        case helperUnavailable, invalidSettingsFile, settingsChanged, writeFailed
        var errorDescription: String? {
            switch self {
            case .helperUnavailable: "当前 Codex Pulse 构建中缺少活动 Hook 辅助程序。"
            case .invalidSettingsFile: "Claude Code settings.json 不是有效的 JSON 对象。"
            case .settingsChanged: "Claude Code 设置正在被其他程序更新；请稍后重试。"
            case .writeFailed: "无法写入 Claude Code 设置或 Codex Pulse 连接配置。"
            }
        }
    }

    struct State: Equatable, Sendable {
        var hooksInstalled = false
        var hasOwnedHooks = false
        var statusLineInstalled = false
        var settingsExist = false
    }

    struct Configuration: Equatable, Sendable {
        var interactiveApprovals: Bool
        var statusLine: Bool
    }

    static let toolEvents = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"]
    static let eventNames = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                             "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
                             "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"]
    static let permissionTimeoutSeconds = 3_600
    static let decisionTimeoutSeconds = 120
    private static let helperName = "ClaudePulseHelper"

    let configurationDirectory: URL
    /// Claude Code's global config: `$CLAUDE_CONFIG_DIR/.claude.json`, else `~/.claude.json`.
    let globalConfigURL: URL
    let settingsURL: URL
    let socketURL: URL
    let authenticationToken: String
    let bundledHelperURL: URL
    let installedHelperURL: URL
    let routeURL: URL
    let statusLineSnapshotURL: URL
    let originalStatusLineURL: URL

    init(socketURL: URL, authenticationToken: String, configurationDirectory: URL? = nil,
         supportDirectory: URL? = nil, helperURL: URL? = nil,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         channelIdentifier: String = ClaudeCodeChannel.identifier) {
        let custom = configurationDirectory
            ?? environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = custom ?? home.appendingPathComponent(".claude", isDirectory: true)
        self.configurationDirectory = directory.standardizedFileURL
        globalConfigURL = (custom?.standardizedFileURL ?? home).appendingPathComponent(".claude.json")
        settingsURL = self.configurationDirectory.appendingPathComponent("settings.json").resolvingSymlinksInPath()
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        bundledHelperURL = helperURL ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers").appendingPathComponent(Self.helperName)
        let rootIdentifier = String(SHA256.hash(data: Data(self.configurationDirectory.path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16))
        let support = supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexNotchMonitor", isDirectory: true)
            .appendingPathComponent("Channels", isDirectory: true)
            .appendingPathComponent(channelIdentifier, isDirectory: true)
            .appendingPathComponent("claude-" + rootIdentifier, isDirectory: true)
        installedHelperURL = support.appendingPathComponent(Self.helperName)
        routeURL = support.appendingPathComponent("ClaudeCodeRoute.json")
        statusLineSnapshotURL = support.appendingPathComponent("claude-statusline.json")
        originalStatusLineURL = support.appendingPathComponent("claude-statusline-original.json")
    }

    var hookCommand: String { [quote(installedHelperURL.path), "--claude-code", "--configuration", quote(routeURL.path)].joined(separator: " ") }
    var statusLineCommand: String { [quote(installedHelperURL.path), "--claude-statusline", "--configuration", quote(routeURL.path)].joined(separator: " ") }
    var projectsURL: URL { configurationDirectory.appendingPathComponent("projects", isDirectory: true) }

    // MARK: Inspection

    func state() -> State {
        guard let root = try? readSettings().root else { return State() }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        var installed = Set<String>()
        var owned = false
        for (event, value) in hooks {
            let handlers = (value as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
                .filter { owns($0["command"] as? String ?? "") }
            guard !handlers.isEmpty else { continue }
            owned = true
            if handlers.count == 1, handlers[0]["command"] as? String == hookCommand { installed.insert(event) }
        }
        let statusLine = (root["statusLine"] as? [String: Any])?["command"] as? String
        return State(hooksInstalled: installed == Set(Self.eventNames) && routeExists
                        && FileManager.default.isExecutableFile(atPath: installedHelperURL.path),
                     hasOwnedHooks: owned, statusLineInstalled: statusLine.map(ownsStatusLine) ?? false,
                     settingsExist: FileManager.default.fileExists(atPath: settingsURL.path))
    }

    private var routeExists: Bool {
        var metadata = stat()
        return lstat(routeURL.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFREG
    }

    // MARK: Install / uninstall

    func install(_ configuration: Configuration) throws {
        guard FileManager.default.isExecutableFile(atPath: bundledHelperURL.path) else { throw InstallationError.helperUnavailable }
        try withLock {
            for _ in 0..<3 {
                let snapshot = try readSettings()
                var root = snapshot.root
                try installHelper()
                var hooks = removingOwnedHandlers(from: root["hooks"] as? [String: Any] ?? [:])
                for event in Self.eventNames {
                    var groups = hooks[event] as? [[String: Any]] ?? []
                    var group: [String: Any] = ["hooks": [["type": "command", "command": hookCommand,
                        "timeout": event == "PermissionRequest" ? Self.permissionTimeoutSeconds : event == "PreToolUse" ? Self.decisionTimeoutSeconds + 5 : 5]]]
                    if Self.toolEvents.contains(event) { group["matcher"] = "*" }
                    groups.append(group)
                    hooks[event] = groups
                }
                root["hooks"] = hooks
                var forwardCommand: String?
                if configuration.statusLine {
                    let current = root["statusLine"] as? [String: Any]
                    if let current, !ownsStatusLine(current["command"] as? String ?? "") {
                        try writePrivate(JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]), to: originalStatusLineURL)
                    }
                    forwardCommand = originalStatusLine()?["command"] as? String
                    root["statusLine"] = ["type": "command", "command": statusLineCommand, "padding": 0]
                } else if let current = root["statusLine"] as? [String: Any], ownsStatusLine(current["command"] as? String ?? "") {
                    restoreStatusLine(in: &root)
                }
                try writeRoute(configuration, forwardCommand: forwardCommand)
                do {
                    if NSDictionary(dictionary: root).isEqual(to: snapshot.root) {
                        try validateRevision(snapshot.revision)
                    } else {
                        try writeSettings(root, expectedRevision: snapshot.revision)
                    }
                    if !configuration.statusLine { try? FileManager.default.removeItem(at: originalStatusLineURL) }
                    return
                }
                catch InstallationError.settingsChanged { continue }
            }
            throw InstallationError.settingsChanged
        }
    }

    func uninstall() throws {
        try withLock {
            for attempt in 0..<3 {
                let snapshot = try readSettings()
                guard snapshot.revision != nil else { break }
                var root = snapshot.root
                let hooks = root["hooks"] as? [String: Any] ?? [:]
                var cleaned = removingOwnedHandlers(from: hooks)
                cleaned = cleaned.filter { !(($0.value as? [Any])?.isEmpty ?? false) }
                if cleaned.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = cleaned }
                if let current = root["statusLine"] as? [String: Any], ownsStatusLine(current["command"] as? String ?? "") {
                    restoreStatusLine(in: &root)
                }
                guard !NSDictionary(dictionary: root).isEqual(to: snapshot.root) else { break }
                do { try writeSettings(root, expectedRevision: snapshot.revision); break }
                catch InstallationError.settingsChanged where attempt < 2 { continue }
            }
            for url in [routeURL, statusLineSnapshotURL, originalStatusLineURL, installedHelperURL]
                where FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func restoreStatusLine(in root: inout [String: Any]) {
        if let original = originalStatusLine() { root["statusLine"] = original }
        else { root.removeValue(forKey: "statusLine") }
    }

    private func originalStatusLine() -> [String: Any]? {
        guard let data = try? Data(contentsOf: originalStatusLineURL), data.count <= 65_536 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Files

    private func readSettings() throws -> (root: [String: Any], revision: Data?) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return ([:], nil) }
        guard let size = try FileManager.default.attributesOfItem(atPath: settingsURL.path)[.size] as? NSNumber, size.intValue <= 8_388_608 else { throw InstallationError.invalidSettingsFile }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return ([:], data) }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallationError.invalidSettingsFile
        }
        if let value = object["statusLine"], !(value is [String: Any]) { throw InstallationError.invalidSettingsFile }
        if let value = object["hooks"] {
            // Never rewrite a hooks section we cannot faithfully preserve.
            guard let hooks = value as? [String: Any],
                  hooks.values.allSatisfy({ ($0 as? [Any])?.allSatisfy({ $0 is [String: Any] }) == true }) else {
                throw InstallationError.invalidSettingsFile
            }
        }
        return (object, data)
    }

    private func writeSettings(_ root: [String: Any], expectedRevision: Data?) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
        try validateRevision(expectedRevision)
        if manager.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("codex-pulse-backup")
            if !manager.fileExists(atPath: backup.path) { try manager.copyItem(at: settingsURL, to: backup) }
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try writeAtomically(data, to: settingsURL, mode: S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH,
                            preservingModeOf: settingsURL) { try validateRevision(expectedRevision) }
    }

    private func validateRevision(_ expected: Data?) throws {
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard try Data(contentsOf: settingsURL) == expected else { throw InstallationError.settingsChanged }
        } else if expected != nil { throw InstallationError.settingsChanged }
    }

    private func writeRoute(_ configuration: Configuration, forwardCommand: String?) throws {
        var route: [String: Any] = [
            "version": 1, "socketPath": socketURL.path, "authenticationToken": authenticationToken,
            "interactiveApprovals": configuration.interactiveApprovals,
            "decisionTimeoutSeconds": Self.decisionTimeoutSeconds,
            "statusLineSnapshotPath": statusLineSnapshotURL.path
        ]
        if let forwardCommand, !forwardCommand.isEmpty { route["statusLineForwardCommand"] = forwardCommand }
        let data = try JSONSerialization.data(withJSONObject: route, options: [.sortedKeys])
        if (try? Data(contentsOf: routeURL)) != data { try writePrivate(data, to: routeURL) }
    }

    func updateRoute(_ configuration: Configuration) throws {
        guard routeExists else { return }
        try writeRoute(configuration, forwardCommand: configuration.statusLine ? originalStatusLine()?["command"] as? String : nil)
    }

    private func writePrivate(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, S_IRWXU)
        try writeAtomically(data, to: destination, mode: S_IRUSR | S_IWUSR, preservingModeOf: nil)
    }

    private func writeAtomically(_ data: Data, to destination: URL, mode: mode_t, preservingModeOf existing: URL?,
                                 beforeReplacing: (() throws -> Void)? = nil) throws {
        var permissions = mode
        if let existing, let attributes = try? FileManager.default.attributesOfItem(atPath: existing.path),
           let value = attributes[.posixPermissions] as? NSNumber { permissions = mode_t(value.uint16Value) }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".codex-pulse-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw InstallationError.writeFailed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        fchmod(descriptor, permissions)
        try handle.close()
        try beforeReplacing?()
        guard rename(temporary.path, destination.path) == 0 else { throw InstallationError.writeFailed }
    }

    private func installHelper() throws {
        let manager = FileManager.default
        if manager.isExecutableFile(atPath: installedHelperURL.path),
           (try? Data(contentsOf: installedHelperURL)) == (try? Data(contentsOf: bundledHelperURL)) { return }
        let directory = installedHelperURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, S_IRWXU)
        let temporary = directory.appendingPathComponent(".\(Self.helperName)-\(UUID().uuidString)")
        do {
            try manager.copyItem(at: bundledHelperURL, to: temporary)
            chmod(temporary.path, S_IRWXU)
            guard rename(temporary.path, installedHelperURL.path) == 0 else { throw InstallationError.writeFailed }
        } catch {
            try? manager.removeItem(at: temporary)
            throw InstallationError.helperUnavailable
        }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
        let lockURL = configurationDirectory.appendingPathComponent(".codex-pulse-settings.lock")
        let descriptor = Darwin.open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw InstallationError.settingsChanged }
        defer { Darwin.close(descriptor) }
        let deadline = Date().addingTimeInterval(1)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline else { throw InstallationError.settingsChanged }
            Thread.sleep(forTimeInterval: 0.01)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    // MARK: Ownership

    private func removingOwnedHandlers(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            result[event] = groups.compactMap { group -> [String: Any]? in
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                let remaining = handlers.filter { !owns($0["command"] as? String ?? "") }
                guard remaining.count != handlers.count else { return group }
                guard !remaining.isEmpty else { return nil }
                var updated = group; updated["hooks"] = remaining
                return updated
            }
        }
        return result
    }

    func owns(_ command: String) -> Bool { commandArguments(command, mode: "--claude-code") }
    func ownsStatusLine(_ command: String) -> Bool { commandArguments(command, mode: "--claude-statusline") }

    private func commandArguments(_ command: String, mode: String) -> Bool {
        guard let words = shellWords(command), words.count == 4 else { return false }
        return words[0] == installedHelperURL.path && words[1] == mode && words[2] == "--configuration" && words[3] == routeURL.path
    }

    private func shellWords(_ command: String) -> [String]? {
        var words = [String](), word = "", quote: Character?, hasWord = false, escaped = false
        for character in command {
            if escaped { word.append(character); hasWord = true; escaped = false; continue }
            if character == "\\", quote != "'" { escaped = true; continue }
            if let current = quote {
                if character == current { quote = nil } else { word.append(character) }
                hasWord = true
            } else if character == "'" || character == "\"" {
                quote = character; hasWord = true
            } else if character.isWhitespace {
                if hasWord { words.append(word); word = ""; hasWord = false }
            } else {
                if ";|&<>`$()\\".contains(character) { return nil }
                word.append(character); hasWord = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if hasWord { words.append(word) }
        return words
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

enum ClaudeCodeChannel {
    static let identifier = "com.coverai.codex-pulse.claude"
}
