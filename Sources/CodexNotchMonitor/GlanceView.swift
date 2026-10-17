import SwiftUI

enum GlanceLayout {
    static let width: CGFloat = 296
    static let height: CGFloat = 806
    static let resetPageHeight: CGFloat = 748
    static let cornerRadius: CGFloat = 26
    static let contentInset: CGFloat = 12
    static let headerHeight: CGFloat = 50
    static let accountHeaderHeight: CGFloat = 38
    static let footerHeight: CGFloat = 48
}

private struct GlanceReadingHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private enum GlanceActivityRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90
    case halfYear = 180

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: return "周"
        case .month: return "月"
        case .quarter: return "三月"
        case .halfYear: return "半年"
        }
    }
}

private enum GlanceRefreshVisualState {
    case idle
    case refreshing
    case completed
}

private enum GlancePage {
    case summary
    case quotaReset
}

private struct GlanceCostBucket: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

private struct GlanceTokenBucket: Identifiable {
    let id: Int
    let label: String
    let tokens: Int?
}

struct GlanceView: View {
    @ObservedObject var store: MonitorStore
    let onQuit: () -> Void
    let onOpenCenter: (MonitorCenterSection) -> Void
    let onPreferredHeightChange: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var readingHeight: CGFloat?
    @State private var activityRange: GlanceActivityRange = .week
    @State private var costRange: GlanceActivityRange = .week
    @State private var refreshVisualState: GlanceRefreshVisualState = .idle
    @State private var refreshRotation = 0.0
    @State private var refreshStartedAt = Date.distantPast
    @State private var page: GlancePage = .summary
    @State private var showsResetConfirmation = false
    @AppStorage(GlanceContentPreferenceKey.showPrimaryQuota) private var showPrimaryQuota = true
    @AppStorage(GlanceContentPreferenceKey.showCostEstimate) private var showCostEstimate = true
    @AppStorage(GlanceContentPreferenceKey.showCreditBalance) private var showCreditBalance = true
    @AppStorage(GlanceContentPreferenceKey.showDailyTokens) private var showDailyTokens = true
    @AppStorage(GlanceContentPreferenceKey.showThirtyDayTokens) private var showThirtyDayTokens = true
    @AppStorage(GlanceContentPreferenceKey.showTokenActivity) private var showTokenActivity = true
    @AppStorage(GlanceContentPreferenceKey.showResetEntry) private var showResetEntry = true

