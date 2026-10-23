enum QuotaNotificationStatus: Equatable {
    case unknown
    case enabled
    case denied
}

enum NotificationAuthorizationPolicy {
    static func shouldRequest(status: QuotaNotificationStatus, signals: Bool, recovery: Bool) -> Bool {
        status == .unknown && (signals || recovery)
    }
}
