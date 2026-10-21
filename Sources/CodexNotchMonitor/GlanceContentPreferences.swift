import Foundation

extension Notification.Name {
    static let glanceSurfaceOpacityDidChange = Notification.Name(
        "CodexMonitor.glanceSurfaceOpacityDidChange"
    )
}

enum GlanceContentPreferenceKey {
    static let showPrimaryQuota = "glance.content.primaryQuota"
    static let showCostEstimate = "glance.content.costEstimate"
    static let showCreditBalance = "glance.content.creditBalance"
    static let showDailyTokens = "glance.content.dailyTokens"
    static let showThirtyDayTokens = "glance.content.thirtyDayTokens"
    static let showTokenActivity = "glance.content.tokenActivity"
    static let showResetEntry = "glance.content.resetEntry"
    static let surfaceOpacity = "glance.surfaceOpacity"
}

struct GlanceContentPreferences: Equatable {
    var showPrimaryQuota: Bool
    var showCostEstimate: Bool
    var showCreditBalance: Bool
    var showDailyTokens: Bool
    var showThirtyDayTokens: Bool
    var showTokenActivity: Bool
    var showResetEntry: Bool
    var surfaceOpacity: Double

    static let defaults = GlanceContentPreferences(
        showPrimaryQuota: true,
        showCostEstimate: true,
        showCreditBalance: true,
        showDailyTokens: true,
        showThirtyDayTokens: true,
        showTokenActivity: true,
        showResetEntry: true,
        surfaceOpacity: 0.38
    )

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let registered = Self.defaults
        return Self(
            showPrimaryQuota: defaults.object(forKey: GlanceContentPreferenceKey.showPrimaryQuota) as? Bool
                ?? registered.showPrimaryQuota,
            showCostEstimate: defaults.object(forKey: GlanceContentPreferenceKey.showCostEstimate) as? Bool
                ?? registered.showCostEstimate,
            showCreditBalance: defaults.object(forKey: GlanceContentPreferenceKey.showCreditBalance) as? Bool
                ?? registered.showCreditBalance,
            showDailyTokens: defaults.object(forKey: GlanceContentPreferenceKey.showDailyTokens) as? Bool
                ?? registered.showDailyTokens,
            showThirtyDayTokens: defaults.object(forKey: GlanceContentPreferenceKey.showThirtyDayTokens) as? Bool
                ?? registered.showThirtyDayTokens,
            showTokenActivity: defaults.object(forKey: GlanceContentPreferenceKey.showTokenActivity) as? Bool
                ?? registered.showTokenActivity,
            showResetEntry: defaults.object(forKey: GlanceContentPreferenceKey.showResetEntry) as? Bool
                ?? registered.showResetEntry,
            surfaceOpacity: min(
                0.90,
                max(
                    0.10,
                    defaults.object(forKey: GlanceContentPreferenceKey.surfaceOpacity) as? Double
                        ?? registered.surfaceOpacity
                )
            )
        )
    }

    func preferredHeight(
        primaryQuotaWindowCount: Int, provider: GlanceProvider = .codex
    ) -> CGFloat {
        var modules: [CGFloat] = []
        if showPrimaryQuota { modules.append(168 + CGFloat(max(0, primaryQuotaWindowCount - 1)) * 18) }
        // Includes the 32 pt text tabs, subtitle, 44 pt bars and summary.
        if showCostEstimate || showTokenActivity { modules.append(160) }
        if provider == .claude || showCreditBalance || showDailyTokens || showThirtyDayTokens { modules.append(56) }
        if provider == .codex && showResetEntry { modules.append(34) }
        let reading = modules.reduce(0, +) + CGFloat(max(0, modules.count - 1)) * GlanceLayout.moduleSpacing
            + 2 * GlanceLayout.readingInset
        return GlanceLayout.preferredHeight(readingHeight: reading, estimatedHeight: 230)
    }
}
