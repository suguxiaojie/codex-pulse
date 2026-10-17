// Layout adapted from QuotaView f779531 IslandResetPage (MIT), Copyright (c) 2026 Duoasa.
// The upstream demo action is replaced by the existing confirmed reset service.
import SwiftUI

struct IslandResetActionPolicy {
    static func canRequest(credits: QuotaResetCreditSummary?, quota: QuotaState, busy: Bool,
                           privacy: Bool, fingerprint: String?) -> Bool {
        guard !busy, !privacy, let fingerprint, !fingerprint.isEmpty,
              let credits, credits.availableCount > 0, case .loaded = quota,
              quota.buckets.contains(where: { $0.id == "codex" && !$0.windows.isEmpty }) else { return false }
        // A server summary may omit the individual cards; never choose a known expired card.
        return credits.credits.isEmpty || credits.nextRedeemableCredit(relativeTo: Date()) != nil
    }
}

struct IslandDashboardResetPage: View {
    @ObservedObject var model: ActivityIslandViewModel
    let hidesTicket: Bool
    let onHeightChange: (CGFloat) -> Void
    @State private var confirmsReset = false
    @State private var confirmedCredits: QuotaResetCreditSummary?
    @State private var confirmedAccount: String?
    private var credits: QuotaResetCreditSummary? { model.resetCredits }
    private var available: Bool {
        IslandResetActionPolicy.canRequest(credits: credits, quota: model.quotaState,
            busy: model.resetBusy, privacy: model.privacyMode, fingerprint: model.resetAccountFingerprint)
    }
    private var remaining: Int? {
        let windows = IslandFloatingQuotaPeriods.windows(model.quotaState)
        return (windows.first { $0.windowDurationMinutes == 10080 } ?? windows.first)?.remainingPercent
    }
    private var expiry: String {
        guard let credits else { return "有效期暂不可用" }
        guard let date = credits.nearestExpiration(relativeTo: Date()) else { return "接口未提供有效期" }
        return "最近到期：" + date.formatted(date: .abbreviated, time: .shortened)
    }
    private var actionTitle: String {
        if model.resetBusy { return "正在重置…" }
        if credits == nil { return "等待重置卡数据" }
        if credits?.availableCount == 0 { return "暂无可用重置次数" }
        if !available { return "请刷新账号与额度数据" }
        return "重置额度"
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        pageContent
            .blur(radius: confirmsReset && !reduceMotion ? 1.5 : 0)
            .allowsHitTesting(!confirmsReset)
            .overlay {
                if confirmsReset {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.45))
                            .onTapGesture { cancelConfirmation() }
                        confirmationCard
                            .frame(width: min(332, model.metrics.expandedRect.width - 88))
                            .shadow(color: .black.opacity(0.65), radius: 30, y: 10)
                    }.padding(.horizontal, 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.26), value: confirmsReset)
            .onChange(of: confirmsReset) { model.resetConfirmationPresented = $0 }
            .onDisappear { cancelConfirmation(); model.resetConfirmationPresented = false }
            .onChange(of: model.resetAccountFingerprint) { _ in cancelConfirmation() }
            .onChange(of: model.privacyMode) { _ in cancelConfirmation() }
    }
    private var pageContent: some View {
        DashboardPageLayout(maximumHeight: model.metrics.maximumUsageHeight - 36, onHeightChange: onHeightChange) {
            VStack(alignment: .leading, spacing: 18) {
                if model.privacyMode {
                    Text("隐私模式已开启").font(FloatingSurfaceTypography.cardTitle).padding(.vertical, 20)
                } else {
                    HStack(spacing: 18) {
                        DashboardResetTicket(playbackEnabled: model.playbackVisible && !hidesTicket,
                            size: CGSize(width: 112, height: 67))
                            .opacity(hidesTicket ? 0 : 1)
                            .anchorPreference(key: DashboardResetTicketAnchors.self, value: .bounds) { [.reset: $0] }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("可用重置次数").font(FloatingSurfaceTypography.caption).foregroundStyle(FloatingSurfaceTheme.secondary())
                            Text(credits.map { "\($0.availableCount) 次" } ?? "—").font(FloatingSurfaceTypography.resetMetric).monospacedDigit()
                            Text(expiry).font(FloatingSurfaceTypography.metadata).foregroundStyle(FloatingSurfaceTheme.secondary())
                        }
                        Spacer(minLength: 0)
                    }
                    Divider().overlay(FloatingSurfaceTheme.separator())
                    VStack(spacing: 9) {
                        HStack {
                            Text(IslandFloatingQuotaPeriods.current(model.quotaState) ? "当前可用额度" : "上次额度")
                                .foregroundStyle(FloatingSurfaceTheme.detail())
                            Spacer()
                            Text(remaining.map { "\($0)%" } ?? "—").monospacedDigit()
                        }.font(FloatingSurfaceTypography.control)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(FloatingSurfaceTheme.track())
                                Capsule().fill(FloatingSurfaceTheme.success).frame(width: proxy.size.width * CGFloat(remaining ?? 0) / 100)
                            }
                        }.frame(height: 5).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("关于这次重置").font(FloatingSurfaceTypography.captionMedium).foregroundStyle(FloatingSurfaceTheme.detail())
                        Text("使用 1 次重置机会，重置符合条件的 Codex 用量周期。完成后无法撤销。")
                            .font(FloatingSurfaceTypography.caption).foregroundStyle(FloatingSurfaceTheme.tertiary())
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("确认后才会使用次数").font(FloatingSurfaceTypography.metadata).foregroundStyle(FloatingSurfaceTheme.tertiary())
                        Spacer(minLength: 8)
                        Button {
                            guard available else { return }
                            confirmedCredits = credits; confirmedAccount = model.resetAccountFingerprint
                            confirmsReset = true
                        } label: {
                            HStack(spacing: 6) {
                                if model.resetBusy { ProgressView().controlSize(.small) }
                                Text(actionTitle).font(FloatingSurfaceTypography.action)
                            }.padding(.horizontal, 18).frame(height: 32)
                        }.buttonStyle(DashboardResetActionStyle(primary: false, destructive: true, emphasized: true)).disabled(!available)
                            .accessibilityLabel(actionTitle).accessibilityHint("打开二次确认，不立即消耗次数")
                    }
                    if let message = model.resetMessage {
                        Text(message).font(FloatingSurfaceTypography.caption).foregroundStyle(FloatingSurfaceTheme.detail())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(FloatingSurfaceTheme.outline(), lineWidth: 0.5).allowsHitTesting(false) }
            .padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 6)
        } footer: {
            HStack {
                Text(model.privacyMode ? "隐私模式" : "额度重置").font(FloatingSurfaceTypography.metadata).opacity(0.65)
                Spacer()
                Button { model.onRefresh?() } label: {
                    IslandChromeIcon(name: "arrow.clockwise")
                }.buttonStyle(FloatingSurfaceButtonStyle(circularFocus: true)).disabled(model.resetBusy).accessibilityLabel("刷新重置数据")
            }.padding(.horizontal, 28).frame(height: 32)
        }
        .foregroundStyle(FloatingSurfaceTheme.primary()).accessibilityElement(children: .contain).accessibilityLabel("额度重置详情")
    }
    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                DashboardResetTicket(playbackEnabled: false, size: CGSize(width: 44, height: 26.2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("使用一次重置").font(FloatingSurfaceTypography.title)
                    Text("Codex 额度").font(FloatingSurfaceTypography.label).foregroundStyle(FloatingSurfaceTheme.tertiary())
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("将重置符合条件的用量周期。确认后消耗 1 次机会，操作无法撤销。")
                    .font(FloatingSurfaceTypography.body).foregroundStyle(FloatingSurfaceTheme.secondary())
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text("剩余次数").font(FloatingSurfaceTypography.caption).foregroundStyle(FloatingSurfaceTheme.tertiary())
                    Spacer()
                    Text(confirmedCredits.map { "\($0.availableCount)" } ?? "—")
                        .foregroundStyle(FloatingSurfaceTheme.faint())
                    Image(systemName: "arrow.right").font(FloatingSurfaceTypography.metadata).foregroundStyle(FloatingSurfaceTheme.faint())
                    Text(confirmedCredits.map { "\(max(0, $0.availableCount - 1)) 次" } ?? "—")
                }.font(Font.system(size: 13, weight: .medium)).monospacedDigit()
            }
            Rectangle().fill(FloatingSurfaceTheme.separator()).frame(height: 0.5)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { cancelConfirmation() } label: {
                    Text("取消").font(FloatingSurfaceTypography.dialogAction)
                        .padding(.horizontal, 14).frame(height: 32)
                }.buttonStyle(DashboardResetActionStyle(primary: false))
                    .keyboardShortcut(.cancelAction)
                Button { submitConfirmedReset() } label: {
                    Text("消耗 1 次并重置").font(FloatingSurfaceTypography.dialogPrimaryAction)
                        .padding(.horizontal, 14).frame(height: 32)
                }.buttonStyle(DashboardResetActionStyle(primary: false, destructive: true, emphasized: true)).disabled(!available)
            }
        }.padding(22).foregroundStyle(FloatingSurfaceTheme.primary())
            .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FloatingSurfaceTheme.outline(), lineWidth: 0.5).allowsHitTesting(false) }
            .accessibilityElement(children: .contain).accessibilityLabel("重置额度二次确认")
    }
    private func cancelConfirmation() {
        confirmsReset = false; confirmedCredits = nil; confirmedAccount = nil
    }
    private func submitConfirmedReset() {
        guard available, let snapshot = confirmedCredits, let account = confirmedAccount,
              credits == snapshot, model.resetAccountFingerprint == account else {
            model.resetMessage = "账号或额度数据已变化，请重新确认。"
            cancelConfirmation()
            return
        }
        cancelConfirmation()
        model.onConsumeReset?(account, snapshot)
    }
}
