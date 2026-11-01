import Foundation

@main
enum CodexProxyTransportTests {
    static func main() throws {
        if CommandLine.arguments.contains("--live") {
            let executable = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex")
            let transport = try CodexProxyTransport(executable: executable)
            defer { transport.close() }
            let result = try transport.request("thread/loaded/list", [:])
            print("Read-only live proxy connected; loaded thread count: \((result["data"] as? [String])?.count ?? 0)")
            return
        }
        let executable = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/CodexProxyFixture.py")
        defer { unsetenv("PULSE_PROXY_FIXTURE") }
        for mode in ["normal", "wrong-id", "bad-upgrade", "oversized", "closed", "rpc-error"] {
            setenv("PULSE_PROXY_FIXTURE", mode, 1)
            var failed = false
            do {
                let transport = try CodexProxyTransport(executable: executable)
                defer { transport.close() }
                let result = try transport.request("thread/loaded/list", [:])
                guard result["data"] as? [String] == ["fixture-thread"] else { fatalError("wrong result") }
                do { _ = try transport.request("thread/start", [:]); fatalError("unsafe method allowed") } catch { }
                do { _ = try transport.request("project/update", [:]); fatalError("question connection may not rename projects") } catch { }
            } catch { failed = true }
            guard failed == !["normal", "wrong-id"].contains(mode) else { fatalError("Unexpected result: " + mode) }
        }
        setenv("PULSE_PROXY_FIXTURE", "normal", 1)
        let projectTransport = try CodexProxyTransport(executable: executable, scope: .projects)
        defer { projectTransport.close() }
        for method in ["turn/steer", "thread/start", "project/delete", "project/create"] {
            do { _ = try projectTransport.request(method, [:]); fatalError("project transport scope widened") } catch { }
        }
        print("Proxy transport: upgrade, masking, fragmented frames, ping/pong, unrelated IDs, limits, close, RPC rejection and method allowlist passed")
    }
}
