// Adapted from QuotaView d16307f (MIT), Copyright (c) 2026 Duoasa.
// Source/license: THIRD_PARTY_NOTICES.md. Observation-only adaptation; no response submission.
import Foundation
import CryptoKit
public enum CodexActivitySessionKind: String, Codable, Sendable {
    case user, memoryConsolidation, subagent, internalTask, unknown

    /// Background memory remains observable without granting user conversation capabilities.
    public var supportsActivityPresentation: Bool { self == .user || self == .memoryConsolidation || self == .subagent }

    /// Explicit background/internal identity takes precedence over sparse host fallbacks.
    /// Exact memory identity can refine a previously generic internal classification.
    public static func resolving(_ kinds: Self...) -> Self {
        if kinds.contains(.memoryConsolidation) { return .memoryConsolidation }
        if kinds.contains(.internalTask) { return .internalTask }
        if kinds.contains(.subagent) { return .subagent }
        if kinds.contains(.user) { return .user }
        return .unknown
    }

    public static func classify(source: Any?, threadSource: String? = nil) -> Self {
        let sourceKind: Self
        if let object = source as? [String: Any] {
            let tags = ["internal", "subagent", "subAgent"].filter { object.keys.contains($0) }
            if tags.count == 1, let tag = tags.first {
                if object[tag] as? String == "memory_consolidation" { sourceKind = .memoryConsolidation }
                else if tag != "internal", CodexActivitySubagentIdentity.threadSpawn(source: object) != nil { sourceKind = .subagent }
                else { sourceKind = .internalTask }
            } else {
                sourceKind = tags.isEmpty ? .unknown : .internalTask
            }
        } else if let text = source as? String {
            if let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] {
                sourceKind = classify(source: object)
            } else if text.lowercased().contains("subagent") {
                sourceKind = .internalTask
            } else if ["cli", "exec", "vscode", "appServer", "app-server"].contains(text) {
                sourceKind = .user
            } else { sourceKind = .unknown }
        } else { sourceKind = .unknown }
        let threadKind: Self
        switch threadSource {
        case "memory_consolidation": threadKind = .memoryConsolidation
        case "user", "agent_created_thread": threadKind = .user
        case "subagent":
            // This persisted generic tag is refined only by the exact native
            // subtype. Alone it grants neither user nor child presentation.
            threadKind = sourceKind == .subagent || sourceKind == .memoryConsolidation ? .unknown : .internalTask
        case .some(let text) where !text.isEmpty: threadKind = .internalTask
        default: threadKind = .unknown
        }
        if threadKind == .internalTask || sourceKind == .internalTask { return .internalTask }
        return resolving(threadKind, sourceKind)
    }

    public static func classify(metadata: [String: Any]) -> Self {
        let kind = classify(source: metadata["source"],
                            threadSource: metadata["threadSource"] as? String ?? metadata["thread_source"] as? String)
        guard kind != .memoryConsolidation else { return kind }
        let child = CodexActivitySubagentIdentity.decode(metadata)
        if kind == .internalTask {
            let threadSource = metadata["threadSource"] as? String ?? metadata["thread_source"] as? String
            return threadSource == "subagent" && child != nil ? .subagent : .internalTask
        }
        if kind == .subagent, child == nil { return .internalTask }
        return child == nil ? kind : .subagent
    }

}

public enum CodexActivityWaitReason: String, Codable, Sendable {
    case approval
    case userInput
}
public enum CodexUserInputMode: String, Codable, Equatable, Sendable {
    case synchronous, asynchronous

    public static func forToolName(_ name: String?) -> Self? {
        switch name?.split(separator: ".").last {
        case "request_user_input": return .synchronous
        case "request_user_input_async": return .asynchronous
        default: return nil
        }
    }
}
public enum CodexActivityPrivacy {
    public static func hashIdentifier(_ identifier: String) -> String {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}

import Foundation
import CoreFoundation

/// Deterministic Codex avatar selected from the native 28-image palette.
/// Matches the locally verified Codex renderer's `khc` algorithm: UTF-16 code
/// units, modulus 2^31 - 1, then palette index. Seed is the native thread ID.
public struct CodexActivitySubagentAvatar: Equatable, Hashable, Sendable {
    public let paletteIndex: Int
    public var assetName: String { "CodexSubagentAvatar-\(paletteIndex)" }

