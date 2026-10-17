import AppKit
import SwiftUI

struct SetupPermissionsView: View {
    @ObservedObject var store: MonitorStore
    @State private var onboardingStep = 0
    @State private var showsConnectionInfo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !store.isSetupOnboardingComplete { onboarding }
                Text("通知与任务状态连接均可按需开启。")
                    .font(.system(size: 12)).foregroundStyle(PanelSettingsTheme.secondary)
                PanelSettingsGroup(title: "权限与连接", symbol: "checkmark.shield") {
                    row("原生任务监控", detail: "通过桌面 IPC 与本地日志自动观察任务；批准和回答请在 Codex 中操作。") {
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
                    PanelSettingsTheme.divider
                    row("通知", detail: "额度恢复、重置确认与需要处理的任务提醒。") {
                        HStack(spacing: 12) {
                            Label(notificationTitle, systemImage: store.quotaNotificationStatus == .enabled ? "checkmark.circle.fill" : "bell.slash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(store.quotaNotificationStatus == .enabled ? PanelSettingsTheme.clay : .orange)
                            if store.quotaNotificationStatus == .unknown {
                                Button("允许通知") { store.requestNotificationAuthorizationForSetup() }
                                    .buttonStyle(PanelSettingsActionStyle(prominent: true))
                            } else {
                                Button { store.openNotificationSettings() } label: { Label("打开通知设置", systemImage: "arrow.up.right") }
                                    .buttonStyle(PanelSettingsActionStyle())
                            }
                        }
                    }
                }
                PanelSettingsGroup(title: "应用更新", symbol: "arrow.triangle.2.circlepath") {
                    row("当前版本", detail: "v\(store.appUpdateStatus.currentVersion) · Build \(store.appUpdateStatus.currentBuild) · \(checkedText)") {
                        HStack(spacing: 12) {
                            Label(updateTitle, systemImage: store.appUpdateStatus.phase == .upToDate ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(store.appUpdateStatus.phase == .failed ? .orange : PanelSettingsTheme.clay)
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
                            .foregroundStyle(store.appUpdateStatus.phase == .failed ? .orange : PanelSettingsTheme.secondary)
                            .textSelection(.enabled).padding(.bottom, 14)
                    }
                }
            }
            .frame(maxWidth: 840).frame(maxWidth: .infinity, alignment: .leading).padding(16).padding(.bottom, 20)
        }
        .foregroundStyle(PanelSettingsTheme.primary)
        .tint(PanelSettingsTheme.clay)
        .background(PanelSettingsTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
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

    private var onboarding: some View {
        let titles = ["欢迎使用", "环境检查", "通知与完成"]
        return PanelSettingsGroup(title: titles[onboardingStep], symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Text(onboardingStep == 0 ? "监控当前账号额度、本机用量与任务状态。会话与用量在本机处理。" : onboardingStep == 1
                     ? "请安装并运行 Codex。桌面连接和本地日志会自动提供任务状态。"
                     : "通知可按需开启，也可以稍后在此页面设置。")
                    .font(.system(size: 13)).foregroundStyle(PanelSettingsTheme.secondary)
                HStack {
                    if onboardingStep > 0 { Button("上一步") { onboardingStep -= 1 }.buttonStyle(PanelSettingsActionStyle()) }
                    Spacer()
                    Button(onboardingStep == 2 ? "完成设置" : "下一步") {
                        if onboardingStep == 2 { store.completeSetupOnboarding() } else { onboardingStep += 1 }
                    }.buttonStyle(PanelSettingsActionStyle(prominent: true))
                }
            }.padding(.vertical, 16)
        }
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
    private func row<Actions: View>(_ title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                label(title, detail: detail).frame(maxWidth: .infinity, alignment: .leading)
                actions().fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) { label(title, detail: detail); actions() }
        }.font(.system(size: 12, weight: .medium)).padding(.vertical, 16)
    }
    private func label(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
