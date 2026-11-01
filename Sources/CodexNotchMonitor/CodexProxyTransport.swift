import Foundation
import Darwin
import CryptoKit

/// A bounded WebSocket client on the existing daemon's local byte-stream proxy.
/// Only the child proxy belongs to us; the daemon and its sessions are never stopped.
final class CodexProxyTransport {
    typealias JSON = [String: Any]
    enum Failure: Error { case unavailable, protocolViolation, timeout, rejected }
    enum Scope { case questions, projects }
    private let scope: Scope
    private var process: Process?
    private var fd: Int32 = -1
    private var buffer = Data()
    private var sequence = 0
    private var deadline = Date.distantPast
    private let maximumBytes = 8 * 1_048_576

    init(executable: URL, scope: Scope = .questions, socketURL: URL? = nil) throws {
        self.scope = scope
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw Failure.unavailable }
        fd = pair[0]
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let child = FileHandle(fileDescriptor: pair[1], closeOnDealloc: true)
        let task = Process()
        task.executableURL = executable
        task.arguments = ["app-server", "proxy"]
        if let socketURL { task.arguments! += ["--sock", socketURL.path] }
        task.standardInput = child; task.standardOutput = child
        task.standardError = FileHandle.nullDevice
        process = task
        do {
            try task.run()
            try child.close()
            deadline = Date().addingTimeInterval(4)
            let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
            try write(Data(("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n").utf8))
            let separator = Data("\r\n\r\n".utf8)
            while buffer.range(of: separator) == nil {
                guard buffer.count < 16_384 else { throw Failure.protocolViolation }
                try receive()
            }
            let end = buffer.range(of: separator)!.upperBound
            let header = String(decoding: buffer.prefix(end), as: UTF8.self)
            let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            guard header.components(separatedBy: "\r\n").first?.contains(" 101 ") == true,
                  header.components(separatedBy: "\r\n").contains(where: {
                      let parts = $0.split(separator: ":", maxSplits: 1)
                      return parts.count == 2 && parts[0].lowercased() == "sec-websocket-accept"
                        && parts[1].trimmingCharacters(in: .whitespaces) == accept
                  }) else { throw Failure.protocolViolation }
            buffer.removeFirst(end)
            _ = try request("initialize", ["clientInfo": ["name": scope == .projects ? "codex-pulse-projects" : "codex-pulse-questions", "version": "1"],
                                           "capabilities": ["experimentalApi": true]])
            deadline = Date().addingTimeInterval(4)
            try send(["method": "initialized"])
        } catch { close(); throw error }
    }

    deinit { close() }
    func close() {
        if fd >= 0 { Darwin.shutdown(fd, SHUT_RDWR); Darwin.close(fd); fd = -1 }
        if let process, process.isRunning { process.terminate() }
        process = nil; buffer.removeAll()
    }

    func request(_ method: String, _ params: JSON) throws -> JSON {
        let allowed = scope == .projects
            ? ["initialize", "project/list", "project/read", "project/update"]
            : ["initialize", "thread/loaded/list", "thread/read", "thread/turns/list", "thread/items/list", "turn/steer"]
        guard allowed.contains(method),
              process?.isRunning == true, fd >= 0 else { throw Failure.unavailable }
        deadline = Date().addingTimeInterval(5)
        sequence += 1
        try send(["id": sequence, "method": method, "params": params])
        for _ in 0..<1024 {
            let data = try message()
            guard let value = try JSONSerialization.jsonObject(with: data) as? JSON else { throw Failure.protocolViolation }
            // We never resume or subscribe, and never answer server-originated requests.
            if value["method"] != nil { continue }
            guard let id = value["id"] as? Int, id == sequence else { continue }
            guard value["error"] == nil, let result = value["result"] as? JSON else { throw Failure.rejected }
            return result
        }
        throw Failure.protocolViolation
    }

    private func ready(_ events: Int16) throws {
        guard fd >= 0 else { throw Failure.unavailable }
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw Failure.timeout }
            var item = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&item, 1, Int32(min(remaining * 1000 + 1, 5000)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0, item.revents & events != 0 else { throw Failure.unavailable }
            return
        }
    }
    private func write(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            try ready(Int16(POLLOUT))
            let count = data.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: offset), data.count - offset, MSG_DONTWAIT) }
            if count < 0 && [EINTR, EAGAIN].contains(errno) { continue }
            guard count > 0 else { throw Failure.unavailable }
            offset += count
        }
    }
    private func receive() throws {
        try ready(Int16(POLLIN))
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = Darwin.recv(fd, &bytes, bytes.count, MSG_DONTWAIT)
        if count < 0 && [EINTR, EAGAIN].contains(errno) { return }
        guard count > 0, buffer.count + count <= maximumBytes + 16_384 else { throw Failure.unavailable }
        buffer.append(contentsOf: bytes.prefix(count))
    }
    private func read(_ count: Int) throws -> Data {
        guard count <= maximumBytes else { throw Failure.protocolViolation }
        while buffer.count < count { try receive() }
        let result = Data(buffer.prefix(count)); buffer.removeFirst(count); return result
    }
    private func frame(_ opcode: UInt8, _ data: Data) throws {
        guard data.count <= maximumBytes else { throw Failure.protocolViolation }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        var bytes = Data([0x80 | opcode])
        if data.count < 126 { bytes.append(0x80 | UInt8(data.count)) }
        else if data.count <= 65_535 {
            bytes.append(0x80 | 126)
            bytes.append(UInt8(data.count >> 8)); bytes.append(UInt8(data.count & 255))
        } else {
            bytes.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((UInt64(data.count) >> shift) & 255)) }
        }
        bytes.append(contentsOf: mask)
        bytes.append(contentsOf: data.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        try write(bytes)
    }
    private func send(_ json: JSON) throws { try frame(1, JSONSerialization.data(withJSONObject: json)) }
    private func message() throws -> Data {
        var result = Data(); var started = false
        while true {
            let header = [UInt8](try read(2))
            let final = header[0] & 0x80 != 0, opcode = header[0] & 15
            guard header[0] & 0x70 == 0, header[1] & 0x80 == 0 else { throw Failure.protocolViolation }
            var length = UInt64(header[1] & 127)
            if length == 126 { length = try read(2).reduce(0) { ($0 << 8) | UInt64($1) } }
            else if length == 127 { length = try read(8).reduce(0) { ($0 << 8) | UInt64($1) } }
            guard length <= maximumBytes, result.count + Int(length) <= maximumBytes else { throw Failure.protocolViolation }
            if opcode >= 8 { guard final, length <= 125 else { throw Failure.protocolViolation } }
            let payload = try read(Int(length))
            if opcode == 8 { throw Failure.unavailable }
            if opcode == 9 { try frame(10, payload); continue }
            if opcode == 10 { continue }
            guard (opcode == 1 && !started) || (opcode == 0 && started) else { throw Failure.protocolViolation }
            started = true; result.append(payload)
            if final { return result }
        }
    }
}
