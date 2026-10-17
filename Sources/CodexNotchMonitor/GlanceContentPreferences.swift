import Foundation
import SwiftUI

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
        primaryQuotaWindowCount: Int
    ) -> CGFloat {
        var height: CGFloat = 161
        if showPrimaryQuota {
            height += 24 + CGFloat(max(1, primaryQuotaWindowCount)) * 55
        }
        if showCostEstimate { height += 139 }
        if showCreditBalance { height += 31 }
        if showDailyTokens { height += 31 }
        if showThirtyDayTokens { height += 31 }
        if showTokenActivity { height += 68 }
        if showResetEntry { height += 55 }
        return min(GlanceLayout.height, max(230, height))
    }
}

private enum GlanceSettingsSection: String, CaseIterable, Identifiable {
    case content = "内容"
    case appearance = "外观"

    var id: String { rawValue }
}

struct GlanceContentSettingsView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(GlanceContentPreferenceKey.showPrimaryQuota) private var showPrimaryQuota = true
    @AppStorage(GlanceContentPreferenceKey.showCostEstimate) private var showCostEstimate = true
    @AppStorage(GlanceContentPreferenceKey.showCreditBalance) private var showCreditBalance = true
    @AppStorage(GlanceContentPreferenceKey.showDailyTokens) private var showDailyTokens = true
    @AppStorage(GlanceContentPreferenceKey.showThirtyDayTokens) private var showThirtyDayTokens = true
    @AppStorage(GlanceContentPreferenceKey.showTokenActivity) private var showTokenActivity = true
    @AppStorage(GlanceContentPreferenceKey.showResetEntry) private var showResetEntry = true
    @AppStorage(GlanceContentPreferenceKey.surfaceOpacity) private var surfaceOpacity = 0.38
    @State private var isAdjustingOpacity = false
    @State private var selectedSection = GlanceSettingsSection.content

    var body: some View {
        GeometryReader { geometry in
            SettingsWorkbench(isAdjusting: isAdjustingOpacity) {
                GlanceSettingsPreview(store: store, preferences: preferences)
                    .padding(14)
                    .background(PanelSettingsTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PanelSettingsTheme.border.opacity(0.55), lineWidth: 0.5))
            } controls: {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        PanelSettingsSegments(options: GlanceSettingsSection.allCases.map(\.rawValue), selection: Binding(
                            get: { selectedSection.rawValue },
                            set: { if let section = GlanceSettingsSection(rawValue: $0) { selectedSection = section } }
                        ))
                        Spacer(minLength: 8)
                        Text("\(visibleContentCount) / 7 项显示")
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(PanelSettingsTheme.secondary)
                    }
                    Group {
                        if selectedSection == .content { contentSettings }
                        else { appearanceSettings }
                    }
                    .id(selectedSection).transition(.opacity)
                }
            }
            .environment(\.workbenchPreviewHeight, geometry.size.width >= 700 ? max(260, geometry.size.height - 50) : 400)
        }
        .font(MonitorDesktopTypography.body)
        .foregroundStyle(PanelSettingsTheme.primary)
        .tint(PanelSettingsTheme.clay)
        .background(PanelSettingsTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
        .animation(reduceMotion ? nil : PanelSettingsTheme.selectionMotion, value: selectedSection)
        .onDisappear { isAdjustingOpacity = false }
        .onChange(of: surfaceOpacity) { opacity in
            NotificationCenter.default.post(name: .glanceSurfaceOpacityDidChange, object: opacity)
        }
    }

    private var preferences: GlanceContentPreferences {
        .init(showPrimaryQuota: showPrimaryQuota,
              showCostEstimate: showCostEstimate, showCreditBalance: showCreditBalance,
              showDailyTokens: showDailyTokens, showThirtyDayTokens: showThirtyDayTokens,
              showTokenActivity: showTokenActivity, showResetEntry: showResetEntry, surfaceOpacity: surfaceOpacity)
    }

    private var contentSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelSettingsGroup(title: "额度", symbol: "gauge.with.dots.needle.33percent") {
                contentRow(
                    title: "Codex 额度窗口",
                    detail: "5 小时、每周及其他可用额度窗口。",
                    isOn: $showPrimaryQuota
                )
                rowDivider
                contentRow(
                    title: "Credits 余额",
                    detail: "当前账号的可用 Credits。",
                    isOn: $showCreditBalance
                )
                rowDivider
                contentRow(
                    title: "额度重置入口",
                    detail: "额度卡次数、有效期与重置操作入口。",
                    isOn: $showResetEntry
                )
            }
            PanelSettingsGroup(title: "用量", symbol: "chart.bar") {
                contentRow(
                    title: "最近一天 Token",
                    detail: "最近一个统计日的用量。",
                    isOn: $showDailyTokens
                )
                rowDivider
                contentRow(
                    title: "30 日 Token",
                    detail: "最近 30 个统计日的总用量。",
                    isOn: $showThirtyDayTokens
                )
                rowDivider
                contentRow(
                    title: "Token 活动图表",
                    detail: "支持周、月、三月与半年范围。",
                    isOn: $showTokenActivity
                )
            }
            PanelSettingsGroup(title: "成本", symbol: "dollarsign.circle") {
                contentRow(
                    title: "成本估算图表",
                    detail: "按参考 API 价格估算，非实际账单。",
                    isOn: $showCostEstimate
                )
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSettingsGroup(title: "面板外观", symbol: "circle.lefthalf.filled") {
                opacityCard
            }
            Label("仅影响菜单栏面板，灵动岛外观独立设置。", systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(PanelSettingsTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibleContentCount: Int {
        [
            showPrimaryQuota,
            showCostEstimate,
            showCreditBalance,
            showDailyTokens,
            showThirtyDayTokens,
            showTokenActivity,
            showResetEntry,
        ].filter { $0 }.count
    }

    private var rowDivider: some View {
        Rectangle().fill(PanelSettingsTheme.border.opacity(0.45)).frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private func contentRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelSettingsTheme.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(PanelSettingsTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(PanelSettingsToggleStyle())
                .accessibilityLabel(title)
                .accessibilityValue(isOn.wrappedValue ? "显示" : "隐藏")
        }
        .padding(.vertical, 12)
        .frame(minHeight: 62)
    }

    private var opacityCard: some View {
        IslandSettingsSliderRow(title: "背景不透明度", detail: "数值越高，黑色背景越深。",
            value: $surfaceOpacity, range: 0.10...0.90, step: 0.01,
            display: "\(Int((surfaceOpacity * 100).rounded()))%", lowerLabel: "更透明", upperLabel: "更深",
            onEditingChanged: { isAdjustingOpacity = $0 })
    }
}
