import SwiftUI

private protocol IslandUsageFormatting {}
private extension IslandUsageFormatting {
    var secondary: Color { FloatingSurfaceTheme.secondary() }
    func tokens(_ value: Int?) -> String {
        value.map { CountFormatter.display(Int64($0)) } ?? "—"
    }
    func money(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—" }
    func heading(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
    }
    func surface<Content: View>(verticalPadding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        content().padding(.horizontal, 14).padding(.vertical, verticalPadding).frame(maxWidth: .infinity, alignment: .leading)
            .islandGlass(RoundedRectangle(cornerRadius: 14, style: .continuous),
                         tint: Color(white: 0.025).opacity(0.90), solidTint: Color(white: 0.025))
    }
}

struct ClaudeMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let lengths: [CGFloat] = [1, 0.84, 0.96, 0.78, 0.92, 0.86]
        var path = Path(ellipseIn: CGRect(x: center.x - radius * 0.16, y: center.y - radius * 0.16,
                                          width: radius * 0.32, height: radius * 0.32))
        for index in 0..<12 {
            let angle = CGFloat(index) * .pi / 6 - .pi / 2
            let dx = cos(angle), dy = sin(angle)
            func point(_ distance: CGFloat, _ halfWidth: CGFloat) -> CGPoint {
                CGPoint(x: center.x + radius * (dx * distance - dy * halfWidth),
                        y: center.y + radius * (dy * distance + dx * halfWidth))
            }
            let tip = min(0.98, lengths[index % lengths.count])
            path.move(to: point(0.12, 0.11))
            path.addLine(to: point(tip, 0.025))
            path.addLine(to: point(tip, -0.025))
            path.addLine(to: point(0.12, -0.11))
            path.closeSubpath()
        }
        return path
    }
}

struct IslandUsageProviderSwitch: View {
    @ObservedObject var model: ActivityIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IslandUsageProvider.allCases, id: \.self) { provider in
                let disabled = (provider == .claude && !model.claudeEnabled) || model.resetBusy || model.resetConfirmationPresented
                Button {
                    withAnimation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion) { model.selectUsageProvider(provider) }
                } label: {
                    HStack(spacing: 5) {
                        if provider == .codex {
                            if let icon = ActivityIslandPreviewAssets.codexIcon {
                                Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit()
                                    .frame(width: 13, height: 13).accessibilityHidden(true)
                            }
                        } else {
                            ClaudeMarkShape().fill(Color(red: 0.851, green: 0.467, blue: 0.341))
                                .frame(width: 13, height: 13)
                                .opacity(model.usageProvider == provider ? 1 : 0.6)
                                .saturation(disabled ? 0 : 1).accessibilityHidden(true)
                        }
                        Text(provider.rawValue).font(FloatingSurfaceTypography.control)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .foregroundStyle(model.usageProvider == provider ? FloatingSurfaceTheme.primary() : FloatingSurfaceTheme.secondary())
                        .background {
                            if model.usageProvider == provider {
                                Capsule().fill(FloatingSurfaceTheme.accent().opacity(0.20))
                                    .matchedGeometryEffect(id: "provider-selection", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(FloatingSurfaceButtonStyle())
                    .disabled(disabled)
                    .accessibilityLabel(provider.rawValue)
                    .accessibilityValue(model.usageProvider == provider ? "已选择" : "未选择")
                    .accessibilityAddTraits(model.usageProvider == provider ? .isSelected : [])
                    .help(provider == .claude && !model.claudeEnabled ? "请先在监控中心启用 Claude Code" : "查看 " + provider.rawValue + " 用量")
            }
        }.frame(width: 240, height: 28)
            .islandGlass(Capsule(), tint: .black.opacity(0.28))
            .animation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion, value: model.usageProvider)
            .accessibilityElement(children: .contain).accessibilityLabel("用量来源")
    }
}

