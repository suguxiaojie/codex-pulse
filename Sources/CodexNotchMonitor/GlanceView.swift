import SwiftUI

private struct GlanceReadingHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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

struct GlanceView: View {
    @AppStorage(CountStyle.preferenceKey) private var countStyle = CountStyle.chinese.rawValue
    @ObservedObject var store: MonitorStore
    @ObservedObject private var claude: ClaudeCodeRuntime
    @AppStorage("glance.provider") private var savedProvider = "codex"
    @State private var now = Date()
    let onQuit: () -> Void
    let onOpenCenter: (MonitorCenterSection) -> Void
    let onPreferredHeightChange: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var readingHeight: CGFloat?
    @AppStorage("glance.stripMetric") private var stripMetric = "cost"
    @AppStorage(GlanceContentPreferenceKey.surfaceOpacity) private var surfaceOpacity = 0.38
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

    init(store: MonitorStore, onQuit: @escaping () -> Void,
         onOpenCenter: @escaping (MonitorCenterSection) -> Void,
         onPreferredHeightChange: @escaping (CGFloat) -> Void) {
        self.store = store
        self.claude = store.claude
        self.onQuit = onQuit
        self.onOpenCenter = onOpenCenter
        self.onPreferredHeightChange = onPreferredHeightChange
    }

