import SwiftUI
import Charts

struct ClaudeCodeView: View {
    @AppStorage(CountStyle.preferenceKey) private var countStyle = CountStyle.chinese.rawValue
    @ObservedObject var runtime: ClaudeCodeRuntime
    @State private var days = 30
    @State private var now = Date()
    private var history: [ClaudeCodeUsageSummary.Day] {
        let today = ClaudeCodeUsageScanner.localDay(Date())
        let lower = today.addingTimeInterval(-Double(days - 1) * 86_400)
        return (runtime.usage?.days ?? []).filter { $0.date >= lower && $0.date <= today }
    }
    private var totalTokens: Int64 { history.reduce(0) { $0 + $1.tokens } }
    private var cost: Double? {
        guard runtime.usage != nil, history.allSatisfy({ $0.estimatedCost != nil }) else { return nil }
        return history.reduce(0) { $0 + ($1.estimatedCost ?? 0) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PanelSettingsGroup(title: "Claude Code 连接", symbol: "point.3.connected.trianglepath.dotted") {
                    SettingsRow(symbol: "terminal", title: "任务与用量", detail: runtime.status) {
                        Toggle("启用 Claude Code", isOn: Binding(get: { runtime.enabled }, set: {
                            runtime.configure(enabled: $0, approvals: runtime.approvalsEnabled, statusLine: runtime.statusLineEnabled)
                        })).labelsHidden().disabled(runtime.configuring)
                    }
                    SettingsRowDivider()
                    SettingsRow(symbol: "checkmark.shield", title: "在 Pulse 中处理请求", detail: "显示真实权限请求与单选问题；未处理或断线时交回原客户端。") {
                        Toggle("在 Pulse 中处理请求", isOn: Binding(get: { runtime.approvalsEnabled }, set: {
                            runtime.configure(enabled: true, approvals: $0, statusLine: runtime.statusLineEnabled)
                        })).labelsHidden().disabled(!runtime.enabled || runtime.configuring)
                    }
                    SettingsRowDivider()
                    SettingsRow(symbol: "gauge.with.dots.needle.50percent", title: "官方额度窗口", detail: "通过 Claude 状态栏采集，继续转发原状态栏输出。") {
                        Toggle("采集官方额度", isOn: Binding(get: { runtime.statusLineEnabled }, set: {
                            runtime.configure(enabled: true, approvals: runtime.approvalsEnabled, statusLine: $0)
                        })).labelsHidden().disabled(!runtime.enabled || runtime.configuring)
                    }
                    Text("启用时备份 settings.json，仅管理 Pulse 的 Claude 条目；停用恢复原状态栏。已有会话可能需要重新启动。")
                        .font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
                        .padding(.bottom, 12)
                    if let error = runtime.error {
                        HStack {
                            Text(error).foregroundStyle(MonitorDesktopTheme.caution)
                            Button("重试") { runtime.retry() }
                        }.padding(.bottom, 12)
                    }
                }
                if runtime.enabled {
                    if !runtime.requests.isEmpty {
                        HStack {
                            Label("\(runtime.requests.count) 条待处理请求", systemImage: "hand.raised")
                            Spacer()
                            Button("查看请求") { runtime.showRequests() }.buttonStyle(PanelSettingsActionStyle(prominent: true))
                        }.padding(16).modifier(MonitorDesktopCardSurface())
                    }
                    quota
                    usage
                    if !runtime.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Claude Code 任务").font(MonitorDesktopTypography.cardTitle)
                            ForEach(runtime.rows) { row in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.title).lineLimit(1)
                                        Text(row.actionText).font(MonitorDesktopTypography.metadata)
                                            .foregroundStyle(MonitorDesktopTheme.secondaryText).lineLimit(2)
                                    }
                                    Spacer()
                                    Text(row.statusTitle).font(MonitorDesktopTypography.metadata)
                                    if row.phase == .waitingApproval {
                                        Button("查看") { runtime.showRequests(for: row.id) }
                                    }
                                }
                            }
                        }.padding(18).modifier(MonitorDesktopCardSurface())
                    }
                }
            }.padding(4).padding(.bottom, 20)
        }.toggleStyle(PanelSettingsToggleStyle()).tint(MonitorDesktopTheme.accent)
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
    private var quota: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude 官方额度").font(MonitorDesktopTypography.cardTitle)
                Spacer()
                Text(runtime.limits.map { "采集于 " + $0.capturedAt.formatted(date: .omitted, time: .shortened) } ?? "等待状态栏数据")
                    .font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
            }
            HStack(spacing: 24) {
                quotaWindow("5 小时", window: runtime.limits?.fiveHour)
                quotaWindow("每周", window: runtime.limits?.sevenDay)
            }
            if runtime.limits == nil {
                Text(runtime.statusLineEnabled ? "订阅窗口需 Claude Code 首次 API 响应后提供；API 账号或不支持的窗口显示为未知。" : "尚未开启状态栏采集。")
                    .font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
            }
        }.padding(18).modifier(MonitorDesktopCardSurface())
    }
    private func quotaWindow(_ title: String, window: ClaudeCodeRateLimits.Window?) -> some View {
        let quota = IslandUsagePresentation.claudeQuota(title: title, window: window,
            capturedAt: runtime.limits?.capturedAt, statusLineEnabled: runtime.statusLineEnabled, now: now)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(MonitorDesktopTypography.metadata)
                Spacer()
                if let label = quota.freshness.observationLabel(now: now) {
                    Text(label).font(MonitorDesktopTypography.metadata)
                }
            }
            Text(quota.remainingPercent.map { "\($0)% 剩余" } ?? "—")
                .font(.system(size: 24, weight: .semibold)).monospacedDigit()
            if let remaining = quota.remainingPercent {
                if quota.freshness.isStale {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(FloatingSurfaceTheme.track())
                            Capsule().fill(MonitorDesktopTheme.secondaryText).frame(width: proxy.size.width * CGFloat(remaining) / 100)
                        }
                    }.frame(height: 4).accessibilityHidden(true)
                } else { ProgressView(value: Double(remaining), total: 100) }
                Text(quota.resetsAt.map { "重置于 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "重置时间未知")
                    .font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .opacity(quota.freshness.isStale ? 0.55 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityValue(quota.freshness.isStale ? "上次观测，非当前" : "")
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("本机 Claude 用量").font(MonitorDesktopTypography.cardTitle)
                Spacer()
                PanelSettingsSegments(options: ["7 天", "30 天", "90 天"], selection: Binding(
                    get: { "\(days) 天" }, set: { if let value = Int($0.split(separator: " ")[0]) { days = value } }
                ), width: 200, title: "Claude 统计周期")
                MonitorRefreshButton(title: "刷新", loadingTitle: "扫描中", isRefreshing: runtime.scanning) {
                    runtime.refreshUsage()
                }.accessibilityLabel("刷新 Claude 用量")
            }
            HStack(alignment: .firstTextBaseline, spacing: 32) {
                metric("Token（含缓存）", runtime.usage == nil ? "—" : MenuBarTokenFormatter.shortCount(Int(totalTokens)))
                metric("API 等价估算", cost.map { String(format: "$%.2f", $0) } ?? "—")
            }
            if runtime.scanning || runtime.usage?.complete == false {
                Text("正在增量扫描，统计尚未完整").font(MonitorDesktopTypography.metadata)
            }
            if let usage = runtime.usage, usage.fileCount == 0 {
                Text("未发现 Claude Code 会话记录。运行一次 Claude Code 后刷新。")
            } else if !history.isEmpty {
                Chart(history, id: \.date) { day in
                    BarMark(x: .value("日期", dayLabel(day.date)), y: .value("Token", day.tokens), width: .fixed(24))
                        .foregroundStyle(MonitorDesktopTheme.accent).cornerRadius(3)
                        .accessibilityLabel(dayLabel(day.date))
                        .accessibilityValue("\(CountFormatter.display(day.tokens)) Token")
                }.frame(height: 150)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let number = value.as(Int.self) { Text(MenuBarTokenFormatter.shortCount(number)) }
                            }
                        }
                    }
                DisclosureGroup("每日明细") {
                    ForEach(history.reversed(), id: \.date) { day in
                        HStack {
                            Text(dayLabel(day.date))
                            Spacer(); Text("\(CountFormatter.display(day.tokens)) Token").monospacedDigit()
                            Text(day.estimatedCost.map { String(format: "$%.2f", $0) } ?? "价格未知").frame(width: 110, alignment: .trailing)
                        }.font(MonitorDesktopTypography.metadata).padding(.vertical, 3)
                    }
                }
            }
            Text("本机全部 Claude 记录，含子 Agent；按消息去重，未推断账号归属。公开标准单价估算，非订阅账单；未知模型或无法确认的计价条件保留未知。费率核对：2026-10-21。")
                .font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
        }.padding(18).modifier(MonitorDesktopCardSurface())
    }
    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd"; return formatter.string(from: date)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
        }
    }
}

