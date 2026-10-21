// Layout and chart interaction adapted from QuotaView f779531 IslandUsageBento (MIT).
// Copyright (c) 2026 Duoasa. Data comes from Codex Monitor's existing services.
import SwiftUI

struct ActivityIslandUsageDashboard: View {
    @ObservedObject var model: ActivityIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsReset = false
    @State private var flightActive = false
    @State private var flightSerial: UInt64 = 0
    @State private var usageHeight: CGFloat = 500
    @State private var resetHeight: CGFloat = 500
    @State private var now = Date()
    @State private var mode = IslandDashboardHeatmap.Mode.daily
    @State private var selectedCost: Date?
    @State private var selectedActivity: String?
    @State private var hoveredCost: Date?
    @State private var hoveredActivity: Int?
    private var presentation: IslandUsagePresentation {
        switch model.usageProvider {
        case .codex: return .codex(quotaState: model.quotaState, accountUsage: model.accountUsage,
            usageCost: model.usageCost, resetCredits: model.resetCredits, now: now)
        case .claude: return .claude(usage: model.claudeUsage, limits: model.claudeLimits,
            statusLineEnabled: model.claudeStatusLineEnabled, now: now)
        }
    }
    private var width: CGFloat { model.metrics.expandedRect.width }
    private var secondary: Color { FloatingSurfaceTheme.secondary() }
    private func utility(_ icon: String, title: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            IslandChromeIcon(name: icon)
        }.buttonStyle(FloatingSurfaceButtonStyle(circularFocus: true)).accessibilityLabel(title)
    }
    var body: some View {
        let p = presentation
        return VStack(spacing: 0) {
            header
            pageFlow(p)

        }
        .foregroundStyle(FloatingSurfaceTheme.primary()).frame(width: width, height: model.metrics.expandedRect.height, alignment: .top)
        .animation(reduceMotion ? nil : FloatingSurfaceTheme.selectionMotion, value: mode)
        .accessibilityElement(children: .contain).accessibilityLabel(showsReset ? "额度重置面板" : "用量统计面板")
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: model.usageProvider) { _ in
            now = Date(); selectedCost = nil; selectedActivity = nil; hoveredCost = nil; hoveredActivity = nil
            flightSerial &+= 1; flightActive = false; showsReset = false; model.resetDetailVisible = false
            model.onUsageHeightChange?(usageHeight + 36)
        }
        .onChange(of: model.privacyMode) { _ in flightActive = false }
        .onDisappear { flightActive = false; model.resetDetailVisible = false }
    }
    // The hardware notch may cover the header center; keep provider controls in content.
    private var header: some View {
            HStack(spacing: 8) {
                Button { if showsReset { navigateReset(false) } else { model.onBackToTasks?() } } label: {
                    Label(showsReset ? "返回用量" : "返回任务", systemImage: "chevron.left").font(FloatingSurfaceTypography.control)
                        .padding(.horizontal, 9).frame(height: 24).islandGlass(Capsule(), tint: FloatingSurfaceTheme.chipFill())
                }.buttonStyle(FloatingSurfaceButtonStyle())
                Text(showsReset ? "额度重置" : "用量统计").font(FloatingSurfaceTypography.control).foregroundStyle(secondary)
                Spacer()
                utility(model.isPinned ? "pin.fill" : "pin", title: model.isPinned ? "取消置顶" : "固定展开", action: model.onPin)
                utility("chevron.up", title: "收起用量面板", action: model.onCollapse)
            }.padding(.horizontal, 28).frame(height: 36)
    }
    private func usagePage(_ p: IslandUsagePresentation) -> some View {
            DashboardPageLayout(maximumHeight: model.metrics.maximumUsageHeight - 36,
                onHeightChange: { usageHeight = $0; if !showsReset { model.onUsageHeightChange?($0 + 36) } }) {
                VStack(spacing: 10) {
                    if model.privacyMode {
                        Text("隐私模式已开启").font(.system(size: 14, weight: .medium))
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .islandGlass(RoundedRectangle(cornerRadius: 14), tint: Color(white: 0.025).opacity(0.90), solidTint: Color(white: 0.025))
                    } else {
                        // Reset navigation hides this whole page without moving its ticket anchor.
                        IslandUsageProviderSwitch(model: model)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let status = p.statusLine {
                            Text(status).font(FloatingSurfaceTypography.metadata).foregroundStyle(secondary)
                                .lineLimit(1).help(status).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(spacing: 10) {
                            IslandUsageQuotaRow(quotas: p.quotas, now: now)
                            IslandUsageSourceCard(source: p.source, playbackVisible: model.playbackVisible,
                                flightActive: flightActive, onReset: { if p.supportsReset { navigateReset(true) } })
                                .frame(width: min(204, max(168, (width - 56) * 0.327)))
                        }.fixedSize(horizontal: false, vertical: true)
                        IslandUsageMetricStrip(metrics: p.metrics)
                        IslandUsageTrendCard(presentation: p, width: width, now: now, mode: $mode,
                            selectedCost: $selectedCost, selectedActivity: $selectedActivity,
                            hoveredCost: $hoveredCost, hoveredActivity: $hoveredActivity)
                    }
                }.padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 8)
            } footer: {
            HStack {
                Text(model.privacyMode ? "隐私模式" : p.updatedAt.map { "更新于 " + $0.formatted(date: .omitted, time: .shortened) } ?? "等待数据")
                    .font(FloatingSurfaceTypography.caption)
                Spacer()
                utility("arrow.clockwise", title: "刷新额度与用量", action: model.onRefresh)
                utility("gearshape", title: "灵动岛设置", action: model.onOpenSettings)
            }.padding(.horizontal, 28).frame(height: 36)
            }
    }
    private func pageFlow(_ p: IslandUsagePresentation) -> some View {
        ZStack(alignment: .top) {
            usagePage(p).frame(width: width, height: usageHeight, alignment: .top)
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
}
