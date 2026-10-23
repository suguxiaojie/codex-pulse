import Foundation

enum QuotaResetReason: String, Codable, Equatable {
    case officialCompleted
    case officialScheduled
    case natural
    case mixed
    case manualCredit
    case userConfirmed
    case unverified

    var title: String {
        switch self {
        case .officialCompleted, .officialScheduled, .mixed: return "Tibo 重置"
        case .natural: return "到期重置"
        case .manualCredit: return "手动重置"
        case .userConfirmed: return "手动重置"
        case .unverified: return "待确认重置"
        }
    }

    /// Classified events can update a recovery notification; expiry alone cannot.
    var isNotifiable: Bool { self != .unverified }

    var defaultDisplayType: QuotaResetDisplayType? {
        switch self {
        case .officialCompleted, .officialScheduled, .mixed: return .tibo
        case .natural: return .natural
        case .manualCredit, .userConfirmed: return .manual
        case .unverified: return nil
        }
    }
}

enum QuotaResetDisplayType: String, Codable, CaseIterable, Identifiable {
    case tibo
    case natural
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tibo: return "Tibo 重置"
        case .natural: return "到期重置"
        case .manual: return "手动重置"
        }
    }

    var representativeReason: QuotaResetReason {
        switch self {
        case .tibo: return .officialCompleted
        case .natural: return .natural
        case .manual: return .userConfirmed
        }
    }
}

struct QuotaResetConfirmationCandidate: Identifiable, Equatable {
    let id: String
    let detectedAt: Date
    let changes: [QuotaResetChange]
    var notificationID: String? = nil
    var isWaiting = true
    var historyEventID: String? = nil
    var communityEvidence: [TiboEvent] = []
    var associationNote = ""

    var title: String {
        if isWaiting { return "额度已恢复，正在等待社区证据" }
        return communityEvidence.isEmpty ? "历史恢复 · 原因未明" : "历史恢复 · 发现社区重置线索"
    }
}

struct QuotaResetChange: Codable, Equatable {
    let bucketID: String
    let bucketName: String
    let windowDurationMinutes: Int?
    let previousRemainingPercent: Int
    let currentRemainingPercent: Int

    var windowLabel: String {
        RateLimitWindow(
            usedPercent: 0,
            windowDurationMinutes: windowDurationMinutes,
            resetsAt: nil
        ).windowLabel
    }
}

struct QuotaResetEvent: Codable, Identifiable, Equatable {
    let id: String
    let detectedAt: Date
    let reason: QuotaResetReason
    let changes: [QuotaResetChange]
    let sourcePostID: String?
    let sourceURL: String?
    var userDisplayType: QuotaResetDisplayType?
    var communityAssociation: TiboEvent? = nil
    var notificationID: String? = nil

    init(
        id: String,
        detectedAt: Date,
        reason: QuotaResetReason,
        changes: [QuotaResetChange],
        sourcePostID: String?,
        sourceURL: String?,
        userDisplayType: QuotaResetDisplayType? = nil,
        notificationID: String? = nil
    ) {
        self.id = id
        self.detectedAt = detectedAt
        self.reason = reason
        self.changes = changes
        self.sourcePostID = sourcePostID
        self.sourceURL = sourceURL
        self.userDisplayType = userDisplayType
        self.notificationID = notificationID
    }

    var displayReason: QuotaResetReason {
        userDisplayType?.representativeReason ?? (communityAssociation == nil ? reason : .officialCompleted)
    }
}

struct QuotaResetEvaluation {
    let events: [QuotaResetEvent]
    let needsFeedRefresh: Bool
    var pendingNotifications: [QuotaResetEvent] = []
}

enum QuotaResetHistoryPresentation {
    static func historyExcludingCandidates(
        events: [QuotaResetEvent],
        candidates: [QuotaResetConfirmationCandidate]
    ) -> [QuotaResetEvent] {
        events.filter { event in
            event.reason != .unverified || !candidates.contains { candidate in
                candidate.detectedAt == event.detectedAt && candidate.changes == event.changes
            }
        }
    }

    static func uniqueCount(
        events: [QuotaResetEvent],
        candidates: [QuotaResetConfirmationCandidate]
    ) -> Int {
        Set(candidates.map(\.id)).count
            + historyExcludingCandidates(events: events, candidates: candidates).count
    }
}

