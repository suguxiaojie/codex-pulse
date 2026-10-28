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

/// Immutable derived data for one inventory/filter combination. No conversation body is copied.
final class SessionLibraryViewData {
    let allProjects: [ContinuityProjectGroup]
    let projects: [ContinuityProjectGroup]
    let completeProjectsByID: [String: ContinuityProjectGroup]
    let summariesByID: [String: SessionProjectSummary]
    let visibleThreadIDs: [String]

    init(allProjects: [ContinuityProjectGroup], completeProjectsByID: [String: ContinuityProjectGroup],
         projects: [ContinuityProjectGroup]) {
        self.allProjects = allProjects; self.projects = projects
        self.completeProjectsByID = completeProjectsByID
        summariesByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, SessionProjectSummary(threads: $0.threads)) })
        visibleThreadIDs = projects.flatMap { $0.threads.map(\.id) }
    }
}

/// A single-view cache: inventory changes regroup; search/filter changes only refilter.
final class SessionLibraryViewCache {
    private var snapshot: SessionContinuitySnapshot?
    private var allProjects: [ContinuityProjectGroup] = []
    private var completeProjectsByID: [String: ContinuityProjectGroup] = [:]
    private var query = ""
    private var filter = SessionLibraryFilter.all
    private var locale = ""
    private var value: SessionLibraryViewData?

    func resolve(snapshot: SessionContinuitySnapshot, query: String, filter: SessionLibraryFilter) -> SessionLibraryViewData {
        if self.snapshot != snapshot {
            self.snapshot = snapshot
            allProjects = snapshot.projectGroups
            completeProjectsByID = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
            value = nil
        }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLocale = Locale.current.identifier
        if let value, self.query == search, self.filter == filter, locale == currentLocale { return value }
        let projects = SessionLibraryPresentation.groups(projects: allProjects, query: search, filter: filter)
        let result = SessionLibraryViewData(allProjects: allProjects, completeProjectsByID: completeProjectsByID, projects: projects)
        self.query = search; self.filter = filter; locale = currentLocale; value = result
        return result
    }
}
