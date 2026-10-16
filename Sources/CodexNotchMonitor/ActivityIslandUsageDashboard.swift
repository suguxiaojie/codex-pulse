// Layout and chart interaction adapted from QuotaView f779531 IslandUsageBento (MIT).
// Copyright (c) 2026 Duoasa. Data comes from Codex Monitor's existing services.
import SwiftUI

struct ActivityIslandUsageDashboard: View {
    @ObservedObject var model: ActivityIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsReset = false
    @State private var flightActive = false
    @State private var flightSerial: UInt64 = 0
    @State private var usageHeight: CGFloat = 544
    @State private var resetHeight: CGFloat = 500
    @State private var mode = IslandDashboardHeatmap.Mode.daily
    @State private var selectedCost: Date?
    @State private var selectedActivity: String?
    @State private var hoveredCost: Date?
    @State private var hoveredActivity: Int?
    private var scope: CostScopeSnapshot { model.usageCost.aggregate }
    private var bucket: RateLimitBucket? { model.quotaState.buckets.first { $0.id == "codex" } }
    private var ready: Bool { model.usageCost.updatedAt != .distantPast }
    private var width: CGFloat { model.metrics.expandedRect.width }
    private var secondary: Color { .white.opacity(0.68) }
    private func tokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        for (scale, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] where Double(value) >= scale {
            return String(format: "%.1f", Double(value) / scale).replacingOccurrences(of: ".0", with: "") + suffix
        }
        return String(value)
    }
    private func money(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—" }
    private func heading(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
    }
    private func surface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .islandGlass(RoundedRectangle(cornerRadius: 14, style: .continuous),
                         tint: Color(white: 0.025).opacity(0.90), solidTint: Color(white: 0.025))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false) }
    }
    private func utility(_ icon: String, title: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24)
                .islandGlass(Circle(), tint: .white.opacity(0.04), clearSurface: true)
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { if showsReset { navigateReset(false) } else { model.onBackToTasks?() } } label: {
                    Label(showsReset ? "返回用量" : "返回任务", systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 9).frame(height: 24).islandGlass(Capsule(), tint: .white.opacity(0.04))
                }.buttonStyle(.plain)
                Text(showsReset ? "额度重置" : "用量统计").font(.system(size: 12, weight: .medium)).foregroundStyle(secondary)
                Spacer()
                utility(model.isPinned ? "pin.fill" : "pin", title: model.isPinned ? "取消置顶" : "固定展开", action: model.onPin)
                utility("chevron.up", title: "收起用量面板", action: model.onCollapse)
            }.padding(.horizontal, 28).frame(height: 36)
            pageFlow

        }
        .foregroundStyle(.white).frame(width: width, height: model.metrics.expandedRect.height, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: mode)
        .accessibilityElement(children: .contain).accessibilityLabel(showsReset ? "额度重置面板" : "用量统计面板")
        .onChange(of: model.privacyMode) { _ in flightActive = false }
        .onDisappear { flightActive = false; model.resetDetailVisible = false }
    }
    private var usagePage: some View {
            DashboardPageLayout(maximumHeight: model.metrics.maximumUsageHeight - 36,
                onHeightChange: { usageHeight = $0; if !showsReset { model.onUsageHeightChange?($0 + 36) } }) {
                VStack(spacing: 10) {
                    if model.privacyMode {
                        surface { Text("隐私模式已开启").font(.system(size: 14, weight: .medium)) }
                    } else {
                        if !IslandFloatingQuotaPeriods.current(model.quotaState) {
                            Text(bucket == nil ? "额度暂不可用，等待刷新" : "额度显示上次数据，等待刷新")
                                .font(.system(size: 10)).foregroundStyle(secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    if let windows = bucket?.windows, !windows.isEmpty {
                                        ForEach(windows.indices, id: \.self) { quotaCard(windows[$0]) }
                                    } else { quotaCard(nil) }
                                }
                                HStack(spacing: 10) {
                                    metric("最近一天 Tokens", value: model.accountUsage.map { tokens($0.recentTokens) } ?? (ready ? tokens(scope.usage.day.tokens) : "—"))
                                    metric("30 天 Tokens", value: model.accountUsage.map { tokens($0.monthlyTokens) } ?? (ready ? tokens(scope.usage.month.tokens) : "—"))
                                    metric("累计 Tokens", value: model.accountUsage.map { tokens($0.lifetimeTokens) } ?? tokens(scope.lifetimeTokens))
                                }
                            }.frame(maxWidth: .infinity)
                            Color.clear.frame(width: min(204, max(168, (width - 56) * 0.327))).overlay { accountCard }
                        }.fixedSize(horizontal: false, vertical: true)
                        costCard.zIndex(hoveredCost == nil ? 0 : 1)
                        activityCard.zIndex(hoveredActivity == nil ? 0 : 1)
                    }
                }.padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 8)
            } footer: {
            HStack {
                Text(model.privacyMode ? "隐私模式" : ready ? "更新于 " + model.usageCost.updatedAt.formatted(date: .omitted, time: .shortened) : "等待数据")
                    .font(.system(size: 11))
                Spacer()
                utility("arrow.clockwise", title: "刷新额度与用量", action: model.onRefresh)
                utility("gearshape", title: "灵动岛设置", action: model.onOpenSettings)
            }.padding(.horizontal, 28).frame(height: 36)
            }
    }
    private var pageFlow: some View {
        ZStack(alignment: .top) {
            usagePage.frame(width: width, height: usageHeight, alignment: .top)
                .opacity(showsReset ? 0 : 1)
                .allowsHitTesting(!showsReset && !flightActive).accessibilityHidden(showsReset)
                .environment(\.islandGlassActive, !showsReset)
            IslandDashboardResetPage(model: model, hidesTicket: flightActive) { height in
                resetHeight = height
                if showsReset { model.onUsageHeightChange?(height + 36) }
            }
            .frame(width: width, height: resetHeight, alignment: .top)
            .opacity(showsReset ? 1 : 0)
            .allowsHitTesting(showsReset && !flightActive).accessibilityHidden(!showsReset)
            .environment(\.islandGlassActive, showsReset)
        }
        .frame(width: width, height: max(usageHeight, resetHeight), alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showsReset)
        .overlayPreferenceValue(DashboardResetTicketAnchors.self) { anchors in
            GeometryReader { proxy in
                DashboardResetTicketFlightView(serial: flightSerial, toReset: showsReset,
                    active: flightActive && model.playbackVisible && !model.privacyMode,
                    source: anchors[.usage].map { proxy[$0] } ?? .zero,
                    destination: anchors[.reset].map { proxy[$0] } ?? .zero,
                    reduceMotion: reduceMotion,
                    onCompletion: { serial in if serial == flightSerial { flightActive = false } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
    private func navigateReset(_ reset: Bool) {
        flightSerial &+= 1
        let serial = flightSerial
        flightActive = !reduceMotion && !model.privacyMode
        showsReset = reset
        model.resetDetailVisible = reset
        model.onUsageHeightChange?((reset ? resetHeight : usageHeight) + 36)
        // Restore the static card if layout/attachment prevents a compositor start.
        DispatchQueue.main.asyncAfter(deadline: .now() + DashboardResetTicketFlight.duration + 0.6) {
            if flightSerial == serial { flightActive = false }
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        surface {
            VStack(alignment: .leading, spacing: 10) {
                heading(title).lineLimit(1).minimumScaleFactor(0.75)
                Text(value) .font(AstaSans.semiBold(21)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
    private func quotaCard(_ window: RateLimitWindow?) -> some View {
        surface {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { heading(window?.windowLabel ?? "额度剩余"); Spacer(minLength: 3); heading(reset(window)) }
                    VStack(alignment: .leading, spacing: 4) { heading(window?.windowLabel ?? "额度剩余"); heading(reset(window)) }
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(window.map { "\($0.remainingPercent)%" } ?? "—") .font(AstaSans.semiBold(21)).monospacedDigit()
                    if window != nil { heading("剩余") }
                    Spacer(minLength: 2)
                    heading(window.map { "已使用 \($0.usedPercent)%" } ?? "—").lineLimit(1).minimumScaleFactor(0.75)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.32))
                        Capsule().fill(quotaColor(window?.remainingPercent)).frame(width: proxy.size.width * CGFloat(window?.remainingPercent ?? 0) / 100)
                    }
                }.frame(height: 8).accessibilityHidden(true)
            }
        }
    }
    private func reset(_ window: RateLimitWindow?) -> String {
        guard let date = window?.resetsAt else { return "重置时间 —" }
        let hours = max(0, Int(ceil(date.timeIntervalSinceNow / 3600)))
        return hours >= 24 ? "\(hours / 24)天\(hours % 24)小时后重置" : "\(hours)小时后重置"
    }
    private func quotaColor(_ percent: Int?) -> Color {
        guard let percent else { return .gray }
        return percent >= 50 ? Color(red: 0, green: 0.92, blue: 0.1) : percent >= 20 ? .yellow : .red
    }
    private var creditBalance: String {
        guard let raw = bucket?.creditBalance else { return "—" }
        guard let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSDecimalNumber(decimal: number)) ?? raw
    }
    private var accountCard: some View {
        surface {
            VStack(alignment: .leading, spacing: 12) {
                heading("账户")
                Text(OpenAIPlanDisplayName.resolve(bucket?.planType) ?? "—").font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 12)
                HStack { heading("积分余额"); Spacer(); Text(creditBalance).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7) }
                Divider().overlay(.white.opacity(0.12))
                Button { navigateReset(true) } label: {
                    HStack {
                        DashboardResetTicket(playbackEnabled: model.playbackVisible && !flightActive)
                            .opacity(flightActive ? 0 : 1)
                            .anchorPreference(key: DashboardResetTicketAnchors.self, value: .bounds) { [.usage: $0] }
                            .accessibilityHidden(true)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            heading("额度重置")
                            Text(model.resetCredits.map { "\($0.availableCount) 次" } ?? "—").font(.system(size: 12))
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("在灵动岛内查看重置次数与有效期，点击票卡不会消耗次数")
            }.frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private var chart: IslandDashboardCost { .init(account: model.accountUsage, local: scope) }
    private var contentWidth: CGFloat { width - 56 }
    private var activityPlotWidth: CGFloat { max(contentWidth - 28, 53 * 10 + 52 * 3) }
    private var cellSize: CGFloat { IslandDashboardHeatmap.cellSize(width: activityPlotWidth) }
    private var costCellSize: CGFloat { max(8, IslandDashboardHeatmap.cellSize(width: contentWidth - 28)) }
    private var costPlotWidth: CGFloat { CGFloat(chart.days.count) * costCellSize + CGFloat(max(0, chart.days.count - 1)) * 3 }
    private var costViewport: CGFloat { min(costPlotWidth, max(104, contentWidth - 28 - 208 - 28)) }
    private var summaryWidth: CGFloat { max(1, (contentWidth - 28 - costViewport - 28) / 2) }
    private var generation: String { "\(model.accountUsage != nil)-\(chart.days.last?.date.timeIntervalSinceReferenceDate ?? 0)" }
    private var costCard: some View {
        let chart = self.chart
        let selected = chart.days.first { $0.date == selectedCost }
        return surface {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    heading(chart.official ? "官方用量折算" : "本地模型计价")
                    Text(money(chart.total)).font(AstaSans.semiBold(21)).tracking(-0.21).lineLimit(1).minimumScaleFactor(0.8)
                    heading("最近 30 天")
                }.frame(width: summaryWidth, alignment: .leading)
                DashboardRecentChartScroll(plotWidth: costPlotWidth, viewportWidth: costViewport, plotHeight: 58, resetID: generation) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(chart.days) { day in
                            Button { selectedCost = selectedCost == day.date ? nil : day.date } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(selectedCost == day.date || hoveredCost == day.date ? .white : Color(white: day.cost == nil ? 0.18 : 0.35 + 0.4 * (day.cost ?? 0) / chart.maximum))
                                    .frame(width: costCellSize, height: max(3, 58 * (day.cost ?? 0) / chart.maximum))
                                    .frame(height: 58, alignment: .bottom).contentShape(Rectangle())
                            }.buttonStyle(.plain)
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
                            Text(money(day.cost) + " · 估算值")
                            Text(tokens(day.tokens) + " Tokens")
                        }
                    }
                }.padding(.top, 14).zIndex(10)
                VStack(alignment: .trailing, spacing: 10) {
                    heading(selected?.date.formatted(.dateTime.month().day()) ?? "最近一天")
                    Text(money(selected != nil ? selected?.cost : chart.latest?.cost)).font(AstaSans.semiBold(17)).lineLimit(1).minimumScaleFactor(0.8)
                    heading("估算值 · 非账单")
                }.frame(width: summaryWidth, alignment: .trailing)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .help(chart.official ? "与 QuotaView 相同：当前账号官方 UTC 每日 Token × $0.50／百万；统一折算，不是实际模型账单。" : "官方汇总不可用：回退本机全部账号日志，按模型输入／输出／缓存费率估算。")
        .accessibilityHint(chart.official ? "当前账号官方 Token 按每百万 0.50 美元统一估算" : "本机全部账号模型计价估算")
    }
    private var activityCard: some View {
        let official = model.accountUsage
        let activity = official.map { ($0.days ?? []).map { DailyTokenActivity(date: $0.date, tokens: $0.tokens) } } ?? scope.usage.activity
        let grid = IslandDashboardHeatmap(activity: activity, endingAt: max(Date(), activity.last?.date ?? Date()), mode: mode,
            lifetimeTokens: official != nil ? official?.lifetimeTokens : scope.lifetimeTokens)
        return surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    heading("Token 活动")
                    if let selectedActivity { heading(selectedActivity).lineLimit(1) }
                    Spacer(minLength: 8)
                    ForEach(IslandDashboardHeatmap.Mode.allCases, id: \.self) { option in
                        Button { mode = option; selectedActivity = nil; hoveredActivity = nil } label: {
                            Text(option == .daily ? "每天" : option == .weekly ? "每周" : "累计")
                                .font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4)
                                .islandGlass(Capsule(), tint: mode == option ? .white.opacity(0.20) : .black.opacity(0.28))
                        }.buttonStyle(.plain).accessibilityValue(mode == option ? "已选择" : "未选择")
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
                                                .fill(filled ? heatColor(cell.tokens, maximum: grid.maximum) : Color(white: 0.18))
                                                .overlay { if hoveredActivity == index { RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.8), lineWidth: 1) } }
                                                .frame(width: cellSize, height: cellSize).opacity(cell.future ? 0.25 : 1)
                                        }.buttonStyle(.plain).disabled(cell.future).accessibilityLabel(label)
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
                                    .font(.system(size: 9)).foregroundStyle(secondary)
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
        .help(official != nil ? "当前账号官方用量，按 UTC 日期统计。" : "官方汇总不可用，显示本机全部账号的近 180 天日志。")
        .onChange(of: width) { _ in hoveredCost = nil; hoveredActivity = nil }
        .onDisappear { hoveredCost = nil; hoveredActivity = nil }
    }
    private func heatColor(_ value: Int?, maximum: Int) -> Color {
        guard let value, value > 0 else { return Color(white: 0.18) }
        let level = Double(value) / Double(max(1, maximum))
        if level < 0.25 { return Color(red: 0.02, green: 0.23, blue: 0.40) }
        if level < 0.5 { return Color(red: 0.02, green: 0.35, blue: 0.61) }
        if level < 0.75 { return Color(red: 0.02, green: 0.53, blue: 0.92) }
        return Color(red: 0.39, green: 0.71, blue: 1)
    }
    // Resolve the upstream anchor outside the scroll clip so edge cells retain a readable tooltip.
    private func tooltip<Content: View>(anchor: Anchor<CGRect>?, height: CGFloat, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            if let anchor {
                let rect = proxy[anchor]
                let width = min(214, proxy.size.width)
                if rect.maxX > 0 && rect.minX < proxy.size.width {
                    VStack(alignment: .leading, spacing: 3, content: content)
                        .font(.system(size: 11)).foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 8)
                        .frame(width: width, alignment: .leading)
                        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.23), lineWidth: 1) }
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