    private var provider: GlanceProvider { .resolve(savedProvider, claudeEnabled: claude.enabled) }
    private var claudeSnapshot: GlanceClaudeSnapshot {
        .init(limits: claude.limits, usage: claude.usage, statusLineEnabled: claude.statusLineEnabled, now: now)
    }
    private var quotaWindows: [RateLimitWindow] {
        provider == .claude ? claudeSnapshot.windows : primaryBucket?.windows ?? []
    }

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
        .background(alignment: .top) {
            if !reduceTransparency && contrast != .increased {
                RadialGradient(colors: [weatherColor.opacity((colorScheme == .dark ? 0.22 : 0.14) * (provider == .claude ? claudeSnapshot.glowMultiplier : 1)), .clear],
                               center: .top, startRadius: 0, endRadius: 250)
                    .frame(height: 300).blur(radius: 12)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: weatherTone)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GlanceLayout.cornerRadius))
        .environment(\.glanceTextShadow, colorScheme == .dark && surfaceOpacity < 0.30 && !reduceTransparency && contrast != .increased)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: primaryRemaining)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: claude.enabled) { enabled in
            if !enabled { savedProvider = GlanceProvider.codex.rawValue }
        }
        .onChange(of: provider) { _ in
            readingHeight = nil
            page = .summary
            showsResetConfirmation = false
            refreshStartedAt = .distantPast
            refreshVisualState = .idle
            refreshRotation = 0
            now = Date()
        }
        .onChange(of: claude.usage?.updatedAt) { date in
            if provider == .claude, let date, date >= refreshStartedAt, refreshVisualState == .refreshing {
                finishManualRefresh()
            }
        }
        .onChange(of: store.costSnapshot.updatedAt) { updatedAt in
            completeRefreshIfReady(updatedAt: updatedAt)
        }
        .onChange(of: store.costSnapshot.costActivity.count) { _ in
            completeRefreshIfReady(updatedAt: store.costSnapshot.updatedAt)
        }
        .onPreferenceChange(GlanceReadingHeightKey.self) { height in
            guard case .summary = page, height.isFinite, height > 0 else { return }
            let next = ceil(height)
            if readingHeight.map({ abs($0 - next) > 0.5 }) ?? true { readingHeight = next }
        }
        .onAppear {
            if !claude.enabled { savedProvider = GlanceProvider.codex.rawValue }
            now = Date()
        }
        .task(id: preferredHeight) {
            let height = preferredHeight
            // Window resizing during the hosting view's layout can be overwritten by
            // the same AppKit pass. Deliver the latest measurement after that pass.
            await Task.yield()
            guard !Task.isCancelled else { return }
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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: GlanceLayout.moduleSpacing) {
                        if showPrimaryQuota { primaryQuota }
                        if provider == .claude {
                            if showCostEstimate || showTokenActivity { dayStrip }
                            if claudeSnapshot.usageReady { dataBlocks }
                            else if !showCostEstimate && !showTokenActivity {
                                Text("正在统计 Claude 用量…").font(FloatingSurfaceTypography.label)
                                    .frame(maxWidth: .infinity, alignment: .leading).weatherModule()
                            }
                        } else if hasCurrentAccountHistory {
                            if showCostEstimate || showTokenActivity { dayStrip }
                            if showCreditBalance || showDailyTokens || showThirtyDayTokens { dataBlocks }
                        } else if showCostEstimate || showTokenActivity || showCreditBalance || showDailyTokens || showThirtyDayTokens {
                            currentAccountHistoryEmptyState
                        }
                        if provider == .codex && showResetEntry { resetCreditCard(store.quotaResetCredits).weatherModule() }
                    }
                    .id(provider)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: provider)
                    .padding(.horizontal, GlanceLayout.contentInset)
                    .padding(.vertical, GlanceLayout.readingInset)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: GlanceReadingHeightKey.self, value: proxy.size.height)
                        }
                    }
                }
                .frame(height: GlanceLayout.readingViewportHeight(panelHeight: geometry.size.height))
                .clipped()
                footer.padding(.horizontal, GlanceLayout.contentInset)
            }
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


            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 7) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(primaryText)
                    Text(store.quotaResetCredits.map { "\($0.availableCount)" } ?? "—")
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
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
                .weatherModule()

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
                .weatherModule()

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
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            return GlanceLayout.preferredHeight(readingHeight: readingHeight,
                estimatedHeight: contentPreferences.preferredHeight(primaryQuotaWindowCount: quotaWindows.count, provider: provider))
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
        HStack(spacing: 6) {
            CodexMark(size: 20)
            Text("Codex Pulse").font(.system(size: 13, weight: .semibold)).fixedSize()
            Spacer(minLength: 0)
            if claude.enabled {
                GlanceProviderSwitch(selection: Binding(get: { provider }, set: { savedProvider = $0.rawValue }))
                    .disabled(store.isConsumingQuotaResetCredit || showsResetConfirmation)
            } else { accountBadge }
        }
        .padding(.horizontal, GlanceLayout.contentInset)
        .frame(height: GlanceLayout.headerHeight)
    }

    private var accountBadge: some View {
            HStack(spacing: 4) {
                Circle().fill(currentAccountIndicatorColor).frame(width: 5, height: 5)
                Text(currentAccountBadgeTitle).font(.system(size: 9, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(FloatingSurfaceTheme.chipFill(colorScheme), in: Capsule())
            .help(currentAccountBadgeTitle)
    }

    private var weatherTone: GlanceTone {
        guard let window = primaryWindow else { return .calm }
        return GlanceTone(window: window, forecast: QuotaPaceForecast(window: window, now: now))
    }

    private var weatherColor: Color { weatherTone.color }

    private var primaryQuota: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 7) {
                if let window = primaryWindow {
                    let forecast = QuotaPaceForecast(window: window, now: context.date)
                    let copy = forecast.copy(resetsAt: window.resetsAt, now: context.date)
                    HStack(spacing: 5) {
                        Text(compactWindowTitle(window)).font(.system(size: 11, weight: .medium)).foregroundStyle(secondaryText)
                            .fixedSize()
                        Spacer(minLength: 0)
                        if provider == .codex && claude.enabled { accountBadge }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(window.remainingPercent)").font(.system(size: 64, weight: .semibold, design: .rounded))
                            .monospacedDigit().contentTransition(.numericText())
                        Text("%").font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(secondaryText)
                    }.glanceReadableText()
                    Text(copy.primary).font(.system(size: 12.5, weight: .medium)).glanceReadableText()
                    Text(copy.secondary + (provider == .claude ? claudeSnapshot.observationSuffix() : "")).font(.system(size: 10.5)).foregroundStyle(tertiaryText)
                    ForEach(Array(quotaWindows.filter { $0 != window }.enumerated()), id: \.offset) { _, other in
                        Text("\(compactWindowTitle(other)) \(other.remainingPercent)% · \(resetText(other))")
                            .font(.system(size: 10)).foregroundStyle(secondaryText)
                    }
                } else if provider == .claude {
                    Text("Claude 额度").font(FloatingSurfaceTypography.section)
                    Text(claudeSnapshot.quotaPlaceholder ?? "等待 Claude Code 下一次回复后同步额度")
                        .font(FloatingSurfaceTypography.label).foregroundStyle(tertiaryText)
                    if !claude.statusLineEnabled {
                        Button("打开 Claude 设置") { onOpenCenter(.claude) }
                            .buttonStyle(FloatingSurfaceButtonStyle())
                    }
                } else {
                    HStack {
                        Text("Codex 额度").font(FloatingSurfaceTypography.section)
                        Spacer(minLength: 0)
                        if claude.enabled { accountBadge }
                    }
                    Text(footerUpdateText == "数据可能过期" ? "额度加载失败" : "正在同步额度窗口…")
                        .font(FloatingSurfaceTypography.label).foregroundStyle(tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private var usesCostStrip: Bool { showCostEstimate && (!showTokenActivity || stripMetric != "token") }

    private var dayStrip: some View {
        let snapshot = claudeSnapshot
        let entries = provider == .claude
            ? (usesCostStrip ? snapshot.costSamples : snapshot.tokenSamples)
            : (usesCostStrip
                ? selectedCostScope.costActivity.map { GlanceDayStrip.Sample(date: $0.date, value: $0.dollars) }
                : selectedCostScope.usage.activity.map { GlanceDayStrip.Sample(date: $0.date, value: Double($0.tokens)) })
        return GlanceWeatherStrip(buckets: GlanceDayStrip.buckets(samples: entries, now: now),
            isCost: usesCostStrip, isReady: provider == .claude ? snapshot.usageReady : selectedCostScope.usage.activityIsReady,
            showsSelector: showCostEstimate && showTokenActivity, metric: $stripMetric, color: weatherColor,
            unknownModels: provider == .claude ? [] : selectedCostScope.unknownModels,
            loadingText: provider == .claude ? "正在统计 Claude 用量…" : "用量明细尚未就绪",
            tokenSourceLabel: provider == .claude ? "本机 Claude 用量" : "当前账号本地用量",
            unpricedDates: provider == .claude ? snapshot.unpricedDates : [])
    }

    private var dataBlocks: some View {
        HStack(spacing: 6) {
            if provider == .claude {
                if showDailyTokens { dataBlock("今日 Token", value: GlanceDayStrip.tokenText(Double(claudeSnapshot.todayTokens))) }
                if showThirtyDayTokens { dataBlock("30 日 Token", value: GlanceDayStrip.tokenText(Double(claudeSnapshot.monthlyTokens))) }
                dataBlock("累计 Token", value: claudeSnapshot.lifetimeTokens.map { GlanceDayStrip.tokenText(Double($0)) } ?? "—")
            } else {
                if showCreditBalance {
                    dataBlock("Credits", value: CreditBalanceFormatter.summary(primaryBucket?.creditBalance))
                        .help("完整余额：" + CreditBalanceFormatter.string(primaryBucket?.creditBalance))
                        .accessibilityValue(CreditBalanceFormatter.string(primaryBucket?.creditBalance))
                }
                if showDailyTokens { dataBlock("今日 Token", value: compactTokens(selectedCostScope.usage.day.tokens)) }
                if showThirtyDayTokens { dataBlock("30 日 Token", value: compactTokens(selectedCostScope.usage.month.tokens)) }
            }
        }
    }

    private func dataBlock(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9)).foregroundStyle(secondaryText)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).glanceReadableText()
        }.frame(maxWidth: .infinity, alignment: .leading).weatherModule()
            .accessibilityElement(children: .combine)
    }

    private func compactWindowTitle(_ window: RateLimitWindow) -> String {
        switch window.kind {
        case .fiveHour: return "5 小时额度"
        case .weekly: return "每周额度"
        case .custom, .unknown: return window.windowLabel
        }
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

    private var footer: some View {
        HStack(spacing: 4) {
            Circle().fill(footerStatusColor).frame(width: 5, height: 5)
            Text(footerUpdateText).font(.system(size: 9)).foregroundStyle(secondaryText).lineLimit(1)
            Spacer(minLength: 0)
            refreshFooterButton
            footerButton(symbol: "chart.bar", help: "打开监控中心") { onOpenCenter(.usage) }
            footerButton(symbol: "gearshape", help: "打开面板设置") { onOpenCenter(.panelSettings) }
            footerButton(symbol: "power", help: "退出 Codex Pulse", action: onQuit)
        }.frame(height: GlanceLayout.footerHeight)
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

    private func resetCreditCardContent(_ summary: QuotaResetCreditSummary?) -> some View {
        HStack(spacing: 6) {
            Text("额度重置").foregroundStyle(primaryText)
            Spacer(minLength: 0)
            Text(summary.map { $0.availableCount > 0 ? "\($0.availableCount) 次可使用" : resetCreditExpirationText(summary) } ?? "数据未知")
                .foregroundStyle(weatherColor).lineLimit(1).minimumScaleFactor(0.7)
            Image(systemName: "chevron.right").foregroundStyle(weatherColor)
        }.font(.system(size: 11, weight: .medium)).contentShape(Rectangle())
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
        .accessibilityLabel(help)
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
        if provider == .claude { claude.refreshUsage() }
        else { store.refreshAll() }

        let startedAt = refreshStartedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard refreshVisualState == .refreshing,
                  refreshStartedAt == startedAt
            else { return }
            finishManualRefresh()
        }
    }

    private func completeRefreshIfReady(updatedAt: Date) {
        guard provider == .codex, refreshVisualState == .refreshing,
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
        provider == .claude ? claudeSnapshot.limitingWindow : primaryBucket?.limitingWindow
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

    private var footerUpdateText: String {
        if provider == .claude {
            guard let date = claudeSnapshot.updatedAt else { return "等待数据" }
            if now.timeIntervalSince(date) < 60 { return "刚刚更新" }
            return "更新于 " + date.formatted(.dateTime.hour().minute())
        }
        switch store.quotaState {
        case .loading:
            return "正在更新"
        case let .loaded(_, date):
            if Date().timeIntervalSince(date) < 60 { return "刚刚更新" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "更新于 \(formatter.string(from: date))"
        case .failed:
            return "数据可能过期"
        }
    }

    private var footerStatusColor: Color {
        if provider == .claude {
            return claudeSnapshot.updatedAt == nil || claudeSnapshot.isStale || !claudeSnapshot.usageReady ? .orange : .green
        }
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
        CountFormatter.display(Int64(value))
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