struct ClaudeRequestsView: View {
    @ObservedObject var runtime: ClaudeCodeRuntime
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Claude Code 请求").font(.title2.bold())
                if runtime.requests.isEmpty { Text("当前没有可处理的请求；已结束或转回终端的请求不会再次提交。") }
                ForEach(runtime.requests) { request in
                    ClaudeRequestCard(runtime: runtime, request: request)
                }
            }.padding(24)
        }.frame(minWidth: 480, minHeight: 320)
    }
}
private struct ClaudeRequestCard: View {
    @ObservedObject var runtime: ClaudeCodeRuntime
    let request: ClaudePermissionRequest
    @State private var answers: [String: String] = [:]
    @State private var confirmAlways = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.tool).font(.headline)
            Text(request.cwd).font(.caption).textSelection(.enabled)
            Text(request.detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            ForEach(request.questions) { question in
                Text(question.text).font(.headline)
                ForEach(question.options, id: \.self) { option in
                    Button { answers[question.text] = option } label: {
                        Label(option, systemImage: answers[question.text] == option ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(.plain)
                }
                TextField("自定义回答", text: Binding(get: { answers[question.text] ?? "" }, set: { answers[question.text] = $0 }))
            }
            if !request.suggestions.isEmpty && request.questions.isEmpty {
                DisclosureGroup("建议的授权规则") {
                    Text(String(decoding: (try? JSONSerialization.data(withJSONObject: request.suggestions, options: [.prettyPrinted, .sortedKeys])) ?? Data(), as: UTF8.self))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
            ViewThatFits {
                HStack { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
        }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .confirmationDialog("始终允许此请求建议的规则？", isPresented: $confirmAlways) {
                Button("写入 Claude 用户授权规则") { runtime.respond(request.id, choice: .always) }
            } message: { Text("Claude Code 会将上方展示的规则写入用户设置，对后续会话生效。") }
    }
    @ViewBuilder private var actions: some View {
        Button(request.questions.isEmpty ? "允许一次" : "提交回答") { runtime.respond(request.id, choice: .once, answers: answers) }
            .disabled(!request.questions.allSatisfy { !(answers[$0.text] ?? "").isEmpty })
        if !request.suggestions.isEmpty && request.questions.isEmpty {
            Button("本会话允许") { runtime.respond(request.id, choice: .session) }
            Button("始终允许") { confirmAlways = true }
        }
        Button("拒绝") { runtime.respond(request.id, choice: .deny) }
        Button("取消任务") { runtime.respond(request.id, choice: .cancel) }
        Button("回终端处理") { runtime.returnToTerminal(request.id) }
    }
}
