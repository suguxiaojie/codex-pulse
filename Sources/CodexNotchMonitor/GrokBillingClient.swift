import Foundation
import Darwin

/// The official CLI owns authentication. This client never receives credentials or opens a model session.
final class GrokBillingClient: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case missingCLI, launch, timeout, cancelled, malformed, authentication, unsupported, service, upstreamUnavailable, network, noQuota
        var title: String {
            switch self {
            case .missingCLI: return "未找到官方 Grok CLI"
            case .launch: return "Grok CLI 无法启动"
            case .timeout: return "Grok 额度查询超时"
            case .cancelled: return "查询已取消"
            case .malformed: return "Grok 额度响应格式无效"
            case .authentication: return "请先在终端运行 grok login"
            case .unsupported: return "此版本 Grok CLI 不支持额度查询"
            case .service: return "Grok 额度服务暂不可用"
            case .upstreamUnavailable: return "Grok 上游额度服务暂时不可用，稍后自动刷新"
            case .network: return "Grok 额度查询网络失败，请检查网络或稍后刷新"
            case .noQuota: return "当前登录未提供订阅额度"
            }
        }
    }
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
    static func executable(home: URL) -> URL? {
        let user = FileManager.default.homeDirectoryForCurrentUser
        return [user.appendingPathComponent(".local/bin/grok"), home.appendingPathComponent("bin/grok"),
                URL(fileURLWithPath: "/opt/homebrew/bin/grok"), URL(fileURLWithPath: "/usr/local/bin/grok")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    func fetch(executable: URL, home: URL, timeout: TimeInterval = 20) throws -> GrokQuotaSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        for attempt in 0..<3 {
            if attempt > 0 {
                let pauseUntil = min(deadline, Date().addingTimeInterval(Double(attempt) * 0.6))
                while Date() < pauseUntil {
                    lock.lock(); let stopped = cancelled; lock.unlock()
                    if stopped { throw Failure.cancelled }
                    Thread.sleep(forTimeInterval: min(0.05, max(0, pauseUntil.timeIntervalSinceNow)))
                }
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw Failure.timeout }
            do { return try fetchOnce(executable: executable, home: home, timeout: remaining) }
            catch let error as Failure {
                guard attempt < 2, [.service, .upstreamUnavailable, .network, .timeout].contains(error),
                      deadline.timeIntervalSinceNow > Double(attempt + 1) * 0.6 + 0.2 else { throw error }
            }
        }
        throw Failure.service
    }
    private func fetchOnce(executable: URL, home: URL, timeout: TimeInterval) throws -> GrokQuotaSnapshot {
        let p = Process(), input = Pipe(), output = Pipe()
        p.executableURL = executable; p.arguments = ["agent", "--no-leader", "stdio"]
        p.currentDirectoryURL = home
        var environment = ProcessInfo.processInfo.environment
        environment["GROK_HOME"] = home.path
        p.environment = environment
        p.standardInput = input; p.standardOutput = output; p.standardError = FileHandle.nullDevice
        let state = ResponseState()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            state.consume(data)
        }
        var launched = false
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if p.isRunning {
                p.terminate()
                let until = Date().addingTimeInterval(1)
                while p.isRunning && Date() < until { Thread.sleep(forTimeInterval: 0.01) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            if launched { p.waitUntilExit() }
            try? output.fileHandleForReading.close()
            lock.lock(); if process === p { process = nil }; lock.unlock()
        }
        lock.lock()
        if cancelled { lock.unlock(); throw Failure.cancelled }
        process = p
        do { try p.run(); launched = true; lock.unlock() } catch { lock.unlock(); throw Failure.launch }
        let request = Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"_x.ai/billing\",\"params\":{}}\n".utf8)
        do { try input.fileHandleForWriting.write(contentsOf: request) } catch { throw Failure.launch }
        guard state.ready.wait(timeout: .now() + timeout) == .success else { throw Failure.timeout }
        switch state.result() {
        case .success(let value):
            guard let quota = GrokQuotaSnapshot.decode(value, now: Date()) else { throw Failure.noQuota }
            return quota
        case .failure(let error): throw error
        }
    }
    private final class ResponseState: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var buffer = Data()
        private var count = 0
        private var response: Result<[String: Any], Failure>?
        func result() -> Result<[String: Any], Failure> { lock.lock(); defer { lock.unlock() }; return response ?? .failure(.malformed) }
        func consume(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            guard response == nil else { return }
            func finish(_ value: Result<[String: Any], Failure>) { response = value; ready.signal() }
            guard !data.isEmpty else { finish(.failure(.service)); return }
            count += data.count
            guard count <= 1_048_576 else { finish(.failure(.malformed)); return }
            buffer.append(data)
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard let object = GrokJSON.object(line), object["jsonrpc"] as? String == "2.0",
                      GrokJSON.integer(object["id"]) == 1 else { continue }
                if let error = object["error"] as? [String: Any] {
                    let code = GrokJSON.number(error["code"])
                    // Classify fixed CLI error prefixes without retaining or displaying the upstream body.
                    let detail = error["data"] as? String ?? ""
                    let failure: Failure = code == -32601 ? .unsupported : code == -32000 ? .authentication
                        : detail.hasPrefix("Billing service error:") ? .upstreamUnavailable
                        : detail.hasPrefix("Failed to fetch billing data:") ? .network : .service
                    finish(.failure(failure))
                } else if let value = object["result"] as? [String: Any] { finish(.success(value)) }
                else { finish(.failure(.malformed)) }
                return
            }
        }
    }
}
