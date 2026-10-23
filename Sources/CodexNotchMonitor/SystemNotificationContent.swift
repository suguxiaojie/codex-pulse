import Foundation

/// Value-only payloads keep presentation and action routing testable without
/// requesting system permission or accessing the notification center.
struct SystemNotificationContent: Equatable {
    let identifier: String
    let title: String
    var subtitle = ""
    let body: String
    let category: String
    var sourceURL: String? = nil
    var playsSound = true

    var islandAlert: IslandAlert? {
        let signal = category == "TIBO_SIGNAL"
        let pending = category == "QUOTA_RECOVERY_UNVERIFIED"
        guard signal || pending || category == "QUOTA_RECOVERY" else { return nil }
        var actions = [IslandAlert.Action(title: signal ? "在动态中心查看" : "查看重置记录", route: .openCenter)]
        if signal { actions.append(.init(title: "打开原帖", route: .openSource)) }
        if pending { actions.append(.init(title: "标记为手动重置", route: .confirmManual)) }
        return IslandAlert(id: identifier, kind: signal ? .tiboSignal : .quotaRecovery,
            title: title, subtitle: subtitle, body: body, isPendingSource: pending,
            actions: actions, sourceURL: sourceURL)
    }

    static func recovery(_ event: QuotaResetEvent, isUpdate: Bool = false) -> Self {
        let pending = event.reason == .unverified
        return Self(
            identifier: event.notificationID ?? event.id,
            title: pending ? "额度已恢复至 100%" : event.reason.title + (isUpdate ? " · 已核对" : ""),
            body: recoveryDetails(event) + (pending ? "\n来源确认中…" : ""),
            category: pending ? "QUOTA_RECOVERY_UNVERIFIED" : "QUOTA_RECOVERY",
            sourceURL: event.sourceURL,
            playsSound: !isUpdate
        )
    }

    static func recoveryDetails(_ event: QuotaResetEvent) -> String {
        event.changes.map {
            "\($0.bucketName) \($0.windowLabel)：\($0.previousRemainingPercent)% → \($0.currentRemainingPercent)%"
        }.joined(separator: "；")
    }

    static func signal(_ signal: CodexResetRadarSignal, state: CodexResetPinnedSignalState) -> Self {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return Self(
            identifier: "tibo-signal-\(signal.tweetId)",
            title: state == .activePreview ? "Tibo 发布了重置预告" : "Tibo 发布了待验证的重置信号",
            subtitle: signal.date.map(formatter.string(from:)) ?? "",
            body: signal.displayText.count > 120 ? String(signal.displayText.prefix(120)) + "…" : signal.displayText,
            category: "TIBO_SIGNAL",
            sourceURL: signal.url
        )
    }
}