    public init(threadID: String) {
        var accumulator: UInt64 = 0
        for codeUnit in threadID.utf16 {
            accumulator = (accumulator * 31 + UInt64(codeUnit)) % 2_147_483_647
        }
        paletteIndex = Int(accumulator % 28)
    }
}

/// Read-only child identity from Codex's native parent relationship, never from
/// a task title, working directory, prompt or tool argument.
public struct CodexActivitySubagentIdentity: Equatable, Sendable {
    public let threadID: String
    public let sessionHash: String
    public let parentThreadID: String
    public let parentSessionHash: String
    public let depth: Int?
    public let nickname: String?
    public let role: String?
    public let title: String?
    public var avatar: CodexActivitySubagentAvatar { .init(threadID: threadID) }

    public init?(threadID: String, parentThreadID: String, depth: Int? = nil,
                 nickname: String? = nil, role: String? = nil, title: String? = nil) {
        guard Self.validIdentifier(threadID), Self.validIdentifier(parentThreadID),
              threadID != parentThreadID, depth.map({ (0...1024).contains($0) }) ?? true else { return nil }
        self.threadID = threadID
        self.sessionHash = CodexActivityPrivacy.hashIdentifier(threadID)
        self.parentThreadID = parentThreadID
        self.parentSessionHash = CodexActivityPrivacy.hashIdentifier(parentThreadID)
        self.depth = depth
        self.nickname = Self.displayText(nickname)
        self.role = Self.displayText(role)
        self.title = Self.displayText(title)
    }

    /// App Server uses parentThreadId; core session_meta also carries the
    /// SubAgentSource::ThreadSpawn parent_thread_id envelope.
    public static func decode(_ metadata: [String: Any], expectedThreadID: String? = nil) -> Self? {
        guard let id = metadata["id"] as? String, expectedThreadID == nil || expectedThreadID == id else { return nil }
        let source = sourceObject(metadata["source"])
        let tags = ["internal", "subagent", "subAgent"].filter { source?.keys.contains($0) == true }
        let threadSource = metadata["threadSource"] as? String ?? metadata["thread_source"] as? String
        // Memory and unrelated internal workers can never acquire a child row.
        guard threadSource != "memory_consolidation", !tags.contains("internal"), tags.count <= 1 else { return nil }
        let spawn = threadSpawn(source: metadata["source"])
        if tags.first != nil, spawn == nil { return nil }
        let direct = (metadata["parentThreadId"] ?? metadata["parent_thread_id"]) as? String
        let nested = spawn?["parent_thread_id"] as? String
        if let direct, let nested, direct != nested { return nil }
        guard let parent = direct ?? nested else { return nil }
        let depth: Int?
        if let number = spawn?["depth"] as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue) else { return nil }
            depth = number.intValue
        } else { depth = nil }
        return .init(threadID: id, parentThreadID: parent, depth: depth,
                     nickname: (metadata["agentNickname"] ?? metadata["agent_nickname"] ?? spawn?["agent_nickname"]) as? String,
                     role: (metadata["agentRole"] ?? metadata["agent_role"] ?? spawn?["agent_role"]) as? String,
                     title: (metadata["name"] ?? metadata["title"]) as? String)
    }

    public func withTitle(_ title: String?) -> Self {
        Self(threadID: threadID, parentThreadID: parentThreadID, depth: depth,
             nickname: nickname, role: role, title: title ?? self.title) ?? self
    }

    static func threadSpawn(source: Any?) -> [String: Any]? {
        guard let object = sourceObject(source), object.count == 1 else { return nil }
        let tags = ["internal", "subagent", "subAgent"].filter { object.keys.contains($0) }
        guard tags.count == 1, let tag = tags.first, tag != "internal",
              let subtype = object[tag] as? [String: Any], subtype.count == 1,
              let spawn = subtype["thread_spawn"] as? [String: Any],
              let parent = spawn["parent_thread_id"] as? String, validIdentifier(parent) else { return nil }
        return spawn
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 1024 && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func sourceObject(_ source: Any?) -> [String: Any]? {
        if let object = source as? [String: Any] { return object }
        guard let text = source as? String, text.utf8.count <= 65_536,
              let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func displayText(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(256))
    }
}
