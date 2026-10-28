import AppKit
import Foundation
import UserNotifications

final class QuotaResetNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpenCenter: (() -> Void)?
    var onConfirmManual: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let openCenter = UNNotificationAction(identifier: "open-center", title: "在动态中心查看", options: [.foreground])
        let openHistory = UNNotificationAction(identifier: "open-center", title: "查看重置记录", options: [.foreground])
        let source = UNNotificationAction(identifier: "open-source", title: "打开原帖", options: [.foreground])
        let manual = UNNotificationAction(identifier: "confirm-manual", title: "标记为手动重置", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "CREDIT_EXPIRY", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "TIBO_SIGNAL", actions: [openCenter, source], intentIdentifiers: []),
            UNNotificationCategory(identifier: "QUOTA_RECOVERY", actions: [openHistory], intentIdentifiers: []),
            UNNotificationCategory(identifier: "QUOTA_RECOVERY_UNVERIFIED", actions: [openHistory, manual], intentIdentifiers: [])
        ])
    }

    func requestAuthorization(completion: @escaping (QuotaNotificationStatus) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.readAuthorizationStatus(completion: completion)
        }
    }

    func refreshAuthorizationStatus(completion: @escaping (QuotaNotificationStatus) -> Void) {
        readAuthorizationStatus(completion: completion)
    }

    @discardableResult
    func openNotificationSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.coverai.codex-notch-monitor",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }

    private func readAuthorizationStatus(completion: @escaping (QuotaNotificationStatus) -> Void) {
        center.getNotificationSettings { settings in
            let status: QuotaNotificationStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = .enabled
            case .denied: status = .denied
            case .notDetermined: status = .unknown
            @unknown default: status = .unknown
            }
            DispatchQueue.main.async { completion(status) }
        }
    }

    func notify(_ payload: SystemNotificationContent) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.categoryIdentifier = payload.category
        content.sound = payload.playsSound ? .default : nil
        if let sourceURL = payload.sourceURL { content.userInfo["sourceURL"] = sourceURL }
        center.add(UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil))
    }

    func sendTestNotification(completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "Codex Pulse 测试通知"
        content.body = "通知已就绪，额度恢复与关注信号会这样提醒你。"
        content.categoryIdentifier = "QUOTA_RECOVERY"
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: "test-notification-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil
        )) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func notifyAccountSwitch(
        _ transition: AccountTransition,
        projectCount: Int,
        sessionCount: Int,
        recoverableCount: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Codex 账号已切换"
        if recoverableCount == 0 {
            content.body = "\(transition.previousAlias) → \(transition.currentAlias)，已同步 \(projectCount) 个本地项目与 \(sessionCount) 条会话。"
        } else {
            content.body = "\(transition.previousAlias) → \(transition.currentAlias)，发现 \(recoverableCount) 条本地会话待恢复。"
        }
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: "account-switch-\(Int(transition.detectedAt.timeIntervalSince1970))",
            content: content,
            trigger: nil
        ))
    }

    func notifyAppUpdate(
        version: String,
        architecture: String?,
        releaseURL: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Codex Pulse v\(version) 可用"
        content.body = architecture.map { "已找到适用于 \($0) 的安装包。" }
            ?? "新版本已经可以下载。"
        content.sound = .default
        content.userInfo["sourceURL"] = releaseURL
        center.add(UNNotificationRequest(
            identifier: "app-update-\(version)",
            content: content,
            trigger: nil
        ))
    }

    static func body(for event: QuotaResetEvent) -> String {
        SystemNotificationContent.recoveryDetails(event)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(notification.request.content.sound == nil ? [.banner] : [.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let action = SystemNotificationAction.resolve(
            category: request.content.categoryIdentifier,
            action: response.actionIdentifier,
            isDefault: response.actionIdentifier == UNNotificationDefaultActionIdentifier
        )
        DispatchQueue.main.async { [weak self] in
            switch action {
            case .openCenter: self?.onOpenCenter?()
            case .confirmManual: self?.onConfirmManual?(request.identifier)
            case .openSource:
                if let value = request.content.userInfo["sourceURL"] as? String,
                   let url = URL(string: value) { NSWorkspace.shared.open(url) }
            case .none: break
            }
        }
        completionHandler()
    }
}
