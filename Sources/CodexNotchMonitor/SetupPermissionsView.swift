import AppKit
import SwiftUI

struct SetupPermissionsView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onboardingStep = 0
    @State private var showsConnectionInfo = false
    @State private var testNotificationSending = false
    @State private var testNotificationFeedback: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    statusOverview
                    Text("通知与任务状态连接均可按需开启。")
                        .font(.system(size: 11)).foregroundStyle(MonitorDesktopTheme.faintText)
                }.modifier(MonitorDesktopReveal(delay: 0))
                if !store.isSetupOnboardingComplete { onboarding.modifier(MonitorDesktopReveal(delay: 0.04)) }
                PanelSettingsGroup(title: "权限与连接", symbol: "checkmark.shield") {
                    SettingsRow(symbol: "point.3.connected.trianglepath.dotted", title: "原生任务监控", detail: "通过桌面 IPC 与本地日志自动观察任务；批准和回答请在 Codex 中操作。") {
                        HStack(spacing: 6) {
                            Text(store.nativeActivityStatus)
                                .foregroundStyle(PanelSettingsTheme.secondary).monospacedDigit()
                            Button { showsConnectionInfo.toggle() } label: { Image(systemName: "info.circle") }
                                .buttonStyle(PanelSettingsActionStyle())
                                .accessibilityLabel("连接诊断").help("查看 CLI 路径与连接说明")
                                .popover(isPresented: $showsConnectionInfo) { connectionInfo }
                            Button { refreshStatus() } label: { Label("刷新状态", systemImage: "arrow.clockwise") }
                                .buttonStyle(PanelSettingsActionStyle())
                        }
                    }
                    SettingsRowDivider()
                    SettingsRow(symbol: "bell.badge", title: "通知", detail: "额度恢复、重置确认与需要处理的任务提醒。") {
                        HStack(spacing: 12) {
                            Label(notificationTitle, systemImage: store.quotaNotificationStatus == .enabled ? "checkmark.circle.fill" : "bell.slash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(store.quotaNotificationStatus == .enabled ? MonitorDesktopTheme.positive : MonitorDesktopTheme.caution)
                            if store.quotaNotificationStatus == .enabled {
                                Button(testNotificationFeedback ?? "发送测试通知") {
                                    testNotificationSending = true
                                    store.sendTestNotification { sent in
                                        testNotificationSending = false
                                        testNotificationFeedback = sent ? "已发送" : "发送失败"
                                    }
                                }
                                .disabled(testNotificationSending || testNotificationFeedback != nil)
                                .buttonStyle(PanelSettingsActionStyle())
                                .task(id: testNotificationFeedback) {
                                    guard testNotificationFeedback != nil else { return }
                                    do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                                    catch { return }
                                    testNotificationFeedback = nil
                                }
                            } else if store.quotaNotificationStatus == .unknown {
                                Button("允许通知") { store.requestNotificationAuthorizationForSetup() }
                                    .buttonStyle(PanelSettingsActionStyle(prominent: true))
                            } else {
                                Button { store.openNotificationSettings() } label: { Label("打开通知设置", systemImage: "arrow.up.right") }
                                    .buttonStyle(PanelSettingsActionStyle())
                            }
                        }
                    }
                    SettingsRowDivider()
                    SettingsRow(symbol: "antenna.radiowaves.left.and.right", title: "关注信号提醒", detail: "新的待验证信号与重置预告。") {
                        Toggle("关注信号提醒", isOn: $store.notifyTiboSignals).labelsHidden().toggleStyle(.switch)
                    }
                    SettingsRowDivider()
                    SettingsRow(symbol: "arrow.counterclockwise", title: "额度恢复提醒", detail: "额度恢复立即提醒，原因确认后静音更新。") {
                        Toggle("额度恢复提醒", isOn: $store.notifyQuotaRecovery).labelsHidden().toggleStyle(.switch)
                    }
                }.modifier(MonitorDesktopReveal(delay: 0.08))
                PanelSettingsGroup(title: "应用更新", symbol: "arrow.triangle.2.circlepath") {
                    SettingsRow(symbol: "arrow.triangle.2.circlepath", title: "当前版本", detail: "v\(store.appUpdateStatus.currentVersion) · Build \(store.appUpdateStatus.currentBuild) · \(checkedText)") {
                        HStack(spacing: 12) {
                            Label(updateTitle, systemImage: store.appUpdateStatus.phase == .upToDate ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(store.appUpdateStatus.phase == .upToDate ? MonitorDesktopTheme.positive : store.appUpdateStatus.phase == .failed ? MonitorDesktopTheme.caution : PanelSettingsTheme.clay)
                                .font(.system(size: 11, weight: .medium))
                            if store.appUpdateStatus.phase == .updateAvailable {
                                Button { store.openAppUpdateDownload() } label: { Label("下载更新", systemImage: "arrow.up.right") }
                                    .buttonStyle(PanelSettingsActionStyle())
                            } else {
                                MonitorRefreshButton(title: "检查更新", loadingTitle: "检查中",
                                    isRefreshing: store.appUpdateStatus.phase == .checking) { store.checkForAppUpdate(force: true) }
                            }
                        }
                    }
                    if let message = store.appUpdateMessage {
                        Text(message).font(.system(size: 11))
                            .foregroundStyle(store.appUpdateStatus.phase == .failed ? MonitorDesktopTheme.caution : PanelSettingsTheme.secondary)
                            .textSelection(.enabled).padding(.bottom, 14)
                    }
                }.modifier(MonitorDesktopReveal(delay: 0.12))
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading).padding(4).padding(.bottom, 20)
        }
        .foregroundStyle(PanelSettingsTheme.primary)
        .tint(PanelSettingsTheme.clay)
        .onAppear { refreshStatus(); store.checkForAppUpdate(force: false) }
    }

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("连接诊断").font(MonitorDesktopTypography.cardTitle).foregroundStyle(PanelSettingsTheme.primary)
                Spacer(minLength: 8)
                Button { showsConnectionInfo = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(PanelSettingsActionStyle()).accessibilityLabel("关闭连接诊断")
            }
            Text(store.codexSetupSnapshot?.codexExecutableURL.map { "Codex CLI：" + $0.path } ?? "未找到 Codex CLI；请确认 Codex 已安装。")
                .textSelection(.enabled)
            Text("任务状态通过本机桌面 IPC 获取，断线时回退本地日志。批准、回答和消息仍在原客户端操作。")
            Text("可运行真实任务核对灵动岛状态；任务结束后保留额度／空闲横幅。")
        }
        .foregroundStyle(PanelSettingsTheme.secondary)
        .modifier(MonitorPopoverSurface()).frame(width: 320, alignment: .leading)
        .onExitCommand { showsConnectionInfo = false }
    }

    private var statusOverview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { statusCards }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 600)
            VStack(spacing: 12) { statusCards }
        }
    }

    @ViewBuilder private var statusCards: some View {
        statusCard(symbol: "waveform.path.ecg", title: "任务监控", value: store.nativeActivityStatus,
                   detail: store.nativeActivityConnectionDetail,
                   color: store.nativeActivityConnectionDetail == "等待连接" ? MonitorDesktopTheme.faintText : MonitorDesktopTheme.positive)
        statusCard(symbol: "bell", title: "通知", value: notificationTitle,
                   detail: SettingsSummaryText.notifications(signals: store.notifyTiboSignals, recovery: store.notifyQuotaRecovery),
                   color: store.quotaNotificationStatus == .enabled ? MonitorDesktopTheme.positive
                       : store.quotaNotificationStatus == .denied ? MonitorDesktopTheme.caution : MonitorDesktopTheme.faintText)
        statusCard(symbol: "shippingbox", title: "版本", value: "v\(store.appUpdateStatus.currentVersion)",
                   detail: updateTitle, color: updateStatusColor)
    }

    private var updateStatusColor: Color {
        switch store.appUpdateStatus.phase {
        case .upToDate: return MonitorDesktopTheme.positive
        case .failed, .updateAvailable: return MonitorDesktopTheme.caution
        default: return MonitorDesktopTheme.faintText
        }
    }

    private func statusCard(symbol: String, title: String, value: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsGlyph(symbol: symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
                HStack(spacing: 6) {
                    Capsule().fill(color).frame(width: 8, height: 6).accessibilityHidden(true)
                    Text(value).font(MonitorDesktopTypography.rowTitle)
                        .lineLimit(1).truncationMode(.tail).help(value)
                }
                Text(detail).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.secondaryText)
                    .lineLimit(1).truncationMode(.tail).help(detail)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 90, maxHeight: .infinity, alignment: .topLeading)
        .modifier(MonitorDesktopCardSurface(cornerRadius: 14))
    }

    private var onboarding: some View {
        let titles = ["欢迎使用", "环境检查", "通知与完成"]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MonitorDesktopTheme.accent).frame(width: 40, height: 40)
                    .background(MonitorDesktopTheme.glyphFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(titles[onboardingStep]).font(MonitorDesktopTypography.cardTitle).accessibilityAddTraits(.isHeader)
                    Text(onboardingStep == 0 ? "监控当前账号额度、本机用量与任务状态。会话与用量在本机处理。" : onboardingStep == 1
                         ? "请安装并运行 Codex。桌面连接和本地日志会自动提供任务状态。"
                         : "通知可按需开启，也可以稍后在此页面设置。")
                        .font(.system(size: 13)).foregroundStyle(PanelSettingsTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { step in
                        Capsule().fill(step == onboardingStep ? MonitorDesktopTheme.accent : MonitorDesktopTheme.primaryText.opacity(0.18))
                            .frame(width: step == onboardingStep ? 18 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
                .animation(reduceMotion ? nil : MonitorDesktopTheme.selectionMotion, value: onboardingStep)
                Spacer()
                if onboardingStep > 0 { Button("上一步") { onboardingStep -= 1 }.buttonStyle(PanelSettingsActionStyle()) }
                Button(onboardingStep == 2 ? "完成设置" : "下一步") {
                    if onboardingStep == 2 { store.completeSetupOnboarding() } else { onboardingStep += 1 }
                }.buttonStyle(PanelSettingsActionStyle(prominent: true))
            }
        }.padding(14).modifier(SettingsStageSurface())
    }
    private var notificationTitle: String {
        switch store.quotaNotificationStatus {
        case .enabled: return "已允许"
        case .denied: return "已关闭"
        case .unknown: return "尚未确认"
        }
    }
    private var updateTitle: String {
        switch store.appUpdateStatus.phase {
        case .idle: return "尚未检查"
        case .checking: return "正在检查"
        case .upToDate: return "已是最新"
        case .updateAvailable: return "新版本可用"
        case .developmentBuild: return "开发版本"
        case .failed: return "检查失败"
        }
    }
    private var checkedText: String {
        store.appUpdateStatus.checkedAt.map { "上次检查：" + $0.compactRelativeText } ?? "尚未检查"
    }
    private func refreshStatus() {
        store.refreshCodexSetup()
        store.refreshNotificationStatus()
        store.refreshSessionActivity()
    }
}
