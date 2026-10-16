import SwiftUI

struct ActivityIslandSnapshot: Equatable {
    let projectID: String
    let projectName: String
    let phase: TaskPhase
    let actionText: String
    let sessionCount: Int
    let projectCount: Int
    let updatedAt: Date
    var sessionID: String? = nil
    var turnID: String? = nil
    var turnTokenUsage: TurnTokenUsage? = nil

}

@MainActor
final class ActivityIslandViewModel: ObservableObject {
    @Published var snapshot: ActivityIslandSnapshot?
    @Published var sessions: [ActivitySessionSnapshot] = []
    @Published var presentation: ActivityIslandPresentation = .hidden
    @Published var reduceMotionOverride = false
    @Published var playbackVisible = false
    @Published var material: ActivityIslandMaterial = .liquidGlass
    @Published var glassDegree: Double = 0.45
    @Published var progressEffect: ActivityIslandProgressEffect = .stateSmoke
    @Published var privacyMode = false
    @Published var floatingUsageEnabled = true
    @Published var usageCapsuleTone: ActivityIslandUsageCapsuleTone = .dark
    @Published var quotaState: QuotaState = .loading
    @Published var showsUsagePage = false
    var usagePageHeight: CGFloat = 580
    @Published var usageCost: CostSnapshot = .empty
    @Published var accountUsage: AccountUsageSnapshot?
    @Published var resetCredits: QuotaResetCreditSummary?
    var showsFloatingUsage: Bool { floatingUsageEnabled && !privacyMode && !showsUsagePage }
    @Published var focusedSessionID: String?
    @Published var isPinned = false
    @Published var metrics = ActivityIslandPanelMetrics(rowCount: 1,
                                                       availableSize: CGSize(width: 1000, height: 800))
    @Published var compactReceipt: ActivitySessionSnapshot?
    @Published var showsCompletedStatistic = false
    @Published var completionBurstSerial = 0
    // QuotaView IslandBoardState.showsCompactQuota: idle is a display branch,
    // never a fabricated activity row or a hidden primary interface.
    var showsCompactQuota: Bool { sessions.isEmpty || sessions.allSatisfy { $0.phase == .completed } }
    var idleSummary: String { sessions.isEmpty ? "暂无运行任务" : "全部任务已完成" }
    var compactQuotaPercent: String {
        guard !privacyMode, IslandFloatingQuotaPeriods.current(quotaState) else { return "—" }
        let windows = IslandFloatingQuotaPeriods.windows(quotaState)
        let window = windows.first { $0.windowDurationMinutes == 300 } ?? windows.first { $0.windowDurationMinutes == 10080 }
        return window.map { "\($0.remainingPercent)%" } ?? "—"
    }
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onInteraction: (() -> Void)?
    var onPin: (() -> Void)?
    var onSelect: ((String) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenUsage: (() -> Void)?
    var onBackToTasks: (() -> Void)?
    @Published var resetDetailVisible = false
    @Published var resetBusy = false
    @Published var resetConfirmationPresented = false
    @Published var resetMessage: String?
    @Published var resetAccountFingerprint: String?
    var onConsumeReset: ((String, QuotaResetCreditSummary) -> Void)?
    var onUsageHeightChange: ((CGFloat) -> Void)?
}

struct ActivityIslandView: View {
    @ObservedObject var model: ActivityIslandViewModel
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if compact && model.showsCompactQuota {
                ActivityIslandCompactQuotaContent(model: model)
            } else if compact, let row = ActivitySessionSnapshot.compactFocus(rows: model.sessions,
                selectedID: model.focusedSessionID, receipt: model.compactReceipt) {
                ActivityIslandCompactContent(row: model.privacyMode ? row.hidingDetails() : row,
                    rows: model.sessions, width: model.metrics.compactRect.width,
                    height: model.metrics.compactRect.height, hardwareGap: model.metrics.hardwareGap,
                    animated: model.playbackVisible && model.presentation == .compact && !motionIsReduced,
                    reduceMotion: motionIsReduced, showsCompletedStatistic: model.showsCompletedStatistic,
                    onExpand: model.onExpand)
            } else if !compact && model.showsUsagePage {
                ActivityIslandUsageDashboard(model: model)
                    .environment(\.islandLiquidGlassEnabled, model.material == .liquidGlass)
                    .transition(.opacity)
            } else if !compact {
                ActivityIslandExpandedList(rows: model.privacyMode ? model.sessions.map { $0.hidingDetails() } : model.sessions, width: model.metrics.expandedRect.width,
                    rowHeight: model.metrics.rowHeight, listHeight: model.metrics.listHeight,
                    animated: model.playbackVisible && model.presentation == .expanded,
                    onCollapse: model.onCollapse, onInteraction: model.onInteraction,
                    effect: model.progressEffect, focusedID: model.focusedSessionID ?? model.snapshot?.sessionID,
                    reduceMotion: motionIsReduced, pinned: model.isPinned,
                    onPin: model.onPin, onSelect: model.onSelect, onSettings: model.onOpenSettings, onRefresh: model.onRefresh,
                    onOpenUsage: model.onOpenUsage, quotaTitle: model.compactQuotaPercent)
                    .environment(\.islandLiquidGlassEnabled, model.material == .liquidGlass)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(motionIsReduced ? nil : .easeOut(duration: 0.22), value: model.showsUsagePage)
        .environment(\.islandGlassActive, model.presentation == (compact ? .compact : .expanded))
    }
    private var motionIsReduced: Bool { reduceMotion || model.reduceMotionOverride }
}

// Compact task branch adapted directly from QuotaView d16307f (MIT).
struct IslandCompactContentLayout: Layout {
    var gap: CGFloat = 16
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: max(0, proposal.width ?? sizes.reduce(0) { $0 + $1.width } + gap * 2),
            height: max(0, proposal.height ?? sizes.map(\.height).max() ?? 0))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let orb = subviews[0].sizeThatFits(.unspecified)
        let title = subviews[1].sizeThatFits(.unspecified)
        let statistics = subviews[2].sizeThatFits(.unspecified)
        let leading = bounds.minX + orb.width + gap
        let trailing = bounds.maxX - statistics.width - gap
        let titleWidth = min(title.width, max(0, trailing - leading))
        let center = titleWidth > 0
            ? min(max(bounds.midX, leading + titleWidth / 2), trailing - titleWidth / 2)
            : min(leading, bounds.maxX)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: .init(width: orb.width, height: orb.height))
        subviews[1].place(at: CGPoint(x: center, y: bounds.midY), anchor: .center,
            proposal: .init(width: titleWidth, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
            proposal: .init(width: statistics.width, height: statistics.height))
    }
}