    var body: some View {
        Group {
            switch page {
            case .summary:
                summaryPage
            case .quotaReset:
                quotaResetPage
            }
        }
        .frame(width: GlanceLayout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(primaryText)
        .background(panelTint)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: primaryRemaining)
        .onChange(of: store.costSnapshot.updatedAt) { updatedAt in
            completeRefreshIfReady(updatedAt: updatedAt)
        }
        .onChange(of: store.costSnapshot.costActivity.count) { _ in
            completeRefreshIfReady(updatedAt: store.costSnapshot.updatedAt)
        }
        .onPreferenceChange(GlanceReadingHeightKey.self) { height in
            guard case .summary = page, height.isFinite, height >= 0 else { return }
            let next = ceil(height)
            if readingHeight.map({ abs($0 - next) > 0.5 }) ?? true { readingHeight = next }
        }
        .onAppear {
            onPreferredHeightChange(preferredHeight)
        }
        .onChange(of: preferredHeight) { height in
            onPreferredHeightChange(height)
        }
        .alert("确认重置额度？", isPresented: $showsResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("消耗 1 次并重置", role: .destructive) {
                store.consumeQuotaResetCredit()
            }
        } message: {
            Text(resetConfirmationMessage)
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryPage: some View {
        VStack(spacing: 0) {
            header
            currentAccountHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if showPrimaryQuota {
                        primaryQuota
                    }
                    if showCreditBalance {
                        Divider().overlay(hairlineColor)
                        creditBalanceRow
                    }
                    if showResetEntry {
                        if showCreditBalance {
                            Divider().overlay(hairlineColor)
                        }
                        resetCreditCard(store.quotaResetCredits)
                    }
                    if showCostEstimate || showDailyTokens || showThirtyDayTokens || showTokenActivity {
                        Divider().overlay(hairlineColor)
                        currentUsageSectionHeader
                        if hasCurrentAccountHistory {
                            if showDailyTokens || showThirtyDayTokens {
                                historicalMetricsGroup
                            }
                            if showCostEstimate {
                                costEstimate
                            }
                            if showTokenActivity {
                                tokenActivity
                            }
                        } else {
                            currentAccountHistoryEmptyState
                        }
                    }
                }
                .padding(.horizontal, GlanceLayout.contentInset)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: GlanceReadingHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FloatingSurfaceTheme.surface(colorScheme).opacity(reduceTransparency ? 1 : contrast == .increased ? 0.90 : 0.72))
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
            }

            Divider().overlay(separatorColor)
            footer
                .padding(.horizontal, GlanceLayout.contentInset)
        }
    }

    private var quotaResetPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Button {
                    withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion) {
                        page = .summary
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(GlanceCircleButtonStyle())
                .help("返回额度概览")

                Text("额度重置")
                    .font(FloatingSurfaceTypography.title)
                    .tracking(-0.15)
                Spacer()
                Text("官方接口")
                    .font(FloatingSurfaceTypography.fineStrong)
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 23)
                    .background(
                        FloatingSurfaceTheme.chipFill(colorScheme),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .padding(.horizontal, GlanceLayout.contentInset)
            .frame(height: 50)

            Divider().overlay(separatorColor)

            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 7) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(primaryText)
                    Text(store.quotaResetCredits.map { "\($0.availableCount)" } ?? "—")
                        .font(FloatingSurfaceTypography.heroMetric)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("可用重置次数")
                        .font(FloatingSurfaceTypography.section)
                        .foregroundStyle(secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                VStack(spacing: 0) {
                    HStack {
                        Text("当前可用额度")
                        Spacer()
                        Text("\(primaryRemaining)%")
                            .font(FloatingSurfaceTypography.section)
                            .monospacedDigit()
                    }
                    .frame(height: 34)

                    Divider().overlay(hairlineColor)

                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.clock")
                        Text(resetCreditExpirationText(store.quotaResetCredits))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 34)
                }
                .font(FloatingSurfaceTypography.label)
                .foregroundStyle(secondaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Label("重置前请确认", systemImage: "exclamationmark.triangle.fill")
                        .font(FloatingSurfaceTypography.section)
                        .foregroundStyle(.orange)
                    Text("• 此操作会消耗 1 次额度重置机会。")
                    Text("• 符合条件的 Codex 用量周期将立即重置。")
                    Text("• 额度重置完成后无法撤销。")
                }
                .font(FloatingSurfaceTypography.label)
                .foregroundStyle(secondaryText)

                Spacer(minLength: 6)

                Button {
                    showsResetConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        if store.isConsumingQuotaResetCredit {
                            ProgressView()
                                .controlSize(.small)
                                .tint(FloatingSurfaceTheme.onDanger)
                        }
                        Text(store.isConsumingQuotaResetCredit ? "正在重置" : "重置额度")
                    }
                    .font(FloatingSurfaceTypography.captionStrong)
                    .foregroundStyle(FloatingSurfaceTheme.onDanger)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        FloatingSurfaceTheme.danger.opacity(canConsumeResetCredit ? 0.30 : 0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                FloatingSurfaceTheme.danger.opacity(canConsumeResetCredit ? 0.58 : 0.22),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(FloatingSurfaceButtonStyle())
                .disabled(!canConsumeResetCredit || store.isConsumingQuotaResetCredit)

                Text(store.quotaResetOperationMessage ?? resetOperationHint)
                    .font(FloatingSurfaceTypography.fine)
                    .foregroundStyle(
                        store.quotaResetOperationMessage == nil
                            ? tertiaryText
                            : secondaryText
                    )
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, GlanceLayout.contentInset)
            .padding(.vertical, 12)
            .frame(maxHeight: .infinity)

            Divider().overlay(separatorColor)
            footer
                .padding(.horizontal, GlanceLayout.contentInset)
        }
    }

    private var canConsumeResetCredit: Bool {
        (store.quotaResetCredits?.availableCount ?? 0) > 0
    }

    private var contentPreferences: GlanceContentPreferences {
        GlanceContentPreferences(
            showPrimaryQuota: showPrimaryQuota,
            showCostEstimate: showCostEstimate,
            showCreditBalance: showCreditBalance,
            showDailyTokens: showDailyTokens,
            showThirtyDayTokens: showThirtyDayTokens,
            showTokenActivity: showTokenActivity,
            showResetEntry: showResetEntry,
            surfaceOpacity: UserDefaults.standard.object(
                forKey: GlanceContentPreferenceKey.surfaceOpacity
            ) as? Double ?? GlanceContentPreferences.defaults.surfaceOpacity
        )
    }

    private var preferredHeight: CGFloat {
        switch page {
        case .summary:
            if let readingHeight {
                let chrome = GlanceLayout.headerHeight + GlanceLayout.accountHeaderHeight + GlanceLayout.footerHeight + 1
                return min(GlanceLayout.height, max(230, readingHeight + chrome))
            }
            return contentPreferences.preferredHeight(primaryQuotaWindowCount: primaryBucket?.windows.count ?? 0)
        case .quotaReset:
            return GlanceLayout.resetPageHeight
        }
    }

    private var resetOperationHint: String {
        canConsumeResetCredit
            ? "确认后将通过官方接口消耗 1 次额度重置机会。"
            : "当前没有可用额度卡，无法执行重置。"
    }

    private var resetConfirmationMessage: String {
        "此操作将消耗 1 次额度重置机会，并立即重置符合条件的 Codex 用量周期。操作完成后无法撤销。\n\n\(resetCreditExpirationText(store.quotaResetCredits))"
    }

    private var header: some View {
        HStack(spacing: 9) {
            CodexMark(size: 23)
            Text("Codex Pulse")
                .font(FloatingSurfaceTypography.title)
                .tracking(-0.15)
            Spacer()
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(GlanceCircleButtonStyle())
            .help("退出 Codex Pulse")
            .accessibilityLabel("退出 Codex Pulse")
        }
        .padding(.horizontal, GlanceLayout.contentInset)
        .frame(height: GlanceLayout.headerHeight)
    }

    private var currentAccountHeader: some View {
        HStack(spacing: 8) {
            Text("当前账号")
                .font(FloatingSurfaceTypography.section)
                .foregroundStyle(secondaryText)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle()
                    .fill(currentAccountIndicatorColor)
                    .frame(width: 5, height: 5)
                Text(currentAccountBadgeTitle)
                    .font(FloatingSurfaceTypography.badge)
                    .lineLimit(1)
            }
            .foregroundStyle(primaryText)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                FloatingSurfaceTheme.chipFill(colorScheme),
                in: Capsule()
            )
        }
        .padding(.horizontal, GlanceLayout.contentInset)
        .frame(height: GlanceLayout.accountHeaderHeight)
    }

    private var primaryQuota: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Codex 额度")
                .font(FloatingSurfaceTypography.section)
                .foregroundStyle(secondaryText)
                .padding(.top, 9)
                .padding(.bottom, 5)

            if let windows = primaryBucket?.windows, !windows.isEmpty {
                ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                    if index > 0 {
                        Divider().overlay(hairlineColor)
                    }
                    primaryQuotaWindow(window)
                }
            } else {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(primaryText)
                    Text("正在同步额度窗口…")
                        .font(Font.system(size: 9.5, weight: .regular))
                        .foregroundStyle(tertiaryText)
                }
                .frame(height: 48)
            }
        }
    }

    private func primaryQuotaWindow(_ window: RateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(compactWindowTitle(window))
                    .font(FloatingSurfaceTypography.metadataStrong)
                    .foregroundStyle(primaryText)
                if primaryBucket?.windows.count ?? 0 > 1,
                   window == primaryBucket?.limitingWindow {
                    Text("当前瓶颈")
                        .font(FloatingSurfaceTypography.micro)
                        .foregroundStyle(Color.orange.opacity(0.92))
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Color.orange.opacity(0.10), in: Capsule())
                }
                Spacer()
                Text("\(window.remainingPercent)%")
                    .font(FloatingSurfaceTypography.action)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("剩余")
                    .font(FloatingSurfaceTypography.fine)
                    .foregroundStyle(tertiaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    Capsule()
                        .fill(quotaColor(for: window.remainingPercent))
                        .frame(width: proxy.size.width * CGFloat(window.remainingPercent) / 100)
                }
            }
            .frame(height: 7)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(FloatingSurfaceTypography.micro)
                Text(resetText(window))
                Spacer()
            }
            .font(FloatingSurfaceTypography.fine)
            .foregroundStyle(tertiaryText)
        }
        .padding(.vertical, 7)
    }

    private func compactWindowTitle(_ window: RateLimitWindow) -> String {
        switch window.kind {
        case .fiveHour: return "5 小时"
        case .weekly: return "每周"
        case .custom, .unknown: return window.windowLabel
        }
    }


    private var metrics: some View {
        VStack(spacing: 0) {
            if showDailyTokens {
                metricRow(
                    title: "今日 Token",
                    value: compactTokens(selectedCostScope.usage.day.tokens),
                    color: FloatingSurfaceTheme.usageData(colorScheme)
                )
            }
            if showDailyTokens && showThirtyDayTokens {
                Divider().overlay(hairlineColor)
            }
            if showThirtyDayTokens {
                metricRow(
                    title: "30 日 Token",
                    value: compactTokens(selectedCostScope.usage.month.tokens),
                    color: FloatingSurfaceTheme.usageData(colorScheme)
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var numericMetricsGroup: some View {
        VStack(spacing: 0) {
            Divider().overlay(hairlineColor)
            if showCreditBalance {
                creditBalanceRow
            }
            if showCreditBalance && (showDailyTokens || showThirtyDayTokens) {
                Divider().overlay(hairlineColor)
            }
            if showDailyTokens || showThirtyDayTokens {
                metrics
            }
            Divider().overlay(hairlineColor)
        }
    }

    private var currentUsageSectionHeader: some View {
        HStack {
            Text("当前账号用量")
                .font(FloatingSurfaceTypography.section)
                .foregroundStyle(secondaryText)
            Spacer()
            if let currentAccount {
                Text(currentAccount.alias)
                    .font(FloatingSurfaceTypography.fine)
                    .foregroundStyle(tertiaryText)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var historicalMetricsGroup: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if showDailyTokens {
                    tokenSummaryMetric("今日 Token", value: compactTokens(selectedCostScope.usage.day.tokens))
                }
                if showDailyTokens && showThirtyDayTokens {
                    Rectangle().fill(hairlineColor).frame(width: 0.5, height: 36).accessibilityHidden(true)
                }
                if showThirtyDayTokens {
                    tokenSummaryMetric("30 日 Token", value: compactTokens(selectedCostScope.usage.month.tokens))
                }
            }.padding(.vertical, 10)
            if showCostEstimate || showTokenActivity { Divider().overlay(hairlineColor) }
        }
    }

    private func tokenSummaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(FloatingSurfaceTypography.label).foregroundStyle(secondaryText)
            Text(value).font(FloatingSurfaceTypography.primaryMetric)
                .foregroundStyle(FloatingSurfaceTheme.usageData(colorScheme))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(value)
    }

    private var currentAccountHistoryEmptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: store.isCostLoading ? "arrow.triangle.2.circlepath" : "tray")
                    .foregroundStyle(secondaryText)
                Text(store.isCostLoading ? "正在读取当前账号用量…" : "当前账号暂无本地用量记录")
                    .font(FloatingSurfaceTypography.section)
                    .foregroundStyle(primaryText)
            }
            Text(store.isCostLoading ? "正在整理已观察到的账号日志。" : "尚未识别到归属该账号的 Cost 或 Token 数据。")
                .font(FloatingSurfaceTypography.fine)
                .foregroundStyle(tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            FloatingSurfaceTheme.rowFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.vertical, 8)
    }

    private var creditBalanceRow: some View {
        HStack {
            Text("Credits 余额")
                .font(FloatingSurfaceTypography.section)
                .foregroundStyle(secondaryText)
            Spacer()
            Text(CreditBalanceFormatter.summary(primaryBucket?.creditBalance))
                .font(FloatingSurfaceTypography.label)
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(height: 29)
        .help("完整余额：" + CreditBalanceFormatter.string(primaryBucket?.creditBalance))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Credits 余额")
        .accessibilityValue(CreditBalanceFormatter.string(primaryBucket?.creditBalance))
    }

    private var costEstimate: some View {
        let activity = Array(selectedCostScope.costActivity.suffix(costRange.rawValue))
        let buckets = costChartBuckets(activity, range: costRange)
        let total = activity.reduce(0) { $0 + $1.dollars }
        let maximum = activity.map(\.dollars).max() ?? 0
        let latest = activity.last(where: { $0.dollars > 0 })?.dollars ?? 0
        let ready = selectedCostScope.usage.activityIsReady && !activity.isEmpty
        let hasTokens = selectedCostScope.usage.activity.suffix(costRange.rawValue).contains { $0.tokens > 0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("成本估算（\(costRange.rawValue) 天）")
                    .font(FloatingSurfaceTypography.label)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(GlanceActivityRange.allCases) { range in
                        Button {
                            withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion) {
                                costRange = range
                            }
                        } label: {
                            Text(range.title)
                                .font(
                                    costRange == range
                                        ? FloatingSurfaceTypography.fineStrong
                                        : FloatingSurfaceTypography.fine
                                )
                                .foregroundStyle(
                                    costRange == range
                                        ? FloatingSurfaceTheme.accent(colorScheme)
                                        : tertiaryText
                                )
                                .padding(.horizontal, 3)
                                .frame(height: 18)
                                .background(costRange == range ? FloatingSurfaceTheme.accent(colorScheme).opacity(0.12) : .clear, in: Capsule())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(FloatingSurfaceButtonStyle())
                        .accessibilityLabel("查看近 \(range.rawValue) 天成本估算")
                    }
                }
            }

            if ready && total > 0 {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(detailedDollars(total))
                        .font(FloatingSurfaceTypography.primaryMetric).tracking(-0.21)
                        .foregroundStyle(FloatingSurfaceTheme.costData(colorScheme)).monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    Text("峰值 \(detailedDollars(maximum))")
                        .font(FloatingSurfaceTypography.fine).foregroundStyle(secondaryText).monospacedDigit()
                }
                CostMiniBarChart(buckets: buckets).frame(height: 42).padding(.horizontal, 4)
                HStack {
                    Text("估算值 · 非账单")
                    Spacer()
                    Text("最近一天 \(detailedDollars(latest))").monospacedDigit()
                }.font(FloatingSurfaceTypography.label).foregroundStyle(secondaryText)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ready ? detailedDollars(total) : "—")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(primaryText).monospacedDigit()
                    Spacer(minLength: 4)
                    Text(ready ? (total == 0 ? (hasTokens ? "当前估值为零" : "当前周期无 Token 用量") : "当前成本估值") : (store.isCostLoading ? "正在整理成本明细…" : "暂无成本明细"))
                        .font(FloatingSurfaceTypography.label).foregroundStyle(secondaryText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Text("估算值 · 非账单").font(FloatingSurfaceTypography.fine).foregroundStyle(tertiaryText)
            }
            if !selectedCostScope.unknownModels.isEmpty {
                Label("该账号日志有未计价模型", systemImage: "info.circle")
                    .font(FloatingSurfaceTypography.fine).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("当前账号日志包含以下未计价模型：" + selectedCostScope.unknownModels.joined(separator: "、") + "。该提示覆盖账号日志范围，不限定于所选周期。")
            }
        }
        .padding(.top, 8).padding(.bottom, 10)
    }

    private func costChartBuckets(
        _ activity: [DailyCostActivity],
        range: GlanceActivityRange
    ) -> [GlanceCostBucket] {
        guard !activity.isEmpty else {
            let count = CostActivityBucketLayout.ranges(
                dayCount: range.rawValue,
                rangeDays: range.rawValue
            ).count
            return (0..<count).map {
                GlanceCostBucket(id: $0, label: "无数据", value: 0)
            }
        }
        return CostActivityBucketLayout.ranges(
            dayCount: activity.count,
            rangeDays: range.rawValue
        ).enumerated().map { index, bucketRange in
            let slice = activity[bucketRange]
            let startDate = slice.first?.date ?? Date()
            let endDate = slice.last?.date ?? startDate
            return GlanceCostBucket(
                id: index,
                label: dateRangeLabel(from: startDate, to: endDate),
                value: slice.reduce(0) { $0 + $1.dollars }
            )
        }
    }

    private func dateRangeLabel(from start: Date, to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let startText = formatter.string(from: start)
        let endText = formatter.string(from: end)
        return startText == endText ? startText : "\(startText)–\(endText)"
    }

    private func detailedDollars(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "$%.2f", value)
    }

    private func metricRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(FloatingSurfaceTypography.section)
                .foregroundStyle(secondaryText)
            Spacer()
            Text(value)
                .font(FloatingSurfaceTypography.label)
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(height: 29)
    }

    private var tokenActivity: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Token 活动")
                    .font(FloatingSurfaceTypography.section)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(GlanceActivityRange.allCases) { range in
                        Button {
                            withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion) {
                                activityRange = range
                            }
                        } label: {
                            Text(range.title)
                                .font(
                                    activityRange == range
                                        ? FloatingSurfaceTypography.fineStrong
                                        : FloatingSurfaceTypography.fine
                                )
                                .foregroundStyle(
                                    activityRange == range
                                        ? FloatingSurfaceTheme.accent(colorScheme)
                                        : tertiaryText
                                )
                                .padding(.horizontal, 4)
                                .frame(height: 18)
                                .background(activityRange == range ? FloatingSurfaceTheme.accent(colorScheme).opacity(0.12) : .clear, in: Capsule())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(FloatingSurfaceButtonStyle())
                        .accessibilityLabel("查看近 \(range.rawValue) 日 Token 活动")
                    }
                }
            }

            TokenActivityMiniGrid(
                activity: selectedCostScope.usage.activity,
                rangeDays: activityRange.rawValue
            )
            .id(activityRange)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerUpdateText)
                .font(FloatingSurfaceTypography.label)
                .foregroundStyle(secondaryText)
            Circle()
                .fill(footerStatusColor)
                .frame(width: 5, height: 5)
            Spacer()
            refreshFooterButton
            footerButton(symbol: "bolt.horizontal.circle", help: "打开动态中心") {
                onOpenCenter(.tibo)
            }
            footerButton(symbol: "gearshape", help: "打开 Usage") {
                onOpenCenter(.usage)
            }
        }
        .frame(height: GlanceLayout.footerHeight)
    }

    private func resetCreditCard(_ summary: QuotaResetCreditSummary?) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion) {
                page = .quotaReset
            }
        } label: {
            resetCreditCardContent(summary)
        }
        .buttonStyle(FloatingSurfaceButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "额度重置，\(summary.map { ChineseDisplayText.count($0.availableCount, unit: "次可用") } ?? "可用次数未知")，\(resetCreditExpirationText(summary))"
        )
        .accessibilityHint("打开额度重置确认页面")
    }

    private func resetCreditCardContent(
        _ summary: QuotaResetCreditSummary?
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("额度重置")
                    .font(FloatingSurfaceTypography.section)
                    .foregroundStyle(primaryText)
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(resetCreditExpirationText(summary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }
                .font(FloatingSurfaceTypography.fine)
                .foregroundStyle(secondaryText)
            }
            Spacer(minLength: 4)
            resetCreditBadge(summary)
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(secondaryText)
        }
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    private func resetCreditBadge(
        _ summary: QuotaResetCreditSummary?
    ) -> some View {
        Text(summary.map { ChineseDisplayText.count($0.availableCount, unit: "次可用") } ?? "数据未知")
            .font(FloatingSurfaceTypography.fineStrong)
            .foregroundStyle(resetBadgeText)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                resetBadgeFill,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .monospacedDigit()
    }

    private var resetBadgeText: Color {
        FloatingSurfaceTheme.detail(colorScheme)
    }

    private var resetBadgeFill: Color {
        FloatingSurfaceTheme.chipFill(colorScheme)
    }

    private func resetCreditExpirationText(_ summary: QuotaResetCreditSummary?) -> String {
        let now = Date()
        guard let expiration = summary?.nearestExpiration(relativeTo: now) else {
            return "有效期未知"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        let value = formatter.string(from: expiration)
        return expiration > now
            ? "有效期至 \(value)"
            : "已于 \(value) 过期"
    }

    private func footerButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(GlanceCircleButtonStyle())
        .help(help)
    }

    private var refreshFooterButton: some View {
        Button(action: beginManualRefresh) {
            Image(
                systemName: refreshVisualState == .completed
                    ? "checkmark"
                    : "arrow.clockwise"
            )
            .rotationEffect(
                .degrees(refreshVisualState == .refreshing ? refreshRotation : 0)
            )
            .scaleEffect(refreshVisualState == .completed ? 1.08 : 1)
        }
        .buttonStyle(GlanceCircleButtonStyle())
        .disabled(refreshVisualState == .refreshing)
        .help(
            refreshVisualState == .refreshing
                ? "正在刷新"
                : (refreshVisualState == .completed ? "刷新完成" : "刷新全部数据")
        )
        .accessibilityLabel(
            refreshVisualState == .refreshing
                ? "正在刷新"
                : (refreshVisualState == .completed ? "刷新完成" : "刷新全部数据")
        )
    }

    private func beginManualRefresh() {
        guard refreshVisualState != .refreshing else { return }
        refreshStartedAt = Date()
        refreshVisualState = .refreshing
        refreshRotation = 0
        if !reduceMotion {
            withAnimation(.linear(duration: 0.72).repeatForever(autoreverses: false)) {
                refreshRotation = 360
            }
        }
        store.refreshAll()

        let startedAt = refreshStartedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard refreshVisualState == .refreshing,
                  refreshStartedAt == startedAt
            else { return }
            finishManualRefresh()
        }
    }

    private func completeRefreshIfReady(updatedAt: Date) {
        guard refreshVisualState == .refreshing,
              updatedAt >= refreshStartedAt,
              !store.costSnapshot.costActivity.isEmpty
        else { return }
        finishManualRefresh()
    }

    private func finishManualRefresh() {
        withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.pressMotion) {
            refreshRotation = 0
            refreshVisualState = .completed
        }
        let completedAt = refreshStartedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard refreshVisualState == .completed,
                  refreshStartedAt == completedAt
            else { return }
            withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion) {
                refreshVisualState = .idle
            }
        }
    }

    private var primaryBucket: RateLimitBucket? {
        store.quotaState.primaryBucket
    }

    private var currentAccount: UsageAccountOption? {
        guard let id = UsageAccountSelection.currentAccountID(
            in: store.usageAccountOptions
        ) else { return nil }
        return store.usageAccountOptions.first { $0.id == id }
    }

    private var selectedCostScope: CostScopeSnapshot {
        guard let currentAccount else { return .empty }
        return store.costSnapshot.scope(for: currentAccount.id)
    }

    private var currentAccountBadgeTitle: String {
        let alias = currentAccount?.alias ?? store.continuityAccountTitle
        let plan = OpenAIPlanDisplayName.resolve(primaryBucket?.planType)
        return [alias, plan].compactMap { $0 }.joined(separator: " · ")
    }

    private var primaryWindow: RateLimitWindow? {
        primaryBucket?.limitingWindow
    }

    private var currentAccountIndicatorColor: Color {
        switch store.quotaState {
        case .loaded: return Color.green.opacity(0.90)
        case .loading: return FloatingSurfaceTheme.accent(colorScheme).opacity(0.82)
        case .failed: return Color.orange.opacity(0.88)
        }
    }

    private var hasCurrentAccountHistory: Bool {
        selectedCostScope.month.tokens > 0
            || selectedCostScope.month.dollars > 0
            || selectedCostScope.usage.month.sessionCount > 0
    }

    private var primaryRemaining: Int {
        primaryWindow?.remainingPercent ?? 0
    }

    private func quotaColor(for remaining: Int) -> Color {
        FloatingSurfaceTheme.quotaHealth(remaining)
    }

    private var footerUpdateText: String {
        switch store.quotaState {
        case .loading:
            return "正在更新"
        case let .loaded(_, date):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "更新于 \(formatter.string(from: date))"
        case .failed:
            return "数据可能过期"
        }
    }

    private var footerStatusColor: Color {
        switch store.quotaState {
        case .loaded: return .green
        case .loading: return .orange
        case .failed: return .red
        }
    }

    private func resetText(_ window: RateLimitWindow?) -> String {
        guard let date = window?.resetsAt else { return "重置时间未知" }
        return ChineseDisplayText.spacing(QuotaResetCountdown.text(until: date, relativeTo: Date()))
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private var primaryText: Color {
        FloatingSurfaceTheme.primary(colorScheme)
    }

    private var secondaryText: Color {
        FloatingSurfaceTheme.detail(colorScheme)
    }

    private var tertiaryText: Color {
        FloatingSurfaceTheme.secondary(colorScheme)
    }

    private var separatorColor: Color {
        FloatingSurfaceTheme.separator(colorScheme)
    }

    private var hairlineColor: Color {
        FloatingSurfaceTheme.hairline(colorScheme)
    }

    private var trackColor: Color {
        FloatingSurfaceTheme.track(colorScheme)
    }

    private var panelTint: Color {
        .clear
    }
}

