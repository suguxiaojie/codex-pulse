import Foundation

struct IslandAlert: Equatable, Identifiable {
    enum Kind: Equatable { case tiboSignal, quotaRecovery, creditExpiry }
    struct Action: Equatable {
        let title: String
        let route: SystemNotificationAction
    }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let body: String
    let isPendingSource: Bool
    let actions: [Action]
    let sourceURL: String?

    func isEnabled(signals: Bool, recovery: Bool, credits: Bool = true) -> Bool {
        if kind == .creditExpiry { return credits }
        return kind == .tiboSignal ? signals : recovery
    }
}

/// Value-only scheduler. A suspended card keeps its remaining time; lifecycle
/// and task presentation are never mutated by notifications.
struct IslandAlertQueue {
    struct Entry: Equatable {
        var alert: IslandAlert
        var remaining: TimeInterval = 8
    }
    private(set) var current: Entry?
    private(set) var pending: [Entry] = []
    private(set) var seen: Set<String> = []
    private var lastTick: Date?
    private var paused = false

    mutating func receive(_ alert: IslandAlert, enabled: Bool, available: Bool) {
        guard enabled, available else { seen.insert(alert.id); return }
        if current?.alert.id == alert.id { current?.alert = alert; return }
        if let index = pending.firstIndex(where: { $0.alert.id == alert.id }) {
            pending[index].alert = alert; return
        }
        guard !seen.contains(alert.id) else { return }
        pending.append(Entry(alert: alert))
        trim()
    }
    mutating func advance(now: Date, blocked: Bool, hovered: Bool, available: Bool,
                          signals: Bool = true, recovery: Bool = true, credits: Bool = true) {
        if let previous = lastTick, !paused, current != nil {
            current?.remaining -= max(0, now.timeIntervalSince(previous))
        }
        lastTick = now
        if !available {
            pending.forEach { seen.insert($0.alert.id) }; pending.removeAll()
            dismiss(); paused = true; return
        }
        pending.removeAll { !$0.alert.isEnabled(signals: signals, recovery: recovery, credits: credits) }
        if let entry = current, entry.remaining <= 0 || !entry.alert.isEnabled(signals: signals, recovery: recovery, credits: credits) { dismiss() }
        if blocked, let entry = current {
            pending.insert(entry, at: 0); current = nil
            // Preserve the interrupted card; evict the oldest waiting card instead.
            while pending.count > 3 { seen.insert(pending.remove(at: 1).alert.id) }
        }
        if !blocked, current == nil, !pending.isEmpty {
            current = pending.removeFirst(); seen.insert(current!.alert.id)
        }
        paused = hovered || blocked
    }
    mutating func dismiss() { current = nil }
    private mutating func trim() {
        while pending.count > 3 { seen.insert(pending.removeFirst().alert.id) }
    }
}

enum SystemNotificationAction: Equatable {
    case openCenter
    case openSource
    case confirmManual
    case none

    static func resolve(category: String, action: String, isDefault: Bool) -> Self {
        if category == "CREDIT_EXPIRY" { return .none }
        let isRecovery = category == "QUOTA_RECOVERY" || category == "QUOTA_RECOVERY_UNVERIFIED"
        if category == "TIBO_SIGNAL" || isRecovery {
            if isDefault || action == "open-center" { return .openCenter }
            if action == "open-source", category == "TIBO_SIGNAL" { return .openSource }
            if action == "confirm-manual", category == "QUOTA_RECOVERY_UNVERIFIED" { return .confirmManual }
            return .none
        }
        return isDefault ? .openSource : .none
    }
}

/// Includes the serial pending presentation, so an alert cannot win the first frame.
enum IslandAlertCompletionGate {
    static func blocks(lifecycle: ActivityIslandLifecycle, confettiActive: Bool,
                       pendingBurst: Bool, now: Date) -> Bool {
        confettiActive || pendingBurst || (lifecycle.isCompletion
            && lifecycle.presentation == .expanded
            && lifecycle.collapseDeadline.map { now < $0 } == true)
    }
}