struct ActivityIslandCompactContent: View {
    let row: ActivitySessionSnapshot
    let rows: [ActivitySessionSnapshot]
    let width: CGFloat
    let height: CGFloat
    let hardwareGap: CGFloat
    let animated: Bool
    let reduceMotion: Bool
    let showsCompletedStatistic: Bool
    var onExpand: (() -> Void)?
    private var completed: Int { rows.filter { $0.phase == .completed }.count }
    private var playsOrb: Bool { animated && (row.phase == .working || row.phase == .usingTool || row.phase == .completed) }
    private var symbol: some View {
        RippleGlowOrb(phase: row.phase, animated: playsOrb)
            .frame(width: 18, height: 18).frame(width: 30).accessibilityHidden(true)
    }
    private var taskText: some View {
        IslandScrollingText(text: row.compactTaskText, font: .systemFont(ofSize: 12, weight: .semibold),
                            visible: animated, reduceMotion: reduceMotion)
    }
    private var statistics: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .trailing) {
                Text("\(rows.count) 会话").hidden()
                Text("\(completed) 完成").hidden()
                Text(showsCompletedStatistic && completed > 0 ? "\(completed) 完成" : "\(rows.count) 会话")
            }.foregroundStyle(Color(white: 0.52))
            if rows.contains(where: { $0.phase == .waitingApproval }) {
                Text("待确认").foregroundStyle(.orange)
            }
            if rows.contains(where: { $0.phase == .failed || $0.phase == .ended }) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }.font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
            .frame(minWidth: 30, alignment: .trailing)
    }
    var body: some View {
        Button { onExpand?() } label: {
            Group {
                if hardwareGap > 0 {
                    let side = max(0, (width - 40 - hardwareGap - 16) / 2)
                    HStack(spacing: 0) {
                        HStack(spacing: 10) { symbol; taskText.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading) }
                            .frame(width: side).frame(maxWidth: .infinity).clipped()
                        Color.clear.frame(width: hardwareGap + 16)
                        statistics.frame(width: side, alignment: .trailing).frame(maxWidth: .infinity, alignment: .trailing).clipped()
                    }
                } else {
                    IslandCompactContentLayout { symbol; taskText; statistics }
                }
            }.padding(.horizontal, 20).frame(width: width, height: height).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(row.compactTaskText)，\(rows.count) 会话")
            .accessibilityValue(rows.contains(where: { $0.phase == .waitingApproval }) ? "待确认" : "")
            .accessibilityHint("悬停或点击展开会话详情")
    }
}

