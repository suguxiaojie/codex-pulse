import Darwin
import Foundation

enum ClaudeHookProcess {
    static let intermediaries: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "login", "timeout"]

    /// At most eight ancestors, including the immediate parent. Missing evidence fails closed.
    static func owner(startingAt parent: pid_t,
                      lookup: (pid_t) -> (parent: pid_t, name: String)?) -> (pid: pid_t, name: String)? {
        var pid = parent
        var visited: Set<pid_t> = []
        for _ in 0..<8 {
            guard pid > 1, visited.insert(pid).inserted, let process = lookup(pid),
                  !process.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let name = URL(fileURLWithPath: process.name).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let executable = String(name.drop(while: { $0 == "-" })).lowercased()
            guard !executable.isEmpty else { return nil }
            if !intermediaries.contains(executable) { return (pid, name) }
            pid = process.parent
        }
        return nil
    }

    static func lookup(_ pid: pid_t) -> (parent: pid_t, name: String)? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard !name.isEmpty else { return nil }
        return (info.kp_eproc.e_ppid, name)
    }
}