struct IslandUsageSourceCard: View, IslandUsageFormatting {
    let source: IslandUsagePresentation.Source
    let playbackVisible: Bool
    let flightActive: Bool
    let onReset: () -> Void
    var body: some View {
        switch source {
        case .codex(let planName, let balance, let resetCount):
            codexAccountCard(planName: planName, balance: balance, resetCount: resetCount)
        case .claude:
            surface {
                VStack(alignment: .leading, spacing: 8) {
                    heading("用量来源")
                    Text("Claude Code").font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 4)
                    heading("额度 · 官方状态栏")
                    heading("历史 · 本机全部会话（含子 Agent）")
                }.frame(maxHeight: .infinity, alignment: .topLeading)
            }.help("历史为本机全部会话，含子 Agent；账号归属未推断。")
        }
    }
    private func codexAccountCard(planName: String, balance: String?, resetCount: Int?) -> some View {
        surface {
            VStack(alignment: .leading, spacing: 6) {
                heading("账户")
                Text(planName).font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 2)
                HStack { heading("积分余额"); Spacer(); Text(CreditBalanceFormatter.summary(balance)).font(FloatingSurfaceTypography.metadata).lineLimit(1).minimumScaleFactor(0.7) }
                    .help("完整余额：" + CreditBalanceFormatter.string(balance))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("积分余额")
                    .accessibilityValue(CreditBalanceFormatter.string(balance))
                Divider().overlay(FloatingSurfaceTheme.separator())
                Button { onReset() } label: {
                    HStack {
                        DashboardResetTicket(playbackEnabled: playbackVisible && !flightActive)
                            .opacity(flightActive ? 0 : 1)
                            .anchorPreference(key: DashboardResetTicketAnchors.self, value: .bounds) { [.usage: $0] }
                            .accessibilityHidden(true)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            heading("额度重置")
                            Text(resetCount.map { "\($0) 次" } ?? "—").font(FloatingSurfaceTypography.body)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(FloatingSurfaceButtonStyle()).help("在灵动岛内查看重置次数与有效期，点击票卡不会消耗次数")
            }.frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct IslandUsageMetricStrip: View, IslandUsageFormatting {
    @AppStorage(CountStyle.preferenceKey) private var countStyle = CountStyle.chinese.rawValue
    let metrics: [IslandUsagePresentation.Metric]
    var body: some View {
        surface(verticalPadding: 10) {
            HStack(spacing: 14) {
                ForEach(metrics.indices, id: \.self) { index in
                    if index > 0 { Rectangle().fill(FloatingSurfaceTheme.separator()).frame(width: 1) }
                    VStack(alignment: .leading, spacing: 6) {
                        heading(metrics[index].title).lineLimit(1).minimumScaleFactor(0.75)
                        Text(tokens(metrics[index].tokens)).foregroundStyle(FloatingSurfaceTheme.usageData())
                            .font(FloatingSurfaceTypography.primaryMetric).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        if let date = metrics[index].dateTag {
                            Text(date).font(FloatingSurfaceTypography.metadata).foregroundStyle(secondary)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct IslandUsageQuotaRow: View, IslandUsageFormatting {
    let quotas: [IslandUsagePresentation.Quota]
    let now: Date
    var body: some View {
        HStack(spacing: 10) { ForEach(quotas.indices, id: \.self) { quotaCard(quotas[$0]) } }
    }
    private func quotaCard(_ quota: IslandUsagePresentation.Quota) -> some View {
        surface {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { heading(quota.title).fixedSize(); Spacer(minLength: 10); heading(quota.freshness.observationLabel(now: now) ?? reset(quota.resetsAt)).fixedSize() }
                    VStack(alignment: .leading, spacing: 4) { heading(quota.title); heading(quota.freshness.observationLabel(now: now) ?? reset(quota.resetsAt)) }
                }
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .leading, spacing: 10) {
                        percentageRow(quota, showsRemaining: true, showsUsed: true)
                        progress(quota)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        percentageRow(quota, showsRemaining: false, showsUsed: true)
                        progress(quota)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        percentageRow(quota, showsRemaining: false, showsUsed: false)
                        progress(quota)
                        usedLabel(quota)
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .topLeading)
        }.opacity(quota.freshness.isStale ? 0.55 : 1)
            .help(reset(quota.resetsAt))
            .accessibilityElement(children: .combine)
            .accessibilityValue(quota.freshness.isStale ? "上次观测，非当前" : "")
    }
    private func percentageRow(_ quota: IslandUsagePresentation.Quota, showsRemaining: Bool, showsUsed: Bool) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(quota.remainingPercent.map { "\($0)%" } ?? "—")
                .font(FloatingSurfaceTypography.primaryMetric).monospacedDigit().fixedSize()
            if showsRemaining && quota.remainingPercent != nil { heading("剩余").fixedSize() }
            Spacer(minLength: 10)
            if showsUsed { usedLabel(quota) }
        }
    }
    private func usedLabel(_ quota: IslandUsagePresentation.Quota) -> some View {
        heading(quota.usedPercent.map { "已使用 \($0)%" } ?? "—").fixedSize()
    }
    private func progress(_ quota: IslandUsagePresentation.Quota) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(FloatingSurfaceTheme.track())
                Capsule().fill(quota.freshness.isStale ? secondary : FloatingSurfaceTheme.quotaHealth(quota.remainingPercent))
                    .frame(width: proxy.size.width * CGFloat(quota.remainingPercent ?? 0) / 100)
            }
        }.frame(height: 8).accessibilityHidden(true)
    }
    private func reset(_ date: Date?) -> String {
        guard let date else { return "重置时间 —" }
        let hours = max(0, Int(ceil(date.timeIntervalSince(now) / 3600)))
        return ChineseDisplayText.spacing(hours >= 24 ? "\(hours / 24)天\(hours % 24)小时后重置" : "\(hours)小时后重置")
    }
}

struct IslandUsageTrendCard: View, IslandUsageFormatting {
    @AppStorage(CountStyle.preferenceKey) private var countStyle = CountStyle.chinese.rawValue
    let presentation: IslandUsagePresentation
    let width: CGFloat
    let now: Date
    @Binding var mode: IslandDashboardHeatmap.Mode
    @Binding var selectedCost: Date?
    @Binding var selectedActivity: String?
    @Binding var hoveredCost: Date?
    @Binding var hoveredActivity: Int?
    private var chart: IslandUsagePresentation.Cost { presentation.cost }
    var body: some View {
        surface(verticalPadding: 8) {
            VStack(spacing: 8) {
                costCard.zIndex(hoveredCost == nil ? 0 : 1)
                Divider().overlay(FloatingSurfaceTheme.separator())
                activityCard.zIndex(hoveredActivity == nil ? 0 : 1)
            }
        }
    }
    private var contentWidth: CGFloat { width - 56 }
    private var activityPlotWidth: CGFloat { max(contentWidth - 28, 53 * 10 + 52 * 3) }
    private var cellSize: CGFloat { IslandDashboardHeatmap.cellSize(width: activityPlotWidth) }
    private var costCellSize: CGFloat { max(8, IslandDashboardHeatmap.cellSize(width: contentWidth - 28)) }
    private var costPlotWidth: CGFloat { CGFloat(chart.days.count) * costCellSize + CGFloat(max(0, chart.days.count - 1)) * 3 }
    private var costViewport: CGFloat { min(costPlotWidth, max(104, contentWidth - 28 - 208 - 28)) }
    private var summaryWidth: CGFloat { max(1, (contentWidth - 28 - costViewport - 28) / 2) }
    private var generation: String { "\(presentation.provider.rawValue)-\(presentation.supportsReset)-\(chart.days.last?.date.timeIntervalSinceReferenceDate ?? 0)" }
    private var costCard: some View {
        let chart = self.chart
        let selected = chart.days.first { $0.date == selectedCost }
        return Group {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    heading(chart.title)
                    Text((chart.totalIsLowerBound && chart.total != nil ? "≥" : "") + money(chart.total)).foregroundStyle(FloatingSurfaceTheme.costData()).font(FloatingSurfaceTypography.primaryMetric).tracking(-0.21).lineLimit(1).minimumScaleFactor(0.8)
                    heading(chart.note)
                }.frame(width: summaryWidth, alignment: .leading)
                DashboardRecentChartScroll(plotWidth: costPlotWidth, viewportWidth: costViewport, plotHeight: 58, resetID: generation) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(chart.days) { day in
                            Button { selectedCost = selectedCost == day.date ? nil : day.date } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(day.cost == nil ? FloatingSurfaceTheme.track() : FloatingSurfaceTheme.costData().opacity(selectedCost == day.date || hoveredCost == day.date ? 1 : 0.35 + 0.4 * (day.cost ?? 0) / chart.maximum))
                                    .frame(width: costCellSize, height: max(3, 58 * (day.cost ?? 0) / chart.maximum))
                                    .frame(height: 58, alignment: .bottom).contentShape(Rectangle())
                            }.buttonStyle(FloatingSurfaceButtonStyle())
                                .onHover { inside in if inside { hoveredCost = day.date } else if hoveredCost == day.date { hoveredCost = nil } }
                                .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted) + " " + money(day.cost))
                                .anchorPreference(key: DashboardHoverAnchor.self, value: .bounds) { hoveredCost == day.date ? $0 : nil }
                        }
                    }
                }
                .overlayPreferenceValue(DashboardHoverAnchor.self) { anchor in
                    if let day = chart.days.first(where: { $0.date == hoveredCost }) {
                        tooltip(anchor: anchor, height: 78) {
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                            Text(day.cost == nil ? chart.missingLabel(for: day) : money(day.cost) + " · 估算值")
                            Text(tokens(day.tokens) + " Tokens")
                        }
                    }
                }.padding(.top, 8).zIndex(10)
                VStack(alignment: .trailing, spacing: 10) {
                    heading(selected?.date.formatted(.dateTime.month().day()) ?? chart.latestDateTag ?? "最近一天")
                    Text(money(selected != nil ? selected?.cost : chart.latest?.cost)).font(Font.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    heading("估算值 · 非账单")
                }.frame(width: summaryWidth, alignment: .trailing)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .help(chart.helpText)
        .accessibilityHint(chart.accessibilityHint)
    }
    private var activityCard: some View {
        let grid = IslandDashboardHeatmap(activity: presentation.activity,
            endingAt: max(now, presentation.activity.last?.date ?? now), mode: mode,
            lifetimeTokens: presentation.lifetimeTokens)
        return Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    heading("Token 活动")
                    if let selectedActivity { heading(selectedActivity).lineLimit(1) }
                    Spacer(minLength: 8)
                    ForEach(IslandDashboardHeatmap.Mode.allCases, id: \.self) { option in
                        Button { mode = option; selectedActivity = nil; hoveredActivity = nil } label: {
                            Text(option == .daily ? "每天" : option == .weekly ? "每周" : "累计")
                                .font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4)
                                .islandGlass(Capsule(), tint: mode == option ? FloatingSurfaceTheme.accent().opacity(0.20) : .black.opacity(0.28))
                        }.buttonStyle(FloatingSurfaceButtonStyle()).accessibilityValue(mode == option ? "已选择" : "未选择")
                    }
                }
                DashboardRecentChartScroll(plotWidth: activityPlotWidth, viewportWidth: contentWidth - 28,
                    plotHeight: IslandDashboardHeatmap.chartHeight(width: activityPlotWidth), resetID: generation + "-\(mode)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(0..<53, id: \.self) { column in
                                VStack(spacing: 3) {
                                    ForEach(0..<7, id: \.self) { row in
                                        let index = grid.cellIndex(column: column, row: row)
                                        let cell = grid.cells[index]
                                        let filled = mode == .daily || grid.isFilled(column: column, row: row)
                                        let label = cell.date.formatted(date: .abbreviated, time: .omitted) + " · " + tokens(cell.tokens)
                                        Button { selectedActivity = label } label: {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(filled ? heatColor(cell.tokens, maximum: grid.maximum) : FloatingSurfaceTheme.track())
                                                .overlay { if hoveredActivity == index { RoundedRectangle(cornerRadius: 2).strokeBorder(FloatingSurfaceTheme.usageData(), lineWidth: 1) } }
                                                .frame(width: cellSize, height: cellSize).opacity(cell.future ? 0.25 : 1)
                                        }.buttonStyle(FloatingSurfaceButtonStyle()).disabled(cell.future).accessibilityLabel(label)
                                            .onHover { inside in if inside { hoveredActivity = index } else if hoveredActivity == index { hoveredActivity = nil } }
                                            .anchorPreference(key: DashboardHoverAnchor.self, value: .bounds) { hoveredActivity == index && (mode == .daily || row == 0) ? $0 : nil }
                                            .accessibilityRepresentation {
                                                Button(label) { selectedActivity = label }.disabled(cell.future)
                                            }
                                    }
                                }
                            }
                        }
                        ZStack(alignment: .leading) {
                            ForEach(grid.months.indices, id: \.self) { index in
                                Text(grid.months[index].date.formatted(.dateTime.month(.abbreviated)))
                                    .font(FloatingSurfaceTypography.fine).foregroundStyle(secondary)
                                    .offset(x: CGFloat(grid.months[index].column) * (cellSize + 3))
                            }
                        }.frame(width: activityPlotWidth, height: 12, alignment: .leading)
                    }
                }
                .overlayPreferenceValue(DashboardHoverAnchor.self) { anchor in
                    if let index = hoveredActivity, grid.cells.indices.contains(index) {
                        tooltip(anchor: anchor, height: 58) {
                            Text(grid.cells[index].date.formatted(date: .abbreviated, time: .omitted))
                            Text(tokens(grid.cells[index].tokens) + " Tokens")
                        }
                    }
                }
            }
        }
        .help(presentation.activityHelp)
        .onChange(of: width) { _ in hoveredCost = nil; hoveredActivity = nil }
        .onDisappear { hoveredCost = nil; hoveredActivity = nil }
    }
    private func heatColor(_ value: Int?, maximum: Int) -> Color {
        guard let value, value > 0 else { return FloatingSurfaceTheme.track() }
        let level = Double(value) / Double(max(1, maximum))
        if level < 0.25 { return FloatingSurfaceTheme.usageData().opacity(0.25) }
        if level < 0.5 { return FloatingSurfaceTheme.usageData().opacity(0.45) }
        if level < 0.75 { return FloatingSurfaceTheme.usageData().opacity(0.65) }
        return FloatingSurfaceTheme.usageData().opacity(0.90)
    }
    // Resolve the upstream anchor outside the scroll clip so edge cells retain a readable tooltip.
    private func tooltip<Content: View>(anchor: Anchor<CGRect>?, height: CGFloat, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            if let anchor {
                let rect = proxy[anchor]
                let width = min(214, proxy.size.width)
                if rect.maxX > 0 && rect.minX < proxy.size.width {
                    VStack(alignment: .leading, spacing: 3, content: content)
                        .font(FloatingSurfaceTypography.caption).foregroundStyle(FloatingSurfaceTheme.primary()).padding(.horizontal, 11).padding(.vertical, 8)
                        .frame(width: width, alignment: .leading)
                        .background(FloatingSurfaceTheme.popover(), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(FloatingSurfaceTheme.outline(), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                        .offset(x: min(max(0, rect.midX - width / 2), max(0, proxy.size.width - width)), y: rect.minY - height)
                }
            }
        }.allowsHitTesting(false)
    }
}
private struct DashboardHoverAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { if let next = nextValue() { value = next } }
}
