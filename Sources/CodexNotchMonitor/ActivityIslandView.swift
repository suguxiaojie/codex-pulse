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
    @Published var glassAppearance: ActivityIslandGlassAppearance = .dark
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
    private struct ReplyCueHistory {
        let turnID: String?
        var requestIDs: Set<String> = []
        var fallbackShown = false
    }
    private var replyCueHistory: [String: ReplyCueHistory] = [:]

    /// Shared by compact and expanded surfaces, so rebuilding a view cannot replay a cue.
    func claimReplyCue(for row: ActivitySessionSnapshot) -> Bool {
        guard row.phase == .waitingApproval, row.waitReason == .userInput else { return false }
        var history = replyCueHistory[row.sessionID].flatMap { $0.turnID == row.turnID ? $0 : nil }
            ?? ReplyCueHistory(turnID: row.turnID)
        let shouldPlay: Bool
        if row.replyRequestIDs.isEmpty {
            shouldPlay = !history.fallbackShown && history.requestIDs.isEmpty
            history.fallbackShown = true
        } else {
            shouldPlay = !(history.fallbackShown && history.requestIDs.isEmpty)
                && !row.replyRequestIDs.subtracting(history.requestIDs).isEmpty
            history.requestIDs.formUnion(row.replyRequestIDs)
        }
        replyCueHistory[row.sessionID] = history
        return shouldPlay
    }

    func finishReplyCues(for rows: [ActivitySessionSnapshot]) {
        for row in rows where !row.phase.isActive { replyCueHistory.removeValue(forKey: row.sessionID) }
    }
    // QuotaView IslandBoardState.showsCompactQuota: idle is a display branch,
    // never a fabricated activity row or a hidden primary interface.
    var showsCompactQuota: Bool {
        if sessions.isEmpty { return true }
        guard sessions.allSatisfy({ $0.phase == .completed }) else { return false }
        guard let receipt = compactReceipt else { return true }
        return !sessions.contains { $0.id == receipt.id && $0.turnID == receipt.turnID && $0.phase == .completed }
    }
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
                    reduceMotion: motionIsReduced,
                    onExpand: model.onExpand,
                    replyCueVisible: model.playbackVisible && model.presentation == .compact,
                    claimReplyCue: { model.claimReplyCue(for: $0) })
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
                    onOpenUsage: model.onOpenUsage, quotaTitle: model.compactQuotaPercent,
                    claimReplyCue: { model.claimReplyCue(for: $0) })
                    .environment(\.islandLiquidGlassEnabled, model.material == .liquidGlass)
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .modifier(IslandGlassAppearanceContext(appearance: model.glassAppearance, material: model.material))
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

