import Foundation
import Darwin

@main enum ClaudeHookProcessTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ title: String) {
            precondition(condition, title); checks += 1
        }
        for shell in ClaudeHookProcess.intermediaries.sorted() + ["/bin/zsh", "-bash"] {
            let chain: [pid_t: (parent: pid_t, name: String)] = [10: (20, shell), 20: (1, "claude")]
            let owner = ClaudeHookProcess.owner(startingAt: 10) { chain[$0] }
            expect(owner?.pid == 20 && owner?.name == "claude", "skip intermediary \(shell)")
        }
        var chain: [pid_t: (parent: pid_t, name: String)] = [:]
        for pid: pid_t in 10...16 { chain[pid] = (pid + 1, "sh") }
        chain[17] = (18, "node")
        expect(ClaudeHookProcess.owner(startingAt: 10) { chain[$0] }?.pid == 17, "eighth ancestor is permitted")
        chain[17] = (18, "env"); chain[18] = (1, "claude")
        var visited: [pid_t] = []
        expect(ClaudeHookProcess.owner(startingAt: 10) { visited.append($0); return chain[$0] } == nil,
            "ninth ancestor is beyond the limit")
        expect(visited.count == 8, "at most eight lookups")
        chain = [10: (20, "sh"), 20: (10, "bash")]
        visited = []
        expect(ClaudeHookProcess.owner(startingAt: 10) { visited.append($0); return chain[$0] } == nil,
            "cyclic shell chain rejected")
        expect(visited == [10, 20], "loop detected before repeating a lookup")
        expect(ClaudeHookProcess.owner(startingAt: 10) { _ in (10, "sh") } == nil, "self cycle rejected")
        expect(ClaudeHookProcess.owner(startingAt: 10) { _ in nil } == nil, "unavailable process omitted")
        expect(ClaudeHookProcess.owner(startingAt: 10) { _ in (20, "") } == nil, "empty name omitted")
        expect(ClaudeHookProcess.owner(startingAt: 10) { _ in (20, "  ") } == nil, "blank name omitted")
        for pid: pid_t in [-1, 0, 1] {
            expect(ClaudeHookProcess.owner(startingAt: pid) { _ in preconditionFailure("must not inspect system PID") } == nil,
                "invalid or init PID omitted")
        }
        print("Claude Hook process ancestry: \(checks)/\(checks) passed")
    }
}
