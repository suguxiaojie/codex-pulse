import Foundation

enum SystemNotificationTests {
    static func run() throws {
        func signal(_ id: String, text: String = "重置预告", active: Bool = true) -> CodexResetRadarSignal {
            .init(tweetId: id, summary: text, at: "2026-10-23T10:00:00Z",
                  url: "https://x.com/thsottiaux/status/\(id)", kind: "signal",
                  active: active, localizedSummary: nil, translationStatus: nil)
        }
        func resolution(_ state: CodexResetPinnedSignalState) -> CodexResetPinnedSignalResolution {
            .init(state: state, signalEvent: nil, evidenceEvent: nil, isLocallyConfirmed: false)
        }
        var ledger = TiboSignalNotificationLedger()
        precondition(!ledger.observe(signal: signal("1"), resolution: resolution(.pending), enabled: true))
        precondition(ledger.observe(signal: signal("2"), resolution: resolution(.pending), enabled: true))
        precondition(!ledger.observe(signal: signal("2"), resolution: resolution(.pending), enabled: true))
        precondition(!ledger.observe(signal: signal("3"), resolution: resolution(.activePreview), enabled: false))
        // Rehydrate exactly the value persisted by MonitorStore.
        ledger = TiboSignalNotificationLedger(observedIDs: ledger.observedIDs)
        precondition(!ledger.observe(signal: signal("3"), resolution: resolution(.activePreview), enabled: true))
        for (index, state) in [CodexResetPinnedSignalState.confirmed, .fulfilled, .expired].enumerated() {
            precondition(!ledger.observe(signal: signal("skip-\(index)"), resolution: resolution(state), enabled: true))
        }
        precondition(!ledger.observe(signal: signal("inactive", active: false), resolution: resolution(.pending), enabled: true))
        for id in 10..<70 {
            _ = ledger.observe(signal: signal(String(id)), resolution: resolution(.pending), enabled: false)
        }
        precondition(ledger.observedIDs?.count == 50 && ledger.observedIDs?.last == "69")
        var empty = TiboSignalNotificationLedger()
        precondition(!empty.observe(signal: nil, resolution: nil, enabled: true))
        precondition(empty.observe(signal: signal("1"), resolution: resolution(.activePreview), enabled: true))

        let long = SystemNotificationContent.signal(signal("1", text: String(repeating: "中", count: 121)), state: .pending)
        precondition(long.title == "Tibo 发布了待验证的重置信号" && long.body == String(repeating: "中", count: 120) + "…")
        precondition(long.category == "TIBO_SIGNAL" && long.identifier == "tibo-signal-1" && !long.subtitle.isEmpty)
        let preview = SystemNotificationContent.signal(signal("2", text: String(repeating: "字", count: 120)), state: .activePreview)
        precondition(preview.title == "Tibo 发布了重置预告" && preview.body.count == 120)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notification-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("state.json")
        var monitor = QuotaResetMonitor(stateURL: stateURL)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = monitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 40)], feed: nil, now: start)
        let result = monitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 100)], feed: nil, now: start.addingTimeInterval(60))
        precondition(result.pendingNotifications.count == 1 && result.events.isEmpty)
        let pending = result.pendingNotifications[0]
        let initial = SystemNotificationContent.recovery(pending)
        precondition(initial.title == "额度已恢复至 100%" && initial.body.hasSuffix("\n来源确认中…"))
        precondition(initial.category == "QUOTA_RECOVERY_UNVERIFIED" && initial.playsSound)
        monitor = QuotaResetMonitor(stateURL: stateURL)
        let candidate = monitor.confirmableRecoveries[0]
        precondition(candidate.notificationID == pending.notificationID)
        let confirmed = monitor.confirmUserReset(candidateID: candidate.id)!
        precondition(confirmed.notificationID == pending.notificationID)
        let update = SystemNotificationContent.recovery(confirmed, isUpdate: true)
        precondition(update.identifier == initial.identifier && update.title == "手动重置 · 已核对")
        precondition(!update.playsSound && update.category == "QUOTA_RECOVERY")
        for content in [long, preview, initial, update] {
            let alert = content.islandAlert!
            precondition(alert.id == content.identifier && alert.title == content.title)
            precondition(alert.subtitle == content.subtitle && alert.body == content.body)
            precondition(alert.sourceURL == content.sourceURL)
        }
        precondition(initial.islandAlert!.isPendingSource && !update.islandAlert!.isPendingSource)
        precondition(initial.islandAlert!.actions.map(\.route) == [.openCenter, .confirmManual])
        precondition(update.islandAlert!.actions.map(\.route) == [.openCenter])
        precondition(long.islandAlert!.actions.map(\.route) == [.openCenter, .openSource])
        precondition(!long.islandAlert!.isEnabled(signals: false, recovery: true))
        precondition(!initial.islandAlert!.isEnabled(signals: true, recovery: false))
        precondition(monitor.confirmUserReset(candidateID: candidate.id) == nil)

        _ = monitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 30)], feed: nil, now: start.addingTimeInterval(120))
        let second = monitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 100)], feed: nil, now: start.addingTimeInterval(180))
        precondition(second.pendingNotifications[0].notificationID != pending.notificationID)
        let expired = monitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 100)], feed: nil, now: start.addingTimeInterval(4 * 3600))
        precondition(expired.pendingNotifications.isEmpty && !expired.events.contains { $0.reason.isNotifiable })
        precondition(monitor.history.first?.notificationID == second.pendingNotifications.first?.notificationID)

        let expiredCandidate = monitor.confirmableRecoveries[0]
        let manualAfterExpiry = monitor.confirmUserReset(candidateID: expiredCandidate.id)!
        precondition(manualAfterExpiry.notificationID == second.pendingNotifications[0].notificationID)
        for reason in [QuotaResetReason.natural, .officialCompleted, .officialScheduled, .manualCredit, .mixed] {
            let event = QuotaResetEvent(id: "classified", detectedAt: start, reason: reason,
                                       changes: pending.changes, sourcePostID: nil, sourceURL: nil,
                                       notificationID: "stable")
            let content = SystemNotificationContent.recovery(event)
            precondition(content.title == reason.title && content.playsSound && content.category == "QUOTA_RECOVERY")
            precondition(content.body.contains("40% → 100%") && !content.body.contains("来源确认中"))
        }
        let officialMonitor = QuotaResetMonitor(stateURL: root.appendingPathComponent("official.json"))
        let evidence = QuotaResetMonitorTests.feed(kind: .resetCompleted, announcedAt: start)
        var identifiers = Set<String>()
        for offset in [60.0, 120.0] {
            _ = officialMonitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 40)], feed: evidence, now: start.addingTimeInterval(offset - 1))
            let recovery = officialMonitor.evaluate(buckets: [QuotaResetMonitorTests.bucket(remaining: 100)], feed: evidence, now: start.addingTimeInterval(offset))
            precondition(recovery.events.count == 1)
            identifiers.insert(recovery.events[0].notificationID!)
        }
        precondition(identifiers.count == 2, "Distinct jumps sharing one source must each notify")

        // Legacy history without the optional field must continue to decode.
        let data = try JSONEncoder().encode(confirmed)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "notificationID")
        let legacy = try JSONDecoder().decode(QuotaResetEvent.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(legacy.notificationID == nil)

        precondition(SystemNotificationAction.resolve(category: "TIBO_SIGNAL", action: "", isDefault: true) == .openCenter)
        precondition(SystemNotificationAction.resolve(category: "TIBO_SIGNAL", action: "open-source", isDefault: false) == .openSource)
        precondition(SystemNotificationAction.resolve(category: "QUOTA_RECOVERY", action: "open-center", isDefault: false) == .openCenter)
        precondition(SystemNotificationAction.resolve(category: "QUOTA_RECOVERY_UNVERIFIED", action: "confirm-manual", isDefault: false) == .confirmManual)
        precondition(SystemNotificationAction.resolve(category: "QUOTA_RECOVERY", action: "confirm-manual", isDefault: false) == .none)
        precondition(SystemNotificationAction.resolve(category: "", action: "", isDefault: true) == .openSource)
        precondition(SystemNotificationAction.resolve(category: "", action: "dismiss", isDefault: false) == .none)
        print("System notification tests: passed")
    }
}
