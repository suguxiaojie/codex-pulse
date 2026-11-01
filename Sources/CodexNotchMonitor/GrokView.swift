import SwiftUI
import Charts

struct GrokView: View {
    @ObservedObject var runtime: GrokRuntime
    @State private var days = 30
    @State private var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CountStyle.preferenceKey) private var countStyle = CountStyle.chinese.rawValue

    private var history: [GrokUsageSummary.Day] {
        let lower = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: now))!
        return (runtime.usage?.days ?? []).filter { $0.date >= lower && $0.date <= now }.sorted { $0.date < $1.date }
    }

    private var tokenTotal: Int { history.reduce(0) { GrokJSON.add($0, $1.tokens) } }

    private var knownCosts: [Double] { history.compactMap(\.cost) }

    private var costIsPartial: Bool {
        history.contains { $0.cost == nil } || runtime.usage?.complete != true
    }

    private var costText: String {
        if runtime.usage == nil || (!history.isEmpty && knownCosts.isEmpty) { return "—" }
        return (costIsPartial ? "≥ " : "") + String(format: "$%.4f", knownCosts.reduce(0, +))
    }

    private var usageCaption: String {
        "本机轮次记录，fork 历史去重；成本来自 CLI 报告，不是订阅账单。"
            + (runtime.usage?.complete == false ? "当前只覆盖部分记录。" : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connection.modifier(MonitorDesktopReveal(delay: 0))
                if runtime.enabled {
                    quotaCard.modifier(MonitorDesktopReveal(delay: 0.04))
                    usageCard.modifier(MonitorDesktopReveal(delay: 0.08))
                    tasksCard.modifier(MonitorDesktopReveal(delay: 0.12))
                }
            }
            .padding(.bottom, 8)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onAppear { now = Date(); runtime.refreshAutomaticStatus() }
        .onChange(of: runtime.quota?.capturedAt) { _ in now = Date() }
    }

    private var connection: some View {
        PanelSettingsGroup(title: "Grok CLI 连接", symbol: "sparkle") {
            SettingsRow(symbol: "terminal", title: "任务与用量", detail: "官方额度和本机会话；自动问答仅管理下方的共享启动设置。") {
                Toggle("启用 Grok CLI", isOn: Binding(get: { runtime.enabled }, set: { runtime.configure(enabled: $0) }))
                    .labelsHidden()
                    .toggleStyle(PanelSettingsToggleStyle(onTitle: "开启", offTitle: "关闭"))
                    .accessibilityLabel("启用 Grok CLI")
            }
            SettingsRowDivider()
            SettingsRow(symbol: "arrow.clockwise", title: "官方额度", detail: runtime.quotaStatus) {
                Button(runtime.refreshing ? "正在查询…" : "刷新") { runtime.refresh() }
                    .buttonStyle(PanelSettingsActionStyle())
                    .disabled(!runtime.enabled || runtime.refreshing)
                    .help(runtime.refreshing ? "正在查询官方额度" : "刷新官方额度")
            }
            SettingsRowDivider()
            SettingsRow(symbol: "bubble.left.and.text.bubble.right", title: "自动接入问答与批准", detail: runtime.automaticReady ? runtime.questionStatus : runtime.automaticStatus) {
                Button(runtime.automaticConfiguring ? "正在配置…" : runtime.automaticReady ? "检查连接" : "开启自动接入") {
                    if runtime.automaticReady { runtime.refreshAutomaticStatus(); runtime.refreshActivity() }
                    else { runtime.enableAutomatic() }
                }
                .buttonStyle(PanelSettingsActionStyle(prominent: !runtime.automaticReady && !runtime.automaticConfiguring))
                .disabled(runtime.automaticConfiguring)
            }
            Text("一次启用官方共享启动设置后，照常在任意项目运行 grok 即可；无需选目录或新建终端。原值会备份，仅影响之后正常启动的 Grok，当前任务保持运行。连接前已有的请求回原终端。")
                .font(MonitorDesktopTypography.metadata)
                .foregroundStyle(MonitorDesktopTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
        }
    }

    private var quotaCard: some View {
        let displayNow = GrokDisplayClock.now(sampled: now)
        let quota = runtime.quota
        let available = quota?.isAvailable(at: displayNow) == true
        let stale = quota.map { runtime.quotaFailed || $0.isStale(at: displayNow) } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            MonitorCardHeader(symbol: "gauge.with.dots.needle.67percent", title: "真实剩余额度") {
                if runtime.refreshing && !available {
                    MonitorMetaChip("正在查询", tint: MonitorDesktopTheme.accent)
                } else if let plan = quota?.plan, available {
                    MonitorMetaChip(plan)
                }
            }
            if let quota, available {
                MonitorHeroMetric(label: quota.title, value: "\(quota.remainingPercent)", unit: "%")
                    .opacity(stale ? 0.55 : 1)
                    .accessibilityLabel((stale ? "上次观测，非当前。" : "") + "剩余 \(quota.remainingPercent)%")
                quotaTrack(remaining: 100 - quota.usedPercent, stale: stale)
                VStack(alignment: .leading, spacing: 6) {
                    if let reset = quota.resetsAt {
                        Text("重置于 " + reset.formatted(date: .abbreviated, time: .shortened))
                    }
                    if quota.sharedPool == true { Text("统一共享额度池，包含其他产品的使用") }
                    if let cents = quota.prepaidCents {
                        Text(String(format: "预付余额 $%.2f", Double(cents) / 100))
                    }
                    Text((stale ? "上次观测，非当前 · " : "观测于 ") + quota.capturedAt.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(MonitorDesktopTheme.tertiaryText)
                }
                .font(MonitorDesktopTypography.metadata)
                .foregroundStyle(MonitorDesktopTheme.secondaryText)
                if runtime.quotaFailed {
                    Text(runtime.quotaStatus)
                        .font(MonitorDesktopTypography.metadata)
                        .foregroundStyle(MonitorDesktopTheme.caution)
                }
            } else {
                HStack(spacing: 9) {
                    if runtime.refreshing { ProgressView().controlSize(.small).tint(MonitorDesktopTheme.accent) }
                    Text(unavailableQuotaText(at: displayNow))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(MonitorDesktopTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 64, alignment: .leading)
            }
        }
        .modifier(MonitorCenterCard(prominent: true))
    }

    private func unavailableQuotaText(at displayNow: Date) -> String {
        guard runtime.quotaStatus == "官方额度已同步" else { return runtime.quotaStatus }
        return runtime.quota?.resetsAt.map { $0 <= displayNow } == true
            ? "额度周期已结束，等待重新查询" : "额度暂不可用，等待重新查询"
    }

    private func quotaTrack(remaining: Double, stale: Bool) -> some View {
        Group {
            if stale {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MonitorDesktopTheme.track)
                        Capsule().fill(MonitorDesktopTheme.secondaryText)
                            .frame(width: proxy.size.width * CGFloat(max(0, min(100, remaining))) / 100)
                    }
                }
                .frame(height: 4)
            } else {
                ProgressView(value: max(0, min(100, remaining)), total: 100)
                    .tint(MonitorDesktopTheme.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余额度")
        .accessibilityValue("\(Int(remaining.rounded()))%")
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitorCardHeader(symbol: "chart.bar", title: "本机用量与成本") {
                HStack(spacing: 8) {
                    if runtime.usage?.complete == false { MonitorMetaChip("部分记录", tint: MonitorDesktopTheme.caution) }
                    PanelSettingsSegments(options: ["7 天", "30 天", "90 天"], selection: Binding(
                        get: { "\(days) 天" },
                        set: { if let value = Int($0.split(separator: " ").first ?? "") { days = value } }
                    ), width: 200, title: "Grok 统计周期")
                }
            }
            HStack(alignment: .center, spacing: 20) {
                MonitorHeroMetric(label: "\(days) 日", value: tokenValue, unit: runtime.usage == nil ? "" : "tokens")
                Spacer(minLength: 0)
                MonitorStatPair(value: costText, label: "CLI 报告成本")
                Rectangle().fill(MonitorDesktopTheme.hairline).frame(width: 0.5, height: 32).accessibilityHidden(true)
                MonitorStatPair(value: runtime.usage.map { String($0.sessionCount) } ?? "—", label: "会话")
            }
            .padding(.vertical, 4)
            if history.isEmpty {
                MonitorCenterEmptyState(
                    symbol: "chart.bar",
                    title: runtime.usage == nil ? "正在读取本机会话" : "此周期暂无已记录用量",
                    detail: runtime.usage == nil ? "" : "所选周期内没有已记录的轮次。",
                    isLoading: runtime.usage == nil
                )
            } else {
                usageChart
                    .frame(height: 140)
                    .modifier(MonitorChartInset())
                    .animation(reduceMotion ? nil : MonitorDesktopTheme.pageMotion, value: days)
                DisclosureGroup("每日明细") {
                    ForEach(history.reversed(), id: \.date) { day in
                        HStack {
                            Text(Self.dayLabel(day.date))
                            Spacer(minLength: 8)
                            Text(tokenCount(day.tokens) + " Token").monospacedDigit()
                            Text(day.cost.map { String(format: "$%.4f", $0) } ?? "金额未知")
                                .foregroundStyle(day.cost == nil ? MonitorDesktopTheme.tertiaryText : MonitorDesktopTheme.secondaryText)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .font(MonitorDesktopTypography.metadata)
                        .foregroundStyle(MonitorDesktopTheme.secondaryText)
                        .padding(.vertical, 3)
                    }
                }
                .font(MonitorDesktopTypography.metadataMedium)
                .foregroundStyle(MonitorDesktopTheme.secondaryText)
            }
            Label(usageCaption, systemImage: "info.circle")
                .font(MonitorDesktopTypography.metadata)
                .foregroundStyle(MonitorDesktopTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(MonitorCenterCard())
    }

    private var usageChart: some View {
        let width: CGFloat = days <= 7 ? 22 : days <= 30 ? 8 : 4
        let stride = days <= 7 ? 1 : days <= 30 ? 5 : 15
        return Chart(history, id: \.date) { day in
            BarMark(x: .value("日期", day.date, unit: .day), y: .value("Token", day.tokens), width: .fixed(width))
                .foregroundStyle(MonitorDesktopTheme.usageData)
                .cornerRadius(3)
                .accessibilityLabel(Self.dayLabel(day.date))
                .accessibilityValue(tokenCount(day.tokens) + " Token")
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(MonitorDesktopTheme.chartGrid)
                AxisValueLabel {
                    if let number = value.as(Int.self) {
                        Text(tokenCount(number)).font(MonitorDesktopTypography.metadata)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: stride)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(Self.dayLabel(date)).font(MonitorDesktopTypography.metadata)
                    }
                }
            }
        }
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorCardHeader(symbol: "bolt.horizontal.circle", title: "实时任务") {
                if !runtime.rows.isEmpty { MonitorMetaChip(ActivitySessionSnapshot.statusSummary(runtime.rows)) }
            }
            if runtime.rows.isEmpty {
                MonitorCenterEmptyState(
                    symbol: "bolt.horizontal.circle",
                    title: "当前没有已确认的活动任务",
                    detail: "共享模式支持岛内选项、文字回答及工具允许一次／拒绝；其他交互回 Grok 原终端。"
                )
            } else {
                ForEach(Array(runtime.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(MonitorDesktopTheme.hairline).frame(height: 0.5).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.projectName).font(MonitorDesktopTypography.rowTitle).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(row.statusTitle)
                                .font(MonitorDesktopTypography.metadataMedium)
                                .foregroundStyle(statusColor(row))
                        }
                        Text(row.title)
                            .font(MonitorDesktopTypography.metadata)
                            .foregroundStyle(MonitorDesktopTheme.secondaryText)
                            .lineLimit(1)
                        if !row.actionText.isEmpty && row.actionText != row.title {
                            Text(row.actionText)
                                .font(MonitorDesktopTypography.metadata)
                                .foregroundStyle(MonitorDesktopTheme.secondaryText)
                                .lineLimit(2)
                        }
                        ForEach(row.recentSteps) { step in
                            Text("\(step.state.title) · \(step.title)")
                                .font(MonitorDesktopTypography.metadata)
                                .foregroundStyle(MonitorDesktopTheme.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Text("共享模式支持岛内选项、文字回答及工具允许一次／拒绝；其他交互回 Grok 原终端。")
                    .font(MonitorDesktopTypography.metadata)
                    .foregroundStyle(MonitorDesktopTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .modifier(MonitorCenterCard())
    }

    private var tokenValue: String {
        guard runtime.usage != nil else { return "—" }
        return tokenCount(tokenTotal)
    }

    private func tokenCount(_ value: Int) -> String {
        _ = countStyle
        return MenuBarTokenFormatter.shortCount(value)
    }

    private func statusColor(_ row: ActivitySessionSnapshot) -> Color {
        switch row.phase {
        case .waitingApproval: return MonitorDesktopTheme.accent
        case .failed: return MonitorDesktopTheme.caution
        case .completed: return MonitorDesktopTheme.positive
        default: return MonitorDesktopTheme.secondaryText
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private static func dayLabel(_ date: Date) -> String { dayFormatter.string(from: date) }
}

struct GrokQuotaView: View {
    @ObservedObject var runtime: GrokRuntime
    let now: Date
    var body: some View {
        let displayNow = GrokDisplayClock.now(sampled: now)
        VStack(alignment: .leading, spacing: 8) {
            if let quota = runtime.quota, quota.isAvailable(at: displayNow) {
                let old = runtime.quotaFailed || quota.isStale(at: displayNow)
                HStack { Text(quota.title); Spacer(); Text(quota.plan ?? "Grok CLI").foregroundStyle(.secondary) }.font(.system(size: 11))
                Text("\(quota.remainingPercent)%").font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                    .opacity(old ? 0.55 : 1)
                    .accessibilityLabel((old ? "上次观测，非当前。" : "") + "剩余 \(quota.remainingPercent)%")
                ProgressView(value: 100 - quota.usedPercent, total: 100).tint(old ? .gray : FloatingSurfaceTheme.accent())
                    .accessibilityLabel("剩余额度")
                if let reset = quota.resetsAt { Text("重置于 " + reset.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)) }
                if quota.sharedPool == true { Text("统一共享额度池，包含其他产品的使用").font(.system(size: 11)).foregroundStyle(.secondary) }
                if let cents = quota.prepaidCents { Text(String(format: "预付余额 $%.2f", Double(cents) / 100)).font(.system(size: 11)).foregroundStyle(.secondary) }
                Text((old ? "上次观测，非当前 · " : "观测于 ") + quota.capturedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 42, weight: .semibold, design: .rounded))
                Text(runtime.quotaStatus == "官方额度已同步"
                    ? (runtime.quota?.resetsAt.map { $0 <= displayNow } == true ? "额度周期已结束，等待重新查询" : "额度暂不可用，等待重新查询") : runtime.quotaStatus)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if runtime.quotaFailed && runtime.quota != nil { Text(runtime.quotaStatus).font(.system(size: 11)).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GrokGlanceContent: View {
    @ObservedObject var runtime: GrokRuntime
    let now: Date
    let showQuota: Bool
    let showCost: Bool
    let showActivity: Bool
    let showDaily: Bool
    let showMonth: Bool
    @Binding var metric: String
    var body: some View {
        VStack(spacing: 12) {
            if showQuota { GrokQuotaView(runtime: runtime, now: now).weatherModule() }
            if showCost || showActivity {
                let cost = showCost && (!showActivity || metric != "token")
                let days = runtime.usage?.days ?? []
                GlanceWeatherStrip(buckets: GlanceDayStrip.buckets(samples: days.compactMap { day in
                    (cost ? day.cost : Double(day.tokens)).map { .init(date: day.date, value: $0) }
                }, now: now), isCost: cost, isReady: runtime.usage != nil, showsSelector: showCost && showActivity,
                    metric: $metric, color: FloatingSurfaceTheme.accent(), unknownModels: [], loadingText: "正在统计 Grok 用量…",
                    tokenSourceLabel: "本机 Grok 用量", unpricedDates: Set(days.filter { $0.cost == nil }.map(\.date)))
            }
            if showDaily || showMonth {
                let today = Calendar.current.startOfDay(for: now)
                let lower = Calendar.current.date(byAdding: .day, value: -29, to: today)!
                HStack {
                    if showDaily { smallMetric("今日 Token", runtime.usage?.days.first { $0.date == today }?.tokens ?? 0) }
                    if showMonth { smallMetric("30 日 Token", (runtime.usage?.days ?? []).filter { $0.date >= lower && $0.date <= today }.reduce(0) { GrokJSON.add($0, $1.tokens) }) }
                }.weatherModule()
            }
            Text("本机历史不代表当前账号账单" + (runtime.usage?.complete == false ? " · 部分记录" : ""))
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func smallMetric(_ title: String, _ tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(runtime.usage == nil ? "—" : GlanceDayStrip.tokenText(Double(tokens))).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
