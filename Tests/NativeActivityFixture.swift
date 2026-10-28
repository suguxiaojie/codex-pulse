// QuotaView d16307f (MIT) native IPC transport fixture; no real desktop connection.
import Foundation
final class CodexDesktopIPCFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var state: [String: Any]
    let conversationID: String
    private var additionalStates: [String: (state: [String: Any], revision: Int64)] = [:]
    private var revision: Int64 = 7
    private var supportsInput: Bool
    private var continuation: AsyncStream<Data>.Continuation?
    private var messages: [[String: Any]] = []
    private var automaticSnapshots = true
    private var acknowledgeSubmissions = true
    private var acknowledgementOwner = "fixture-owner"
    private var steerResultTurn = "turn"
    private var stateAfterSteer: [String: Any]?
    private var host = "local"
    private var ownerDiscoveryReady = true
    init(state: [String: Any], supportsInput: Bool = true) { self.state = state; self.supportsInput = supportsInput; conversationID = state["id"] as? String ?? "conversation" }
    var submissions: [[String: Any]] { lock.withLock { messages.filter { ($0["method"] as? String)?.hasPrefix("thread-follower-") == true } } }
    var followingCount: Int { lock.withLock { messages.filter { $0["method"] as? String == "thread-stream-following-changed" }.count } }
    var initializeCount: Int { lock.withLock { messages.filter { $0["method"] as? String == "initialize" }.count } }
    var discoveryMessages: [[String: Any]] { lock.withLock { messages.filter { $0["method"] as? String == "thread-owner-discovery" } } }
    func setOwnerDiscoveryReady(_ ready: Bool) { lock.withLock { ownerDiscoveryReady = ready } }
    func emitFollowingStatusRequested() {
        lock.withLock { emitLocked(["type": "broadcast", "method": "thread-stream-following-status-requested",
            "sourceClientId": "fixture-owner", "version": 1,
            "params": ["conversationId": conversationID, "hostId": host]]) }
    }
    func setAutomaticSnapshots(_ enabled: Bool) { lock.withLock { automaticSnapshots = enabled } }
    func setSubmissionAcknowledgement(_ enabled: Bool, owner: String = "fixture-owner") { lock.withLock { acknowledgeSubmissions = enabled; acknowledgementOwner = owner } }
    func setSteerResultTurn(_ turn: String) { lock.withLock { steerResultTurn = turn } }
    func setStateAfterSteer(_ state: [String: Any]) { lock.withLock { stateAfterSteer = state } }
    func setState(_ state: [String: Any], revision: Int64, emit: Bool = true) {
        lock.withLock { self.state = state; self.revision = revision; if emit { emitStateLocked() } }
    }
    func setAdditionalState(_ state: [String: Any], conversationID: String, revision: Int64, emit: Bool = true) {
        lock.withLock {
            additionalStates[conversationID] = (state, revision)
            if emit { emitStateLocked(conversationID: conversationID) }
        }
    }
    func emitFrameHeader(length: UInt32) {
        lock.withLock { continuation?.yield(Data([UInt8(length & 255), UInt8((length >> 8) & 255), UInt8((length >> 16) & 255), UInt8((length >> 24) & 255)])) }
    }
    func emitRawBytes(_ bytes: Data) { lock.withLock { continuation?.yield(bytes) } }
    func emitRawPayload(_ payload: Data, chunkBytes: Int) {
        let size = UInt32(payload.count)
        let framed = Data([UInt8(truncatingIfNeeded: size), UInt8(truncatingIfNeeded: size >> 8),
            UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 24)]) + payload
        lock.withLock {
            for offset in stride(from: 0, to: framed.count, by: chunkBytes) {
                continuation?.yield(Data(framed[offset..<min(framed.count, offset + chunkBytes)]))
            }
        }
    }
    func emitState(version: Int = 11) { lock.withLock { emitStateLocked(version: version) } }
    func patch(_ patches: [[String: Any]], baseRevision: Int64, revision: Int64) {
        lock.withLock { emitLocked(["type": "broadcast", "method": "thread-stream-state-changed", "sourceClientId": "fixture-owner", "version": 11,
            "params": ["conversationId": conversationID, "hostId": host, "change": ["type": "patches", "baseRevision": baseRevision, "revision": revision, "patches": patches]]]) }
    }
    func client(timeout: TimeInterval = 0.2, maximumFrameBytes: Int = 9_437_184,
                maximumRetainedStateBytes: Int = 33_554_432, frameDrainTimeoutSeconds: TimeInterval = 5) -> CodexDesktopIPCClient {
        .init(configuration: .init(socketURL: URL(fileURLWithPath: "/fixture/ipc.sock"), requestTimeoutSeconds: timeout,
            maximumFrameBytes: maximumFrameBytes, maximumRetainedStateBytes: maximumRetainedStateBytes,
            frameDrainTimeoutSeconds: frameDrainTimeoutSeconds), connector: { [self] _ in makeTransport() })
    }
    func connectedClient(timeout: TimeInterval = 0.2) async throws -> (CodexDesktopIPCClient, CodexDesktopIPCSnapshotRecorder, CodexDesktopConversationSnapshot) {
        let client = client(timeout: timeout), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await client.follow(conversationID: conversationID)
        return (client, recorder, try await recorder.wait(after: 0))
    }
    func waitForFollowingCount(_ count: Int) async throws {
        for _ in 0..<500 { if followingCount >= count { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    private func makeTransport() -> CodexDesktopIPCTransport {
        let stream = AsyncStream<Data>.makeStream()
        lock.withLock { continuation = stream.continuation }
        return .init(chunks: stream.stream, write: { [self] data in try receive(data) }, close: { stream.continuation.finish() })
    }
    private func receive(_ data: Data) throws {
        var decoder = CodexDesktopIPCFrameDecoder(maximumFrameBytes: 9_437_184)
        for payload in try decoder.append(data) {
            guard let message = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw CodexDesktopIPCError.invalidMessage }
            lock.withLock {
                messages.append(message)
                let method = message["method"] as? String
                if message["type"] as? String == "request", let id = message["requestId"] as? String {
                    if method == "initialize" { response(id: id, method: method!, owner: "fixture-client", result: ["clientId": "fixture-client"]) }
                    else if method == "thread-owner-discovery" {
                        guard ownerDiscoveryReady else { return }
                        if let candidate = message["targetClientId"] as? String, candidate != "fixture-owner" {
                            emitLocked(["type": "response", "requestId": id, "resultType": "error", "error": "no-client-found"])
                        } else { response(id: id, method: method!, owner: "fixture-owner", result: ["supportsUntrustedAppInput": supportsInput]) }
                    } else if acknowledgeSubmissions, let method {
                        if method == "thread-follower-steer-turn",
                           (state["turns"] as? [[String: Any]])?.last?["status"] as? String != "inProgress" {
                            emitLocked(["type": "response", "requestId": id, "resultType": "error",
                                "error": "Cannot steer a conversation without an active turn"])
                            return
                        }
                        if (method == "thread-follower-steer-turn" || method == "thread-follower-start-turn"), let next = stateAfterSteer {
                            state = next; revision += 1
                        }
                        if method == "thread-follower-start-turn" {
                            response(id: id, method: method, owner: acknowledgementOwner,
                                result: ["result": ["turn": ["id": steerResultTurn]]])
                            return
                        }
                        response(id: id, method: method, owner: acknowledgementOwner,
                            result: method == "thread-follower-steer-turn" ? ["result": ["turnId": steerResultTurn]] : ["ok": true])
                    }
                } else if method == "thread-stream-following-changed", let params = message["params"] as? [String: Any], params["following"] as? Bool == true {
                    host = params["hostId"] as? String ?? "local"
                    if automaticSnapshots { emitStateLocked(conversationID: params["conversationId"] as? String) }
                }
            }
        }
    }
    private func response(id: String, method: String, owner: String, result: [String: Any]) {
        emitLocked(["type": "response", "requestId": id, "resultType": "success", "method": method, "handledByClientId": owner, "result": result])
    }
    private func emitStateLocked(version: Int = 11, conversationID requested: String? = nil) {
        let selected = requested ?? conversationID
        let content: (state: [String: Any], revision: Int64)? = selected == conversationID ? (state: state, revision: revision) : additionalStates[selected]
        guard let content else { return }
        emitLocked(["type": "broadcast", "method": "thread-stream-state-changed", "sourceClientId": "fixture-owner", "version": version,
            "params": ["conversationId": selected, "hostId": host, "change": ["type": "snapshot", "revision": content.revision, "conversationState": content.state]]])
    }
    private func emitLocked(_ message: [String: Any]) {
        let payload = try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        continuation?.yield(try! CodexDesktopIPCFrameDecoder.frame(payload, maximumFrameBytes: 9_437_184))
    }
}

actor CodexDesktopIPCSnapshotRecorder {
    private var values: [CodexDesktopConversationSnapshot] = []
    private var states: [CodexDesktopIPCConnectionState] = []
    private var invalidations: [CodexDesktopIPCInvalidation] = []
    var latest: CodexDesktopConversationSnapshot? { values.last }
    var count: Int { values.count }
    var isConnected: Bool { states.last == .connected }
    func recordInvalidation(_ value: CodexDesktopIPCInvalidation) { invalidations.append(value) }
    func waitForInvalidation(after count: Int) async throws -> CodexDesktopIPCInvalidation {
        for _ in 0..<500 { if invalidations.count > count, let value = invalidations.last { return value }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func record(_ value: CodexDesktopConversationSnapshot) { values.append(value) }
    func recordState(_ value: CodexDesktopIPCConnectionState) { states.append(value) }
    func wait(after count: Int) async throws -> CodexDesktopConversationSnapshot {
        for _ in 0..<500 { if values.count > count, let value = values.last { return value }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func waitForConnection() async throws {
        for _ in 0..<500 { if states.contains(.connected) { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func waitForDisconnect() async throws {
        for _ in 0..<500 { if states.contains(.disconnected) { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
}