// Card information hierarchy adapted from QuotaView's IslandTaskCard (MIT).
struct ActivityIslandTaskCard: View {
    let row: ActivitySessionSnapshot
    let animated: Bool
    let rowHeight: CGFloat
    var selected = true
    var effect: ActivityIslandProgressEffect = .stateSmoke
    var reduceMotion = false
    var preview = false
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 12) {
            if !selected && row.phase != .completed {
              Group {
                if animated && !selected {
                    RippleGlowOrb(phase: row.phase, animated: true)
                } else {
                    Image(systemName: row.phase == .completed ? "checkmark.circle.fill" :
                          row.phase == .failed ? "exclamationmark.circle.fill" : "circle.fill")
                        .font(.system(size: 19)).foregroundStyle(row.phase.color)
                }
              }.frame(width: 34, height: 28).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if row.phase == .completed {
                        RippleGlowOrb(phase: .completed, animated: animated)
                            .frame(width: 18, height: 18).accessibilityHidden(true)
                    }
                    IslandScrollingText(text: row.title, font: .systemFont(ofSize: 13, weight: .semibold),
                        visible: animated, reduceMotion: reduceMotion)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Text(row.modelTitle).lineLimit(1).fixedSize().help(row.modelTitle)
                    Rectangle().fill(Color(white: 0.24)).frame(width: 1, height: 9)
                    Group {
                        if animated && !preview && row.startedAt != nil {
                            TimelineView(.periodic(from: .now, by: 60)) { context in Text(row.durationTitle(at: context.date)) }
                        } else { Text(row.durationTitle()) }
                    }.monospacedDigit().fixedSize()
                    Image(nsImage: ActivityIslandPreviewAssets.codexIcon ?? NSImage())
                        .resizable().scaledToFit().frame(width: 16, height: 16).accessibilityLabel("Codex")
                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(white: 0.52)).frame(height: 18)
                HStack(spacing: 8) {
                    let copy = IslandOperationText(operation: row.actionText,
                        statusTitle: row.statusTitle, completed: row.phase == .completed)
                    Text(copy.status)
                        .foregroundStyle(row.phase == .completed ? Color(red: 0.36, green: 0.80, blue: 0.55) : row.phase == .waitingApproval ? .orange : row.phase == .failed ? Color(red: 0.95, green: 0.43, blue: 0.42) : Color(white: 0.92))
                        .font(.system(size: 11, weight: .medium)).fixedSize()
                    if !copy.detail.isEmpty {
                        Text("·").foregroundStyle(Color(white: 0.60))
                        IslandScrollingText(text: copy.detail, font: .systemFont(ofSize: 11),
                            color: IslandTextPalette.secondary, visible: animated, reduceMotion: reduceMotion)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    } else { Spacer(minLength: 0) }
                    Text(row.displayedTokenTitle)
                        .monospacedDigit().lineLimit(1).fixedSize().accessibilityHint(row.phase == .completed ? "本轮消耗与会话累计" : "会话累计")
                }.font(.system(size: 10)).foregroundStyle(Color(white: 0.52)).frame(height: 18)
            }
        }
        .padding(.horizontal, 10).frame(height: rowHeight)
        .background {
            if selected {
                ActivityIslandTaskEffect(row: row, effect: effect, playback: animated,
                    reduceMotion: reduceMotion, preview: preview).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .islandGlass(RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: row.phase == .completed ? Color(red: 0.025, green: 0.055, blue: 0.035).opacity(hovered ? 0.32 : 0.42) : .black.opacity(hovered ? 0.32 : 0.42),
            solidTint: Color(white: 0.055))
        .onHover { hovered = $0 }
        .help("\(row.projectName) · \(row.title)\n\(row.actionText)\n\(row.displayedTokenTitle)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title)，\(row.phase.title)，\(row.actionText)，\(row.modelTitle)，\(row.displayedTokenTitle)")
    }
}

