// Adapted from QuotaView d16307f IslandUsageCapsuleContent / IslandFloatingQuotaPeriods.
// Copyright (c) 2026 Duoasa, MIT; see Resources/ThirdPartyNotices.txt.
import SwiftUI

struct IslandFloatingQuotaPeriods {
    static func windows(_ windows: [RateLimitWindow]) -> [RateLimitWindow?] {
        let short = windows.first { $0.windowDurationMinutes == 300 }
        let week = windows.first { $0.windowDurationMinutes == 10080 }
        return short.map { [$0, week] } ?? [week]
    }
    static func current(_ state: QuotaState) -> Bool {
        if case .loaded = state { return true }
        return false
    }
    static func countdown(until reset: Date?, now: Date) -> String {
        guard let reset else { return "—" }
        let seconds = max(0, reset.timeIntervalSince(now))
        if seconds == 0 { return "待刷新" }
        if seconds >= 86400 { return "\(Int(seconds / 86400)) 天" }
        if seconds >= 3600 { return "\(Int(seconds / 3600)) 时" }
        return "\(max(1, Int(ceil(seconds / 60)))) 分"
    }
    static func windows(_ state: QuotaState) -> [RateLimitWindow] {
        // Never substitute a Spark/other-model bucket for the Codex account.
        state.buckets.first { $0.id == "codex" }?.windows ?? []
    }
}

struct IslandUsageCapsuleContent: View {
    let windows: [RateLimitWindow]
    let current: Bool
    let now: Date
    var tone: ActivityIslandUsageCapsuleTone = .dark
    private var ink: Color { .white }
    var body: some View {
        let periods = IslandFloatingQuotaPeriods.windows(windows)
        HStack(spacing: 12) {
            ForEach(periods.indices, id: \.self) { index in
                if index > 0 { Capsule().fill(ink.opacity(0.22)).frame(width: 1, height: 12) }
                period(periods[index], short: periods.count == 2 && index == 0)
            }
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
        .padding(.horizontal, 12).frame(height: 32).fixedSize()
        .islandGlass(Capsule(), tint: tone == .dark ? .black.opacity(0.55) : .clear,
                     solidTint: Color(white: 0.12), clearSurface: true)
        .environment(\.colorScheme, .dark)
        .environment(\.islandLiquidGlassEnabled, true)
    }
    private func period(_ window: RateLimitWindow?, short: Bool) -> some View {
        let percent = current ? window?.remainingPercent : nil
        let countdown = IslandFloatingQuotaPeriods.countdown(until: current ? window?.resetsAt : nil, now: now)
        let title = short ? "5 小时" : "周额度"
        let value = percent.map { "\($0)%" } ?? "—"
        let reset = window?.resetsAt != nil && current ? (countdown == "待刷新" ? countdown : "\(countdown)重置") : "重置时间 —"
        let color: Color = percent.map { $0 >= 50 ? Color(red: 0, green: 1, blue: 17.0 / 255) : $0 >= 20 ? Color(red: 1, green: 0.80, blue: 0) : Color(red: 1, green: 69.0 / 255, blue: 58.0 / 255) } ?? .gray
        return HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color(white: 0.18), lineWidth: 2)
                Circle().trim(from: 0, to: CGFloat(percent ?? 0) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }.padding(1).frame(width: 12, height: 12).accessibilityHidden(true)
            Text(title)
            Text(value).monospacedDigit()
            Text(reset).foregroundStyle(ink.opacity(0.78)).monospacedDigit()
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，剩余 \(value)，\(reset)")
    }
}

struct IslandFloatingUsageCapsule: View {
    @ObservedObject var model: ActivityIslandViewModel
    @ObservedObject var geometry: IslandGlassGeometry
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.showsFloatingUsage && model.presentation != .hidden {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    IslandUsageCapsuleContent(windows: IslandFloatingQuotaPeriods.windows(model.quotaState),
                        current: IslandFloatingQuotaPeriods.current(model.quotaState), now: context.date,
                        tone: model.usageCapsuleTone)
                }
                .position(x: geometry.value.rect.midX, y: geometry.value.rect.maxY + 24)
            }
        }.id(geometry.generation).allowsHitTesting(false)
    }
}

// QuotaView d16307f compact quota branch, using the same notch clearance and
// no-notch fitting layout as the running branch. No orb or activity renderer.
struct ActivityIslandCompactQuotaContent: View {
    @ObservedObject var model: ActivityIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var percent: some View {
        Text(model.compactQuotaPercent).monospacedDigit().fixedSize().foregroundStyle(.white)
    }
    private var summary: some View {
        IslandScrollingText(text: model.idleSummary, font: .systemFont(ofSize: 12, weight: .semibold),
            visible: model.playbackVisible && model.presentation == .compact,
            reduceMotion: reduceMotion || model.reduceMotionOverride)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
    private var statistics: some View {
        let completed = model.sessions.filter { $0.phase == .completed }.count
        return ZStack(alignment: .trailing) {
            Text("\(model.sessions.count) 会话").hidden()
            Text("\(completed) 完成").hidden()
            Text(model.showsCompletedStatistic && completed > 0 ? "\(completed) 完成" : "\(model.sessions.count) 会话")
        }.foregroundStyle(Color(white: 0.52)).monospacedDigit().fixedSize()
    }
    var body: some View {
        let width = model.metrics.compactRect.width
        let gap = model.metrics.hardwareGap
        return Button { model.onOpenUsage?() } label: {
            Group {
                if gap > 0 {
                    let side = max(0, (width - 40 - gap - 16) / 2)
                    HStack(spacing: 0) {
                        percent.frame(width: side, alignment: .leading).frame(maxWidth: .infinity).clipped()
                        Color.clear.frame(width: gap + 16)
                        HStack(spacing: 6) { summary; statistics }
                            .frame(width: side, alignment: .trailing).frame(maxWidth: .infinity).clipped()
                    }
                } else {
                    IslandCompactContentLayout { percent; summary; statistics }
                }
            }.padding(.horizontal, 20).frame(width: width, height: model.metrics.compactRect.height)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
            .accessibilityLabel("\(model.idleSummary)，剩余额度 \(model.compactQuotaPercent)，\(model.sessions.count) 会话")
            .accessibilityHint("悬停或点击展开会话详情")
    }
}