/// Reports recovery immediately while retaining pending evidence separately.
final class QuotaResetMonitor {
    private struct WindowSnapshot: Codable, Equatable {
        let id: String
        let bucketID: String
        let bucketName: String
        let windowDurationMinutes: Int?
        let remainingPercent: Int
        let resetsAt: Date?
    }

    private struct Snapshot: Codable {
        let capturedAt: Date
        let contextSignature: String
        var accountID: String? = nil
        let windows: [WindowSnapshot]
    }

    private struct Pending: Codable {
        let detectedAt: Date
        let changes: [QuotaResetChange]
        var plans: [String]? = nil
        var notificationID: String? = nil
    }

    private struct State: Codable {
        var snapshot: Snapshot?
        var pending: [Pending]
        var history: [QuotaResetEvent]
        var manualResetRequestedAt: Date?
    }

    private let stateURL: URL
    private var state: State
    private var evidenceFeed: TiboFeed?

    init(stateURL: URL = AppPaths.supportDirectory.appendingPathComponent("quota-reset-state.json")) {
        self.stateURL = stateURL
        self.state = Self.load(from: stateURL) ?? State(
            snapshot: nil,
            pending: [],
            history: [],
            manualResetRequestedAt: nil
        )
    }

    var history: [QuotaResetEvent] { state.history }

    func updateEvidence(_ feed: TiboFeed) {
        evidenceFeed = feed
        associateHistoricalRecoveries()
    }

    private func associateHistoricalRecoveries() {
        let matches = state.history.indices.compactMap { index -> (Int, TiboEvent)? in
            let record = state.history[index]
            guard record.reason == .unverified, record.userDisplayType == nil, record.communityAssociation == nil,
                  let evidence = nearbyEvidence(in: evidenceFeed, detectedAt: record.detectedAt, changes: record.changes, plans: nil, now: Date()).first
            else { return nil }
            return (index, evidence)
        }
        guard !matches.isEmpty else { return }
        let previous = state.history
        do {
            try backupStateBeforeClassificationChange()
            for (index, evidence) in matches { state.history[index].communityAssociation = evidence }
            try writeState()
        } catch {
            state.history = previous
        }
    }