// Presentation only: terminal evidence, focus ordering and lifecycle stay in their owners.
private struct IslandSessionPresentation {
    let row: ActivitySessionSnapshot
    var isResult: Bool { !row.phase.isActive }
    private var status: (title: String, symbol: String, color: Color) {
        if row.endReason == .cancelled {
            return ("本轮已取消", "stop.circle", FloatingSurfaceTheme.secondary())
        }
        switch row.phase {
        case .starting: return ("开始中", "hourglass", FloatingSurfaceTheme.secondary())
        case .working: return ("思考中", "ellipsis", FloatingSurfaceTheme.accent())
        case .usingTool: return ("执行工具", "terminal.fill", FloatingSurfaceTheme.accent())
        case .waitingApproval:
            return row.waitReason == .userInput
                ? ("待回复", "questionmark.bubble.fill", .orange)
                : ("待批准", "hand.raised.fill", .orange)
        case .completed: return ("本轮已完成", "checkmark.circle.fill", FloatingSurfaceTheme.success)
        case .failed: return ("本轮失败", "exclamationmark.circle.fill", FloatingSurfaceTheme.danger)
        case .ended: return ("会话已结束", "minus.circle", FloatingSurfaceTheme.secondary())
        }
    }
    var title: String { status.title }
    var symbol: String { status.symbol }
    var color: Color { status.color }
    var modelTitle: String {
        row.isPrivate ? "模型已隐藏" : row.modelTitle.isEmpty ? "模型未知" : row.modelTitle
    }
    var runningDetail: String {
        let action = row.actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = action.isEmpty || action == row.phase.title || action == row.statusTitle
        if row.phase == .waitingApproval {
            if row.waitReason == .userInput { return "请在 Codex 中选择或回复" }
            return generic ? "请在 Codex 中处理批准请求" : "请在 Codex 中处理 · " + action
        }
        if !generic { return action }
        return row.projectName.isEmpty ? "Codex 任务" : "项目 · " + row.projectName
    }
    var compactTitle: String {
        if row.phase == .waitingApproval && row.waitReason == .userInput {
            return title + " · " + (row.isPrivate ? "会话详情已隐藏" : row.title)
        }
        return (isResult ? summaryGroup : title) + " · " + (row.isPrivate ? "会话详情已隐藏" : isResult ? row.title : runningDetail)
    }
    var turnTokens: String {
        guard !row.isPrivate else { return "用量已隐藏" }
        let total = row.tokenUsage.flatMap { usage -> Int? in
            guard let turn = row.turnID, !turn.isEmpty, usage.sessionID == row.sessionID,
                  usage.turnID == turn, let total = usage.total, total >= 0 else { return nil }
            return total
        }
        let value = total.map { CodexActivityTokenUsageFormatter.string(for: Int64($0)) } ?? "—"
        return "本轮 \(value) tokens"
    }
    var cumulativeTokens: String { row.isPrivate ? "用量已隐藏" : "累计 " + row.tokenTitle }
    func duration(at now: Date = Date()) -> String {
        row.durationTitle(at: isResult ? row.updatedAt : now)
    }
    var accessibilitySummary: String {
        if row.isPrivate { return title + "，会话详情已隐藏" }
        let detail = isResult ? "耗时 " + duration() + "，" + turnTokens : runningDetail + "，已运行 " + duration()
        return [row.title, title, detail, modelTitle, cumulativeTokens].joined(separator: "，")
    }
    private var summaryGroup: String {
        if row.endReason == .cancelled { return "取消" }
        switch row.phase {
        case .waitingApproval: return row.waitReason == .userInput ? "待回复" : "待批准"
        case .starting, .working, .usingTool: return "运行"
        case .failed: return "失败"
        case .completed: return "完成"
        case .ended: return "结束"
        }
    }
    static func conciseSummary(_ rows: [ActivitySessionSnapshot], maxGroups: Int = 6) -> Text {
        let counts = Dictionary(grouping: rows, by: { Self(row: $0).summaryGroup }).mapValues(\.count)
        let groups: [(title: String, count: Int)] = ["待批准", "待回复", "失败", "运行", "完成", "取消", "结束"]
            .compactMap { title in counts[title].map { (title, $0) } }
        guard !groups.isEmpty else { return Text("暂无运行任务").foregroundColor(FloatingSurfaceTheme.secondary()) }
        return groups.prefix(max(1, maxGroups)).enumerated().reduce(Text("")) { text, item in
            let group = item.element
            let color: Color = ["待批准", "待回复"].contains(group.title) ? .orange : group.title == "失败" ? FloatingSurfaceTheme.danger : FloatingSurfaceTheme.secondary()
            let separator = Text(item.offset == 0 ? "" : " · ").foregroundColor(FloatingSurfaceTheme.secondary())
            return text + separator + Text("\(group.count) \(group.title)").foregroundColor(color)
        }
    }
    static func summary(_ rows: [ActivitySessionSnapshot]) -> String {
        let order = ["待批准", "待回复", "开始中", "思考中", "执行工具", "本轮失败", "本轮已完成", "本轮已取消", "会话已结束"]
        let counts = Dictionary(grouping: rows, by: { Self(row: $0).title }).mapValues(\.count)
        return rows.isEmpty ? "暂无运行任务" : order.compactMap { title in counts[title].map { "\($0) \(title)" } }.joined(separator: " · ")
    }
}

private struct IslandSessionSummaryView: View {
    let rows: [ActivitySessionSnapshot]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            IslandSessionPresentation.conciseSummary(rows)
                .fixedSize(horizontal: true, vertical: false)
            IslandSessionPresentation.conciseSummary(rows, maxGroups: 2)
                .fixedSize(horizontal: true, vertical: false)
            IslandSessionPresentation.conciseSummary(rows, maxGroups: 1)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .monospacedDigit()
        .help(IslandSessionPresentation.summary(rows))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("会话状态")
        .accessibilityValue(IslandSessionPresentation.summary(rows))
    }
}

