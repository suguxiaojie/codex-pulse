import Foundation

/// Read-only presentation of the same filtered threads shown under a project.
struct SessionProjectSummary {
    let updatedAt: Date?
    let ownershipTitle: String
    let ownershipDetail: String
    let recoverableCount: Int
    let missingPathCount: Int

    var hasExceptions: Bool { recoverableCount + missingPathCount > 0 }

    var statusTitle: String {
        if recoverableCount > 0 && missingPathCount > 0 {
            return "\(recoverableCount + missingPathCount) 条异常"
        }
        if recoverableCount > 0 { return "\(recoverableCount) 条待恢复" }
        if missingPathCount > 0 { return "\(missingPathCount) 条路径缺失" }
        return "—"
    }

    var statusDetail: String {
        guard hasExceptions else { return "当前筛选范围内无待恢复或路径缺失的会话。" }
        return "当前筛选范围内：待恢复 \(recoverableCount) 条，路径缺失 \(missingPathCount) 条。"
    }

    init(threads: [LocalThreadRecord]) {
        updatedAt = threads.map(\.updatedAt).max()
        recoverableCount = threads.filter(\.canRecover).count
        missingPathCount = threads.filter { $0.visibility == .projectPathMissing }.count

        var accounts: [String: (alias: String, count: Int)] = [:]
        var baselineCount = 0
        var unknownCount = 0
        for thread in threads {
            let ownership = thread.ownership
            switch ownership.confidence {
            case .baseline:
                baselineCount += 1
            case .unknown:
                unknownCount += 1
            case .observed:
                guard let fingerprint = ownership.accountFingerprint, !fingerprint.isEmpty else {
                    unknownCount += 1
                    continue
                }
                let previous = accounts[fingerprint]
                let alias = ownership.accountAlias.flatMap { $0.isEmpty ? nil : $0 }
                    ?? previous?.alias ?? "已观察账号"
                accounts[fingerprint] = (alias, (previous?.count ?? 0) + 1)
            }
        }

        if threads.isEmpty {
            ownershipTitle = "—"
        } else if accounts.isEmpty {
            ownershipTitle = "未归属"
        } else if baselineCount + unknownCount > 0 {
            ownershipTitle = "部分归属"
        } else if accounts.count == 1 {
            ownershipTitle = accounts.values.first?.alias ?? "已观察账号"
        } else {
            ownershipTitle = "多账号"
        }

        var details = ["当前筛选范围内的 \(threads.count) 条会话"]
        let orderedAccounts = accounts.sorted {
            if $0.value.alias != $1.value.alias { return $0.value.alias < $1.value.alias }
            return $0.key < $1.key
        }
        details += orderedAccounts.map { "\($0.value.alias)：\($0.value.count) 条" }
        if baselineCount > 0 { details.append("基线前未记录：\(baselineCount) 条") }
        if unknownCount > 0 { details.append("尚未建立可靠归属：\(unknownCount) 条") }
        details.append("仅汇总已有归属证据，不按当前登录账号推断。")
        ownershipDetail = details.joined(separator: "\n")
    }
}
