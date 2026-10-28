import Foundation
import Darwin

/// Claude CLI's own process registry. It proves activity without restoring old approval capabilities.
struct ClaudeLiveSessionRegistry {
    struct ProcessIdentity: Equatable {
        let pid: pid_t
        let startedAt: Date
    }
    struct Record {
        let sessionID: String
        let process: ProcessIdentity
        let cwd: String
        let title: String?
        let status: String
        let statusAt: Date
        let transcriptPath: String?
    }
    struct ProcessInfo {
        let name: String
        let startedAt: Date
        let uid: uid_t
    }
    let configurationDirectory: URL

    static func processInfo(_ pid: pid_t) -> ProcessInfo? {
        guard pid > 1 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size else { return nil }
        var name = withUnsafeBytes(of: info.kp_proc.p_comm) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        // Native Claude installs use a version number as their executable's kernel name.
        if name != "claude" {
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let count = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            if count > 0 {
                let executable = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
                let versions = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local/share/claude/versions").resolvingSymlinksInPath()
                if executable.deletingLastPathComponent() == versions, executable.lastPathComponent == name { name = "claude" }
            }
        }
        let start = info.kp_proc.p_un.__p_starttime
        return .init(name: name, startedAt: Date(timeIntervalSince1970:
            Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000), uid: info.kp_eproc.e_ucred.cr_uid)
    }
    static func isCurrent(_ identity: ProcessIdentity) -> Bool {
        guard let info = processInfo(identity.pid) else { return false }
        return info.uid == getuid() && info.name == "claude" && info.startedAt == identity.startedAt
    }
    static func processStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.string(from: date)
    }
    private static func normalizedStamp(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func read(includeTranscripts: Bool = false, now: Date = Date(),
              lookup: (pid_t) -> ProcessInfo? = Self.processInfo) -> [Record] {
        let manager = FileManager.default
        let root = configurationDirectory.appendingPathComponent("sessions").resolvingSymlinksInPath()
        guard let files = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var records: [Record] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(256) {
            guard file.pathExtension == "json", let pid = Int32(file.deletingPathExtension().lastPathComponent), pid > 1,
                  file.resolvingSymlinksInPath().deletingLastPathComponent() == root,
                  let attributes = try? manager.attributesOfItem(atPath: file.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            let data = try? handle.read(upToCount: 65_537)
            try? handle.close()
            guard let data, data.count <= 65_536,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let declaredPID = object["pid"] as? NSNumber, CFGetTypeID(declaredPID) != CFBooleanGetTypeID(),
                  declaredPID.doubleValue == Double(pid), object["pidDomain"] as? String == "darwin",
                  object["kind"] as? String == "interactive",
                  let id = object["sessionId"] as? String, UUID(uuidString: id) != nil,
                  let cwd = object["cwd"] as? String, cwd.hasPrefix("/"), cwd.utf8.count <= 4_096,
                  let stamp = object["procStart"] as? String,
                  let process = lookup(pid), process.uid == getuid(), process.name == "claude",
                  Self.normalizedStamp(stamp) == Self.processStamp(process.startedAt),
                  let status = object["status"] as? String,
                  let milliseconds = object["statusUpdatedAt"] as? NSNumber,
                  CFGetTypeID(milliseconds) != CFBooleanGetTypeID(), milliseconds.doubleValue.isFinite else { continue }
            let statusAt = Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
            guard statusAt >= process.startedAt.addingTimeInterval(-1), statusAt <= now.addingTimeInterval(5) else { continue }
            records.append(.init(sessionID: id, process: .init(pid: pid, startedAt: process.startedAt), cwd: cwd,
                title: (object["name"] as? String).map { String($0.prefix(160)) }, status: status, statusAt: statusAt,
                transcriptPath: includeTranscripts && status == "busy" ? transcriptPath(for: id) : nil))
        }
        // The same native session owned by multiple processes is ambiguous.
        let counts = Dictionary(grouping: records, by: \.sessionID).mapValues(\.count)
        return records.filter { counts[$0.sessionID] == 1 }
    }
    private func transcriptPath(for id: String) -> String? {
        let root = configurationDirectory.appendingPathComponent("projects").resolvingSymlinksInPath()
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        let matches = directories.prefix(512).compactMap { directory -> String? in
            let file = directory.appendingPathComponent(id + ".jsonl").resolvingSymlinksInPath()
            guard file.path.hasPrefix(root.path + "/"), file.lastPathComponent == id + ".jsonl",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return file.path
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