private struct CostMiniBarChart: View {
    let buckets: [GlanceCostBucket]
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredBucketID: Int?

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let bucket = hoveredBucket {
                    Text("\(bucket.label) · \(exactDollars(bucket.value))")
                        .foregroundStyle(tooltipTextColor)
                        .padding(.horizontal, 7)
                        .background(tooltipBackground, in: Capsule())
                } else {
                    Color.clear
                }
            }
            .font(FloatingSurfaceTypography.fine)
            .frame(height: 16)

            GeometryReader { proxy in
                let maximum = max(buckets.map(\.value).max() ?? 0, 0.000_001)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(buckets) { bucket in
                        ZStack(alignment: .bottom) {
                            if bucket.value > 0 {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(
                                        barColor(
                                            value: bucket.value,
                                            maximum: maximum,
                                            hovered: hoveredBucketID == bucket.id
                                        )
                                    )
                                    .frame(
                                        height: max(
                                            4,
                                            proxy.size.height * CGFloat(bucket.value / maximum)
                                        )
                                    )
                            }

                            Color.clear
                                .contentShape(Rectangle())
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredBucketID = hovering ? bucket.id : nil
                            }
                            .accessibilityLabel(
                                "\(bucket.label)，成本估算 \(exactDollars(bucket.value))"
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityLabel("30 天成本估算柱状图")
    }

    private var hoveredBucket: GlanceCostBucket? {
        buckets.first(where: { $0.id == hoveredBucketID })
    }

    private func exactDollars(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "US$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "US$%.2f", value)
    }

    private func barColor(
        value: Double,
        maximum: Double,
        hovered: Bool
    ) -> Color {
        let level = CostActivityScale.level(dollars: value, maximum: maximum)
        let baseOpacity: Double
        switch level {
        case 1: baseOpacity = 0.26
        case 2: baseOpacity = 0.42
        case 3: baseOpacity = 0.60
        case 4: baseOpacity = 0.82
        default: return .clear
        }
        let opacity = min(1, baseOpacity + (hovered ? 0.14 : 0))
        return FloatingSurfaceTheme.accent(colorScheme).opacity(opacity)
    }

    private var tooltipBackground: Color {
        FloatingSurfaceTheme.popover(colorScheme).opacity(0.96)
    }

    private var tooltipTextColor: Color {
        FloatingSurfaceTheme.primary(colorScheme)
    }
}

private struct TokenActivityMiniGrid: View {
    let activity: [DailyTokenActivity]
    let rangeDays: Int
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredBucketID: Int?
    @State private var hoverClearWorkItem: DispatchWorkItem?

    private let columns = Array(
        repeating: GridItem(.fixed(12), spacing: 3),
        count: 16
    )

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let bucket = hoveredBucket, let tokens = bucket.tokens {
                    Text("\(bucket.label) · \(exactTokens(tokens)) Tokens")
                        .font(FloatingSurfaceTypography.fine)
                        .foregroundStyle(tooltipTextColor)
                        .padding(.horizontal, 7)
                        .background(tooltipBackground, in: Capsule())
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .trailing)
            .allowsHitTesting(false)

            LazyVGrid(columns: columns, alignment: .center, spacing: 3) {
                ForEach(buckets) { bucket in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(cellColor(bucket.tokens ?? 0))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(
                                    bucket.tokens == nil ? placeholderBorder : .clear,
                                    style: StrokeStyle(lineWidth: 0.6, dash: [2, 2])
                                )
                        }
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            updateHover(bucketID: bucket.id, hovering: hovering)
                        }
                        .accessibilityLabel(
                            bucket.tokens.map {
                                "\(bucket.label)，\(exactTokens($0)) Tokens"
                            } ?? "无数据"
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onDisappear {
            hoverClearWorkItem?.cancel()
            hoverClearWorkItem = nil
            hoveredBucketID = nil
        }
    }

    private var buckets: [GlanceTokenBucket] {
        let recent = Array(activity.suffix(rangeDays))
        guard !recent.isEmpty else {
            return (0..<16).map {
                GlanceTokenBucket(id: $0, label: "无数据", tokens: nil)
            }
        }

        if recent.count <= 16 {
            let placeholderCount = 16 - recent.count
            let placeholders = (0..<placeholderCount).map {
                GlanceTokenBucket(id: $0, label: "无数据", tokens: nil)
            }
            let values = recent.enumerated().map { index, day in
                GlanceTokenBucket(
                    id: placeholderCount + index,
                    label: shortDate(day.date),
                    tokens: day.tokens
                )
            }
            return placeholders + values
        }

        return (0..<16).map { index in
            let start = Int(Double(index) * Double(recent.count) / 16)
            let end = max(
                start + 1,
                Int(Double(index + 1) * Double(recent.count) / 16)
            )
            let boundedEnd = min(end, recent.count)
            let slice = recent[start..<boundedEnd]
            let startDate = slice.first?.date ?? Date()
            let endDate = slice.last?.date ?? startDate
            return GlanceTokenBucket(
                id: index,
                label: dateRangeLabel(from: startDate, to: endDate),
                tokens: slice.reduce(0) { $0 + $1.tokens }
            )
        }
    }

    private var maximum: Int {
        max(1, buckets.compactMap(\.tokens).max() ?? 1)
    }

    private func cellColor(_ tokens: Int) -> Color {
        guard tokens > 0 else {
            return FloatingSurfaceTheme.chipFill(colorScheme)
        }
        let ratio = Double(tokens) / Double(maximum)
        let opacity = 0.18 + min(0.62, ratio * 0.62)
        return FloatingSurfaceTheme.usageData(colorScheme).opacity(opacity)
    }

    private var placeholderBorder: Color {
        FloatingSurfaceTheme.outline(colorScheme, strong: true)
    }

    private var hoveredBucket: GlanceTokenBucket? {
        buckets.first(where: { $0.id == hoveredBucketID })
    }

    private func updateHover(bucketID: Int, hovering: Bool) {
        hoverClearWorkItem?.cancel()
        hoverClearWorkItem = nil
        if hovering {
            hoveredBucketID = bucketID
            return
        }
        let work = DispatchWorkItem {
            guard hoveredBucketID == bucketID else { return }
            hoveredBucketID = nil
        }
        hoverClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func dateRangeLabel(from start: Date, to end: Date) -> String {
        let startText = shortDate(start)
        let endText = shortDate(end)
        return startText == endText ? startText : "\(startText)–\(endText)"
    }

    private func exactTokens(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private var tooltipBackground: Color {
        FloatingSurfaceTheme.popover(colorScheme).opacity(0.96)
    }

    private var tooltipTextColor: Color {
        FloatingSurfaceTheme.primary(colorScheme)
    }

}

private struct GlanceCircleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(enabled && (hovered || configuration.isPressed) ? FloatingSurfaceTheme.accent(colorScheme) : FloatingSurfaceTheme.secondary(colorScheme))
            .frame(width: 28, height: 28)
            .background(FloatingSurfaceTheme.accent(colorScheme).opacity(enabled && configuration.isPressed ? 0.18 : enabled && hovered ? 0.12 : 0.055), in: Circle())
            .overlay(Circle().strokeBorder(enabled && focused ? FloatingSurfaceTheme.accent(colorScheme) : .clear, lineWidth: 1.5))
            .contentShape(Circle()).opacity(enabled ? 1 : 0.45)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : FloatingSurfaceTheme.hoverMotion, value: hovered)
            .animation(reduceMotion ? nil : FloatingSurfaceTheme.pressMotion, value: configuration.isPressed)
    }
}