    var confirmableRecoveries: [QuotaResetConfirmationCandidate] {
        var seen = Set<String>()
        let candidates = state.pending.map { pending in
            var candidate = Self.confirmationCandidate(detectedAt: pending.detectedAt, changes: pending.changes)
            candidate.notificationID = pending.notificationID
            return decorate(candidate, plans: pending.plans)
        } + state.history.compactMap { event in
            guard event.reason == .unverified, event.userDisplayType == nil, event.communityAssociation == nil else { return nil }
            var candidate = Self.confirmationCandidate(detectedAt: event.detectedAt, changes: event.changes)
            candidate.notificationID = event.notificationID
            candidate.isWaiting = false
            candidate.historyEventID = event.id
            return decorate(candidate, plans: nil)
        }
        return candidates
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    func confirmUserReset(candidateID: String) -> QuotaResetEvent? {
        if let index = state.pending.firstIndex(where: {
            Self.confirmationCandidate(detectedAt: $0.detectedAt, changes: $0.changes).id == candidateID
        }) {
            let pending = state.pending.remove(at: index)
            let event = record(
                changes: pending.changes,
                reason: .userConfirmed,
                source: nil,
                now: pending.detectedAt,
                notificationID: pending.notificationID
            )
            persist()
            return event
        }

        if let index = state.history.firstIndex(where: { event in
            event.reason == .unverified && event.userDisplayType == nil && event.communityAssociation == nil
                && Self.confirmationCandidate(detectedAt: event.detectedAt, changes: event.changes).id == candidateID
        }) {
            let unverified = state.history.remove(at: index)
            let event = record(
                changes: unverified.changes,
                reason: .userConfirmed,
                source: nil,
                now: unverified.detectedAt,
                notificationID: unverified.notificationID
            )
            persist()
            return event
        }
        return nil
    }

    func markManualResetRequested(at date: Date = Date()) {
        state.manualResetRequestedAt = date
        persist()
    }

    func setDisplayType(
        eventID: String,
        displayType: QuotaResetDisplayType?
    ) -> QuotaResetEvent? {
        guard let index = state.history.firstIndex(where: { $0.id == eventID }) else {
            return nil
        }
        let normalizedDisplayType = displayType == state.history[index].reason.defaultDisplayType
            ? nil
            : displayType
        let previous = state.history[index].userDisplayType
        guard previous != normalizedDisplayType else { return state.history[index] }

        do {
            try backupStateBeforeClassificationChange()
            state.history[index].userDisplayType = normalizedDisplayType
            try writeState()
            return state.history[index]
        } catch {
            state.history[index].userDisplayType = previous
            return nil
        }
    }

    func evaluate(buckets: [RateLimitBucket], feed: TiboFeed?, now: Date = Date(), accountID: String? = nil) -> QuotaResetEvaluation {
        if let feed { evidenceFeed = feed }
        if let requestedAt = state.manualResetRequestedAt,
           now.timeIntervalSince(requestedAt) > 10 * 60 {
            state.manualResetRequestedAt = nil
        }
        let hasManualResetEvidence = state.manualResetRequestedAt.map {
            now.timeIntervalSince($0) >= -60 && now.timeIntervalSince($0) <= 10 * 60
        } ?? false
        let current = makeSnapshot(buckets: buckets, now: now, accountID: accountID)
        var events = expirePending(now: now)

        guard let previous = state.snapshot,
              now.timeIntervalSince(previous.capturedAt) <= 6 * 60 * 60,
              previous.contextSignature == current.contextSignature,
              previous.accountID == current.accountID else {
            state.snapshot = current
            persist()
            return QuotaResetEvaluation(events: events, needsFeedRefresh: false)
        }

        let oldByID = Dictionary(uniqueKeysWithValues: previous.windows.map { ($0.id, $0) })
        var changes: [QuotaResetChange] = []
        var naturalEvidence = false

        for window in current.windows {
            guard let old = oldByID[window.id],
                  window.remainingPercent >= 99,
                  old.remainingPercent <= 95,
                  window.remainingPercent - old.remainingPercent >= 5 else { continue }

            changes.append(QuotaResetChange(
                bucketID: window.bucketID,
                bucketName: window.bucketName,
                windowDurationMinutes: window.windowDurationMinutes,
                previousRemainingPercent: old.remainingPercent,
                currentRemainingPercent: window.remainingPercent
            ))
            naturalEvidence = naturalEvidence || isNaturalReset(old: old, current: window, now: now)
        }

        state.snapshot = current
        guard !changes.isEmpty else {
            persist()
            return QuotaResetEvaluation(events: events, needsFeedRefresh: false)
        }

        let notificationID = "quota-recovery-\(UUID().uuidString)"
        var pendingNotifications: [QuotaResetEvent] = []
        if hasManualResetEvidence {
            state.manualResetRequestedAt = nil
            if let event = record(changes: changes, reason: .manualCredit, source: nil, now: now, notificationID: notificationID) {
                events.append(event)
            }
        } else if let official = matchingOfficialEvent(in: feed, detectedAt: now, changes: changes, plans: buckets.compactMap(\.planType), now: now) {
            let reason: QuotaResetReason
            if naturalEvidence {
                reason = .mixed
            } else {
                reason = official.kind == .resetCompleted ? .officialCompleted : .officialScheduled
            }
            if let event = record(changes: changes, reason: reason, source: official, now: now, notificationID: notificationID) {
                events.append(event)
            }
        } else if naturalEvidence {
            if let event = record(changes: changes, reason: .natural, source: nil, now: now, notificationID: notificationID) {
                events.append(event)
            }
        } else {
            state.pending.append(Pending(detectedAt: now, changes: changes, plans: buckets.compactMap(\.planType), notificationID: notificationID))
            pendingNotifications.append(QuotaResetEvent(id: notificationID, detectedAt: now, reason: .unverified, changes: changes, sourcePostID: nil, sourceURL: nil, notificationID: notificationID))
        }

        persist()
        return QuotaResetEvaluation(events: events, needsFeedRefresh: !state.pending.isEmpty, pendingNotifications: pendingNotifications)
    }

    func reconcile(feed: TiboFeed, now: Date = Date()) -> [QuotaResetEvent] {
        evidenceFeed = feed
        var events = expirePending(now: now)
        var remaining: [Pending] = []

        for pending in state.pending {
            if let official = matchingOfficialEvent(in: feed, detectedAt: pending.detectedAt, changes: pending.changes, plans: pending.plans ?? [], now: now),
               let event = record(
                    changes: pending.changes,
                    reason: official.kind == .resetCompleted ? .officialCompleted : .officialScheduled,
                    source: official,
                    now: pending.detectedAt,
                    notificationID: pending.notificationID
               ) {
                events.append(event)
            } else {
                remaining.append(pending)
            }
        }
        state.pending = remaining
        associateHistoricalRecoveries()
        persist()
        return events
    }

    private func makeSnapshot(buckets: [RateLimitBucket], now: Date, accountID: String?) -> Snapshot {
        let signature = buckets
            .map { "\($0.id):\($0.planType ?? "-")" }
            .sorted()
            .joined(separator: "|")
        let windows = buckets.flatMap { bucket in
            bucket.windows.enumerated().map { index, window in
                let duration = window.windowDurationMinutes.map(String.init) ?? "unknown-\(index)"
                return WindowSnapshot(
                    id: "\(bucket.id)|\(duration)",
                    bucketID: bucket.id,
                    bucketName: bucket.name,
                    windowDurationMinutes: window.windowDurationMinutes,
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt
                )
            }
        }
        return Snapshot(capturedAt: now, contextSignature: signature, accountID: accountID, windows: windows)
    }

    private func isNaturalReset(old: WindowSnapshot, current: WindowSnapshot, now: Date) -> Bool {
        guard let oldReset = old.resetsAt else { return false }
        let secondsAfterDeadline = now.timeIntervalSince(oldReset)
        guard secondsAfterDeadline >= -2 * 60, secondsAfterDeadline <= 6 * 60 * 60 else { return false }
        guard let newReset = current.resetsAt, newReset > oldReset, newReset > now else { return false }

        if let duration = old.windowDurationMinutes {
            return newReset.timeIntervalSince(oldReset) >= Double(duration * 60) * 0.5
        }
        return true
    }

    private func decorate(_ original: QuotaResetConfirmationCandidate, plans: [String]?) -> QuotaResetConfirmationCandidate {
        var candidate = original
        candidate.communityEvidence = nearbyEvidence(in: evidenceFeed, detectedAt: candidate.detectedAt, changes: candidate.changes, plans: plans, now: Date())
        if !candidate.isWaiting {
            candidate.associationNote = "历史记录未保存账号证据；社区线索不等于该账号已获 Tibo 重置。"
        } else if evidenceFeed == nil {
            candidate.associationNote = "等待社区数据同步；不会仅凭满额跳变确认原因。"
        } else {
            candidate.associationNote = "尚无时间、类型与适用范围一致的充分证据。"
        }
        if candidate.communityEvidence.isEmpty, let evidenceFeed,
           evidenceFeed.events.contains(where: { event in
               event.kind == .bankedReset && event.announcedDate.map { abs($0.timeIntervalSince(candidate.detectedAt)) <= 12 * 3600 } == true
           }) {
            candidate.associationNote += " 附近只有额度重置卡线索，不能证明已执行重置。"
        }
        return candidate
    }

    private func nearbyEvidence(in feed: TiboFeed?, detectedAt: Date, changes: [QuotaResetChange], plans: [String]?, now: Date) -> [TiboEvent] {
        guard let feed else { return [] }
        return feed.officialEvidenceEvents(now: now).filter { event in
            guard [.resetCompleted, .resetScheduled].contains(event.kind), event.confidence >= 0.65,
                  let time = event.effectiveDate ?? event.announcedDate,
                  abs(time.timeIntervalSince(detectedAt)) <= 3 * 3600,
                  time <= now.addingTimeInterval(30 * 60),
                  scopeMatches(event, changes: changes, plans: plans)
            else { return false }
            return event.kind != .resetScheduled || event.effectiveDate != nil
        }.sorted {
            abs(($0.effectiveDate ?? $0.announcedDate ?? .distantPast).timeIntervalSince(detectedAt))
                < abs(($1.effectiveDate ?? $1.announcedDate ?? .distantPast).timeIntervalSince(detectedAt))
        }
    }

    private func scopeMatches(_ event: TiboEvent, changes: [QuotaResetChange], plans: [String]?) -> Bool {
        let audience = Set(event.scope.plans.map { $0.lowercased() })
        let generic: Set<String> = ["all", "codex", "chatgpt_work", "unknown"]
        if audience.isDisjoint(with: generic), let plans {
            guard !audience.isDisjoint(with: Set(plans.map { $0.lowercased() })) else { return false }
        }
        let windows = event.scope.windows.map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
        return windows.contains { window in
            if ["all", "unknown", "codex"].contains(window) { return true }
            if window.contains("week") || window.contains("周") || window == "7d" { return changes.contains { $0.windowDurationMinutes == 10080 } }
            if window.contains("5h") || window.contains("5小时") { return changes.contains { $0.windowDurationMinutes == 300 } }
            return false
        }
    }

    private func matchingOfficialEvent(in feed: TiboFeed?, detectedAt: Date, changes: [QuotaResetChange], plans: [String], now: Date) -> TiboEvent? {
        nearbyEvidence(in: feed, detectedAt: detectedAt, changes: changes, plans: plans, now: now)
            .first { event in
                guard !event.hasDifferentSourceTimes else { return false }
                let time = event.effectiveDate ?? event.announcedDate ?? .distantPast
                return event.kind == .resetScheduled || abs(time.timeIntervalSince(detectedAt)) <= 30 * 60
            }
    }

    private func expirePending(now: Date) -> [QuotaResetEvent] {
        var expiredEvents: [QuotaResetEvent] = []
        var remaining: [Pending] = []
        for pending in state.pending {
            if now.timeIntervalSince(pending.detectedAt) > 3 * 60 * 60 {
                if let event = record(changes: pending.changes, reason: .unverified, source: nil, now: pending.detectedAt, notificationID: pending.notificationID) {
                    expiredEvents.append(event)
                }
            } else {
                remaining.append(pending)
            }
        }
        state.pending = remaining
        return expiredEvents
    }

    private func record(
        changes: [QuotaResetChange],
        reason: QuotaResetReason,
        source: TiboEvent?,
        now: Date,
        notificationID: String? = nil
    ) -> QuotaResetEvent? {
        let identities = changes
            .map { "\($0.bucketID)-\($0.windowDurationMinutes ?? -1)" }
            .sorted()
            .joined(separator: "+")
        let evidence = source?.source.postId ?? String(Int(now.timeIntervalSince1970 / 60))
        let id = notificationID ?? "\(reason.rawValue)|\(evidence)|\(identities)"
        guard !state.history.contains(where: { $0.id == id }) else { return nil }

        let event = QuotaResetEvent(
            id: id,
            detectedAt: now,
            reason: reason,
            changes: changes,
            sourcePostID: source?.source.postId,
            sourceURL: source?.source.url,
            notificationID: notificationID
        )
        state.history.insert(event, at: 0)
        state.history = Array(state.history.prefix(50))
        return event
    }

    private static func confirmationCandidate(
        detectedAt: Date,
        changes: [QuotaResetChange]
    ) -> QuotaResetConfirmationCandidate {
        let identities = changes
            .map { "\($0.bucketID)-\($0.windowDurationMinutes ?? -1)" }
            .sorted()
            .joined(separator: "+")
        let milliseconds = Int64((detectedAt.timeIntervalSince1970 * 1_000).rounded())
        return QuotaResetConfirmationCandidate(
            id: "quota-recovery|\(milliseconds)|\(identities)",
            detectedAt: detectedAt,
            changes: changes
        )
    }

    private func persist() {
        try? writeState()
    }

    private func writeState() throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func backupStateBeforeClassificationChange() throws {
        let directory = stateURL.deletingLastPathComponent()
            .appendingPathComponent("quota-reset-backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backupURL = directory.appendingPathComponent(
            "quota-reset-state-before-type-change-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: backupURL, options: .atomic)
    }

    private static func load(from url: URL) -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var decoded = try? decoder.decode(State.self, from: data) else {
            return nil
        }
        for index in decoded.history.indices
        where decoded.history[index].userDisplayType
            == decoded.history[index].reason.defaultDisplayType {
            decoded.history[index].userDisplayType = nil
        }
        return decoded
    }
}