struct ActivityIslandExpandedList: View {
    let rows: [ActivitySessionSnapshot]
    let width: CGFloat
    let rowHeight: CGFloat
    let listHeight: CGFloat
    let animated: Bool
    var onCollapse: (() -> Void)?
    var onInteraction: (() -> Void)?
    var effect: ActivityIslandProgressEffect = .stateSmoke
    var focusedID: String?
    var reduceMotion = false
    var pinned = false
    var onPin: (() -> Void)?
    var onSelect: ((String) -> Void)?
    var onSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenUsage: (() -> Void)?
    var quotaTitle = "—"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { onOpenUsage?() } label: {
                    Label(quotaTitle + " · 用量", systemImage: "chart.pie")
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 8).frame(height: 24)
                        .islandGlass(Capsule(), tint: .white.opacity(0.08))
                }.buttonStyle(.plain).accessibilityLabel("查看用量统计")
                Spacer(minLength: 0)
                Button { onPin?() } label: { chromeIcon(pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).disabled(onPin == nil).accessibilityLabel(pinned ? "取消置顶" : "固定展开")
                Button { onCollapse?() } label: {
                    chromeIcon("chevron.up")
                }.buttonStyle(.plain).disabled(onCollapse == nil)
                    .accessibilityLabel("收起任务列表")
            }.foregroundStyle(.white).padding(.horizontal, 28)
                .frame(height: ActivityIslandPanelMetrics.headerHeight)
            if rows.isEmpty {
                Text("暂无运行任务").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .frame(width: width - 56, height: listHeight)
            } else {
                ActivityIslandTaskScroll(rows: rows, playback: animated,
                    rowHeight: rowHeight, onInteraction: onInteraction, effect: effect,
                    focusedID: focusedID ?? rows.first?.id, reduceMotion: reduceMotion, onSelect: onSelect)
                    .frame(width: width - 56, height: listHeight)
            }
            HStack(spacing: 8) {
                Text("\(rows.count) 个会话")
                Spacer(minLength: 0)
                Text(ActivitySessionSnapshot.statusSummary(rows)).lineLimit(1)
                    .help(ActivitySessionSnapshot.statusSummary(rows))
                Button { onRefresh?() } label: { chromeIcon("arrow.clockwise") }.buttonStyle(.plain)
                    .disabled(onRefresh == nil).accessibilityLabel("刷新任务状态")
                Button { onSettings?() } label: { chromeIcon("gearshape") }.buttonStyle(.plain)
                    .disabled(onSettings == nil).accessibilityLabel("灵动岛设置")
            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 28).padding(.bottom, 12).frame(height: ActivityIslandPanelMetrics.footerHeight)
        }.frame(width: width).accessibilityElement(children: .contain)
    }
    private func chromeIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24).islandGlass(Circle(), tint: .white.opacity(0.04), clearSurface: true)
    }
}