/// Replay history belongs to the model, while this modifier owns only the brief cue.
private struct IslandReplyCue: ViewModifier {
    let row: ActivitySessionSnapshot
    let visible: Bool
    let reduceMotion: Bool
    var claim: ((ActivitySessionSnapshot) -> Bool)?
    @Binding var active: Bool
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .onAppear { refresh() }
            .onChange(of: row) { _ in refresh() }
            .onChange(of: visible) { _ in refresh() }
            .onChange(of: reduceMotion) { _ in refresh() }
            .onDisappear { stop() }
    }

    private func refresh() {
        guard visible, row.phase == .waitingApproval, row.waitReason == .userInput else {
            stop(); return
        }
        // Consume in Reduce Motion too, so enabling motion later cannot replay it.
        guard claim?(row) == true else {
            if reduceMotion { stop() }
            return
        }
        generation += 1
        let current = generation
        guard !reduceMotion else { active = false; return }
        withAnimation(MonitorDesktopTheme.selectionMotion) { active = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == current else { return }
            withAnimation(MonitorDesktopTheme.hoverMotion) { active = false }
        }
    }

    private func stop() {
        generation += 1
        withAnimation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion) { active = false }
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
    var onExpand: (() -> Void)?
    var replyCueVisible = false
    var claimReplyCue: ((ActivitySessionSnapshot) -> Bool)?
    @State private var replyCueActive = false
    private var presentation: IslandSessionPresentation { .init(row: row) }
    private var symbol: some View {
        Group {
            if !presentation.isResult && animated && !reduceMotion && (row.phase == .working || row.phase == .usingTool) {
                RippleGlowOrb(phase: row.phase, animated: true)
            } else {
                Image(systemName: presentation.symbol).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(presentation.color)
            }
        }.frame(width: 18, height: 18)
            .scaleEffect(replyCueActive ? 1.12 : 1)
            .animation(reduceMotion ? nil : MonitorDesktopTheme.selectionMotion, value: replyCueActive)
            .frame(width: 30).accessibilityHidden(true)
    }
    private var taskText: some View {
        IslandScrollingText(text: presentation.compactTitle, font: .systemFont(ofSize: 12, weight: .semibold),
                            visible: animated && !presentation.isResult && row.waitReason != .userInput, reduceMotion: reduceMotion)
    }
    private var statistics: some View {
        let side = max(0, (width - 40 - hardwareGap - (hardwareGap > 0 ? 16 : 0)) / 2)
        return IslandSessionSummaryView(rows: rows)
            .font(FloatingSurfaceTypography.action).foregroundStyle(FloatingSurfaceTheme.secondary())
            .frame(width: min(220, side), alignment: .trailing)
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
            .help(presentation.accessibilitySummary)
            .accessibilityLabel("\(presentation.accessibilitySummary)，\(rows.count) 会话")
            .accessibilityValue(IslandSessionPresentation.summary(rows))
            .accessibilityHint("悬停或点击展开会话详情")
            .modifier(IslandReplyCue(row: row, visible: replyCueVisible,
                reduceMotion: reduceMotion, claim: claimReplyCue, active: $replyCueActive))
    }
}

