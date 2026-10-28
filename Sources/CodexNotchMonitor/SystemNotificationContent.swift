import Foundation
import CryptoKit

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
        if category == "CREDIT_EXPIRY" {
            return IslandAlert(id: identifier, kind: .creditExpiry, title: title, subtitle: subtitle,
                body: body, isPendingSource: false, actions: [], sourceURL: nil)
        }
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

/// Thresholds are evaluated only against a successful, account-matched quota read.
/// Persist the most urgent announced stage so restarts cannot replay older stages.
struct CreditExpiryReminderLedger {
    private struct Entry: Codable {
        let expiry: Date
        let hours: Int
    }
    private var entries: [String: Entry]
    init(data: Data? = nil) {
        entries = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }
    var data: Data? { try? JSONEncoder().encode(entries) }

    mutating func observe(_ summary: QuotaResetCreditSummary?, accountID: String?, now: Date) -> [SystemNotificationContent] {
        entries = entries.filter { $0.value.expiry > now }
        guard let accountID, !accountID.isEmpty, let summary, summary.availableCount > 0 else { return [] }
        var result: [SystemNotificationContent] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for credit in summary.credits {
            guard credit.status.lowercased() == "available", !credit.id.isEmpty,
                  !credit.id.hasPrefix("reset-credit-"),
                  let expiry = credit.expiresAt, expiry.timeIntervalSince1970.isFinite,
                  expiry > now,
                  let hours = [6, 12, 24].first(where: { expiry.timeIntervalSince(now) <= Double($0) * 3600 }) else { continue }
            let identity = [accountID, credit.id, String(expiry.timeIntervalSince1970)]
            guard let bytes = try? JSONEncoder().encode(identity) else { continue }
            let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            if let previous = entries[key], previous.hours <= hours { continue }
            entries[key] = Entry(expiry: expiry, hours: hours)
            let name = credit.title?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
            result.append(SystemNotificationContent(identifier: "credit-expiry-\(key)-\(hours)",
                title: "重置卡即将过期", subtitle: "\(hours) 小时内到期",
                body: "\(name.isEmpty ? "额度重置卡" : String(name.prefix(80)))将于 \(formatter.string(from: expiry)) 到期，请及时使用。",
                category: "CREDIT_EXPIRY"))
        }
        return result
    }
}
