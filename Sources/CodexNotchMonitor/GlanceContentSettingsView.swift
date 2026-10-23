import SwiftUI

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
    @State private var countStyle = CountStyle.load()
    @State private var isAdjustingOpacity = false
    @State private var selectedSection = GlanceSettingsSection.content

    var body: some View {
        GeometryReader { geometry in
            SettingsWorkbench(isAdjusting: isAdjustingOpacity) {
                SettingsStage(title: "实时面板", status: "只读预览", caption: "当前账号真实数据") {
                    GlanceSettingsPreview(store: store, preferences: preferences)
                }.modifier(MonitorDesktopReveal(delay: 0))
            } controls: {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        PanelSettingsSegments(options: GlanceSettingsSection.allCases.map(\.rawValue), selection: Binding(
                            get: { selectedSection.rawValue },
                            set: { if let section = GlanceSettingsSection(rawValue: $0) { selectedSection = section } }
                        ))
                        Spacer(minLength: 8)
                        Text("\(visibleContentCount) / 7 项显示")
                            .font(MonitorDesktopTypography.valueBadge)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(MonitorDesktopTheme.primaryText.opacity(0.05), in: Capsule())
                            .fixedSize()
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
        VStack(alignment: .leading, spacing: 26) {
            PanelSettingsGroup(title: "额度", symbol: "gauge.with.dots.needle.33percent") {
                contentRow(
                    symbol: "gauge.with.dots.needle.33percent", title: "Codex 额度窗口",
                    detail: "5 小时、每周及其他可用额度窗口。",
                    isOn: $showPrimaryQuota
                )
                rowDivider
                contentRow(
                    symbol: "creditcard", title: "Credits 余额",
                    detail: "当前账号的可用 Credits。",
                    isOn: $showCreditBalance
                )
                rowDivider
                contentRow(
                    symbol: "arrow.counterclockwise.circle", title: "额度重置入口",
                    detail: "额度卡次数、有效期与重置操作入口。",
                    isOn: $showResetEntry
                )
            }.modifier(MonitorDesktopReveal(delay: 0.04))
            PanelSettingsGroup(title: "用量", symbol: "chart.bar") {
                SettingsRow(symbol: "textformat.123", title: "数字单位", detail: countPreview, numericDetail: true) {
                    PanelSettingsSegments(options: ["万／亿", "K／M／B"], selection: Binding(
                        get: { countStyle == .chinese ? "万／亿" : "K／M／B" },
                        set: { countStyle = $0 == "万／亿" ? .chinese : .western; countStyle.save() }
                    ), title: "数字单位")
                }
                rowDivider
                contentRow(
                    symbol: "sun.max", title: "最近一天 Token",
                    detail: "最近一个统计日的用量。",
                    isOn: $showDailyTokens
                )
                rowDivider
                contentRow(
                    symbol: "calendar", title: "30 日 Token",
                    detail: "最近 30 个统计日的总用量。",
                    isOn: $showThirtyDayTokens
                )
                rowDivider
                contentRow(
                    symbol: "chart.bar.xaxis", title: "Token 活动图表",
                    detail: "最近 7 天用量，长周期请到监控中心查看。",
                    isOn: $showTokenActivity
                )
            }.modifier(MonitorDesktopReveal(delay: 0.08))
            PanelSettingsGroup(title: "成本", symbol: "dollarsign.circle") {
                contentRow(
                    symbol: "dollarsign.circle", title: "成本估算图表",
                    detail: "按参考 API 价格估算，非实际账单。",
                    isOn: $showCostEstimate
                )
            }.modifier(MonitorDesktopReveal(delay: 0.12))
        }
    }

    private var countPreview: String {
        let accountID = UsageAccountSelection.currentAccountID(in: store.usageAccountOptions)
        let usage = accountID.map { store.costSnapshot.scope(for: $0).usage }
        let hasData = usage.map { !$0.activity.isEmpty || $0.day.tokens > 0 || $0.month.tokens > 0 } ?? false
        return SettingsSummaryText.countPreview(
            day: hasData ? usage.map { Int64($0.day.tokens) } : nil,
            month: hasData ? usage.map { Int64($0.month.tokens) } : nil, style: countStyle)
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSettingsGroup(title: "面板外观", symbol: "circle.lefthalf.filled") {
                opacityCard
            }.modifier(MonitorDesktopReveal(delay: 0.04))
            Label("仅影响菜单栏面板，灵动岛外观独立设置。", systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(MonitorDesktopTheme.faintText)
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

    private var rowDivider: some View { SettingsRowDivider() }

    private func contentRow(
        symbol: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsRow(symbol: symbol, title: title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(PanelSettingsToggleStyle())
                .accessibilityLabel(title)
                .accessibilityValue(isOn.wrappedValue ? "显示" : "隐藏")
        }
    }

    private var opacityCard: some View {
        IslandSettingsSliderRow(title: "面板不透明度", detail: "统一控制整个菜单栏面板的底色。",
            value: $surfaceOpacity, range: 0.10...0.90, step: 0.01,
            display: "\(Int((surfaceOpacity * 100).rounded()))%", lowerLabel: "更透明", upperLabel: "更深",
            onEditingChanged: { isAdjustingOpacity = $0 }, symbol: "circle.lefthalf.filled")
    }
}