// Card shell and native glass adapted from QuotaView's IslandTaskCard (MIT).
struct ActivityIslandTaskCard: View {
    let row: ActivitySessionSnapshot
    let animated: Bool
    let rowHeight: CGFloat
    var selected = true
    var effect: ActivityIslandProgressEffect = .stateSmoke
    var reduceMotion = false
    var preview = false
    var claimReplyCue: ((ActivitySessionSnapshot) -> Bool)?
    @State private var hovered = false
    @State private var replyCueActive = false
    private var presentation: IslandSessionPresentation { .init(row: row) }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(presentation.color)
                    .id(presentation.symbol).transition(.opacity)
            }
                .frame(width: 28, height: 28)
                .scaleEffect(replyCueActive ? 1.10 : 1)
                .animation(reduceMotion ? nil : MonitorDesktopTheme.selectionMotion, value: replyCueActive)
                .animation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion, value: presentation.symbol)
                .background(FloatingSurfaceTheme.accent().opacity(selected ? 0.16 : 0),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FloatingSurfaceTheme.primary())
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(presentation.title).font(FloatingSurfaceTypography.captionMedium)
                        .foregroundStyle(presentation.color).fixedSize()
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion, value: presentation.title)
                }.frame(height: 16)
                if row.isPrivate {
                    Text("会话详情已隐藏").font(FloatingSurfaceTypography.caption)
                        .foregroundStyle(FloatingSurfaceTheme.secondary())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 29, alignment: .topLeading)
                } else {
                    if presentation.isResult { resultLine } else { runningLine }
                    metadataLine
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).frame(height: rowHeight)
        .background {
            if selected && (!presentation.isResult || row.phase == .completed) {
                ActivityIslandTaskEffect(row: row, effect: effect, playback: animated,
                    reduceMotion: reduceMotion, preview: preview, replyCueActive: replyCueActive)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .islandGlass(RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: row.phase == .completed ? Color(red: 0.025, green: 0.055, blue: 0.035).opacity(hovered ? 0.32 : 0.42) : .black.opacity(hovered ? 0.32 : 0.42),
            solidTint: Color(white: 0.055))
        .onHover { hovered = $0 }
        .help(row.isPrivate ? presentation.accessibilitySummary : "\(row.projectName) · \(row.title)\n\(presentation.accessibilitySummary)\n\(row.actionText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary)
        .modifier(IslandReplyCue(row: row, visible: animated && selected && !preview,
            reduceMotion: reduceMotion, claim: claimReplyCue, active: $replyCueActive))
    }

    private var runningLine: some View {
        IslandScrollingText(text: presentation.runningDetail, font: .systemFont(ofSize: 11),
            color: IslandTextPalette.secondary, visible: animated && selected && row.waitReason != .userInput, reduceMotion: reduceMotion)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 14)
    }
    private var resultLine: some View {
        HStack(spacing: 8) {
            Text("耗时 " + presentation.duration()).monospacedDigit().fixedSize()
            Text("·").accessibilityHidden(true)
            Text(presentation.turnTokens).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .font(FloatingSurfaceTypography.caption).foregroundStyle(FloatingSurfaceTheme.primary())
        .frame(height: 14)
    }
    private var metadataLine: some View {
        HStack(spacing: 8) {
            Text(presentation.modelTitle).lineLimit(1).truncationMode(.tail)
                .help(presentation.modelTitle)
            Spacer(minLength: 4)
            if !presentation.isResult {
                Group {
                    if animated && !preview && row.startedAt != nil {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(presentation.duration(at: context.date))
                        }
                    } else { Text(presentation.duration()) }
                }.monospacedDigit().fixedSize()
            }
            Text(presentation.cumulativeTokens).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(FloatingSurfaceTypography.metadata).foregroundStyle(FloatingSurfaceTheme.secondary())
        .frame(height: 12)
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
    var claimReplyCue: ((ActivitySessionSnapshot) -> Bool)?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { onOpenUsage?() } label: {
                    HStack(spacing: 5) {
                        Text(quotaTitle).font(FloatingSurfaceTypography.control).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .medium))
                            .foregroundStyle(FloatingSurfaceTheme.secondary()).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 8).frame(height: 24)
                    .islandGlass(Capsule(), tint: FloatingSurfaceTheme.chipFill())
                }.buttonStyle(FloatingSurfaceButtonStyle())
                    .help("查看额度与用量")
                    .accessibilityLabel("查看额度与用量").accessibilityValue(quotaTitle)
                Spacer(minLength: 0)
                Button { onPin?() } label: { chromeIcon(pinned ? "pin.fill" : "pin") }
                    .buttonStyle(FloatingSurfaceButtonStyle(circularFocus: true)).disabled(onPin == nil).accessibilityLabel(pinned ? "取消置顶" : "固定展开")
                Button { onCollapse?() } label: {
                    chromeIcon("chevron.up")
                }.buttonStyle(FloatingSurfaceButtonStyle(circularFocus: true)).disabled(onCollapse == nil)
                    .accessibilityLabel("收起任务列表")
            }.foregroundStyle(FloatingSurfaceTheme.primary()).padding(.horizontal, 28)
                .frame(height: ActivityIslandPanelMetrics.headerHeight)
            if rows.isEmpty {
                Text("暂无运行任务").font(FloatingSurfaceTypography.body).foregroundStyle(FloatingSurfaceTheme.secondary())
                    .frame(width: width - 56, height: listHeight)
            } else {
                ActivityIslandTaskScroll(rows: rows, playback: animated,
                    rowHeight: rowHeight, onInteraction: onInteraction, effect: effect,
                    focusedID: focusedID ?? rows.first?.id, reduceMotion: reduceMotion, onSelect: onSelect,
                    claimReplyCue: claimReplyCue)
                    .frame(width: width - 56, height: listHeight)
            }
            HStack(spacing: 8) {
                Text("\(rows.count) 个会话")
                Spacer(minLength: 0)
                IslandSessionSummaryView(rows: rows)
                Button { onRefresh?() } label: { chromeIcon("arrow.clockwise") }.buttonStyle(FloatingSurfaceButtonStyle(circularFocus: true))
                    .disabled(onRefresh == nil).accessibilityLabel("刷新任务状态")
                Button { onSettings?() } label: { chromeIcon("gearshape") }.buttonStyle(FloatingSurfaceButtonStyle(circularFocus: true))
                    .disabled(onSettings == nil).accessibilityLabel("灵动岛设置")
            }.font(FloatingSurfaceTypography.body).modifier(IslandGlassChrome())
                .padding(.horizontal, 28).padding(.bottom, 12).frame(height: ActivityIslandPanelMetrics.footerHeight)
        }.frame(width: width).accessibilityElement(children: .contain)
    }
    private func chromeIcon(_ name: String) -> some View {
        IslandChromeIcon(name: name)
    }
}
