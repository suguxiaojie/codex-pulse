import Foundation
import Darwin

/// Connects only to an existing same-user leader. Never spawns, initializes or loads a session.
final class GrokSharedClient: @unchecked Sendable {
    struct Snapshot: Equatable {
        var revision: UInt64 = 0
        var requests: [GrokQuestionRequest] = []
        var submitted: Set<String> = []
        var status = "等待下次正常启动 Grok，自动接入新请求"
    }
    private let queue = DispatchQueue(label: "com.coverai.grok.questions", qos: .utility)
    private let socketURL: URL
    private var timer: DispatchSourceTimer?
    private var fd: Int32 = -1
    private var ready = false
    private var input = Data(), output = Data()
    private var state = GrokQuestionState()
    private var bindings: [String: String] = [:]
    private var verified: Set<String> = []
    private var queries: [String: (String, String)] = [:]
    private var queriedAt: [String: Date] = [:]
    private var lastConnect = Date.distantPast
    private var lastPublished = Snapshot()
    var onSnapshot: (@Sendable (Snapshot) -> Void)?

    init(socketURL: URL) { self.socketURL = socketURL }
    // ExtMethodResult<SessionInfoResponse> is {result:{result:{sessionId,cwd,...}}}, not {success,data}.
    static func confirmsSession(_ object: [String: Any], id: String, cwd: String) -> Bool {
        guard object["error"] == nil, let envelope = object["result"] as? [String: Any], envelope["error"] == nil,
              let info = envelope["result"] as? [String: Any] else { return false }
        return info["sessionId"] as? String == id && info["cwd"] as? String == cwd
    }
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now(), repeating: .milliseconds(200))
            clock.setEventHandler { [weak self] in self?.tick() }
            timer = clock; clock.resume()
        }
    }
    func stop() { queue.async { [self] in timer?.cancel(); timer = nil; disconnect(); publish("共享问答已关闭") } }
    func updateSessions(_ sessions: [String: String]) {
        queue.async { [self] in
            verified = verified.filter { bindings[$0] == sessions[$0] }
            bindings = sessions
            queriedAt = queriedAt.filter { sessions[$0.key] != nil }
            queries = queries.filter { sessions[$0.value.0] == $0.value.1 }
            verified.formIntersection(sessions.keys)
            state.restrict(to: verified)
            if bindings.isEmpty { disconnect() }
            subscribe(); publish()
        }
    }
    func submit(_ request: GrokQuestionRequest, action: String = "answers", selections: [String: [String]], texts: [String: String]) async -> String {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                tick() // Drain already-arrived resolutions before accepting a click.
                guard fd >= 0, ready, let payload = state.submit(request, action: action, selections: selections, texts: texts) else {
                    continuation.resume(returning: "请求已失效或回答已提交，请在 Grok 原终端查看"); return
                }
                if !enqueueACP(payload) { disconnect(); publish("提交结果未确认，请在 Grok 原终端查看") }
                else { flush(); publish() }
                continuation.resume(returning: "回答已提交，结果请在 Grok 原终端确认；不会自动重发")
            }
        }
    }
    private func tick() {
        if fd < 0 {
            if !bindings.isEmpty && Date().timeIntervalSince(lastConnect) >= 2 { connectExisting() }
            return
        }
        flush()
        guard fd >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        for _ in 0..<16 {
            let count = recv(fd, &bytes, bytes.count, MSG_DONTWAIT)
            if count == 0 { disconnect(); publish(); return }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK { disconnect(); publish() }
                break
            }
            input.append(contentsOf: bytes.prefix(count))
            guard input.count <= 4_194_308 else { disconnect(); publish("共享响应过大，已交回 Grok 终端"); return }
            while input.count >= 4 {
                let length = input.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard length > 0, length <= 4_194_304 else { disconnect(); publish("共享帧无效，已断开"); return }
                guard input.count >= length + 4 else { break }
                let data = Data(input.dropFirst(4).prefix(length)); input.removeFirst(length + 4)
                guard let frame = GrokJSON.object(data) else { disconnect(); publish("共享协议无效"); return }
                consume(frame)
                if fd < 0 { return }
            }
        }
        subscribe(); publish()
    }
    private func connectExisting() {
        lastConnect = Date()
        var metadata = stat()
        guard lstat(socketURL.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFSOCK,
              metadata.st_uid == getuid(), metadata.st_mode & 0o022 == 0 else { publish(); return }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketURL.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { publish("共享 Socket 路径过长"); return }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: path.map { UInt8(bitPattern: $0) }) }
        let candidate = socket(AF_UNIX, SOCK_STREAM, 0)
        guard candidate >= 0 else { return }
        guard fcntl(candidate, F_SETFL, O_NONBLOCK) == 0 else { close(candidate); return }
        var noPipe: Int32 = 1
        setsockopt(candidate, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        var uid: uid_t = 0, gid: gid_t = 0
        guard result == 0, getpeereid(candidate, &uid, &gid) == 0, uid == getuid() else { close(candidate); return }
        fd = candidate; ready = false; state.reset(); verified = []; queries = [:]
        _ = enqueue(["type": "register", "client_type": "CodexPulse", "mode": "stdio", "capabilities": ["yolo_mode": false, "auto_mode": false]])
        flush(); publish("正在连接 Grok 共享问答")
    }
    private func consume(_ frame: [String: Any]) {
        switch frame["type"] as? String {
        case "registered":
            guard GrokJSON.integer(frame["leader_protocol_version"]) == 1 else { disconnect(); publish("Grok 共享协议版本不受支持"); return }
            ready = frame["ready"] as? Bool == true
        case "leader_ready": ready = true
        case "acp":
            guard let text = frame["payload"] as? String, let object = GrokJSON.object(Data(text.utf8)) else { return }
            if let id = object["id"] as? String, let expected = queries.removeValue(forKey: id) {
                if Self.confirmsSession(object, id: expected.0, cwd: expected.1), bindings[expected.0] == expected.1 {
                    verified.insert(expected.0); state.restrict(to: verified)
                }
            } else { state.consume(object) }
        case "shutdown", "shutting_down", "error": disconnect()
        default: break
        }
    }
    private func subscribe() {
        guard ready, fd >= 0 else { return }
        for (id, cwd) in bindings where !verified.contains(id) && !queries.values.contains(where: { $0.0 == id }) {
            guard Date().timeIntervalSince(queriedAt[id] ?? .distantPast) >= 2 else { continue }
            let queryID = "pulse-info-" + UUID().uuidString
            queries[queryID] = (id, cwd); queriedAt[id] = Date()
            if !enqueueACP(["jsonrpc": "2.0", "id": queryID, "method": "_x.ai/session/info", "params": ["sessionId": id]]) { disconnect(); return }
        }
    }
    @discardableResult private func enqueueACP(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let payload = String(data: data, encoding: .utf8) else { return false }
        return enqueue(["type": "acp", "payload": payload])
    }
    @discardableResult private func enqueue(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 262_144,
              output.count + data.count + 4 <= 524_288 else { return false }
        var header = UInt32(data.count).bigEndian
        output.append(Data(bytes: &header, count: 4)); output.append(data); return true
    }
    private func flush() {
        while fd >= 0 && !output.isEmpty {
            let count = output.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, MSG_DONTWAIT) }
            if count > 0 { output.removeFirst(count) }
            else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { break }
            else { disconnect(); break }
        }
    }
    private func disconnect() {
        if fd >= 0 { close(fd) }; fd = -1; ready = false
        input = Data(); output = Data(); state.reset(); verified = []; queries = [:]; queriedAt = [:]
    }
    private func publish(_ status: String? = nil) {
        var snapshot = Snapshot(revision: lastPublished.revision, requests: state.requests.values.filter { verified.contains($0.sessionID) }.sorted { $0.id < $1.id },
            submitted: state.submitted, status: status ?? (ready ? "共享问答已连接 · 新请求自动接入" : "等待下次正常启动 Grok，自动接入新请求"))
        if snapshot != lastPublished { snapshot.revision &+= 1; lastPublished = snapshot; onSnapshot?(snapshot) }
    }
    deinit { timer?.cancel(); if fd >= 0 { close(fd) } }
}
