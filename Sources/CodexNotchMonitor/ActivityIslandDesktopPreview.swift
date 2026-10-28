import SwiftUI

/// Synthetic sessions only; the stage itself is shared with the live island.
struct ActivityIslandDesktopPreview: View {
    let material: ActivityIslandMaterial
    let degree: Double
    let effect: ActivityIslandProgressEffect
    let expandedWidth: Double
    var maximumExpandedWidth: CGFloat = 680
    let animated: Bool
    let reduceMotion: Bool
    var privacyMode = false
    var floatingUsageEnabled = true
    var glassAppearance: ActivityIslandGlassAppearance = .dark
    var clawdEnabled = true
    var clawdSize: IslandClawdSize = .medium
    @State private var referenceDate = Date()

    static func sampleRows(now: Date, privacy: Bool) -> [ActivitySessionSnapshot] {
        let focus = ActivitySessionSnapshot(sessionID: "preview", turnID: "preview-turn", projectID: "preview", projectName: "示例项目",
            title: "整理项目资料", phase: .usingTool, actionText: "汇总文档，准备更新说明", updatedAt: now,
            tokenUsage: .init(sessionID: "preview", turnID: "preview-turn", total: 12800),
            modelName: "gpt-6.1-sol", reasoningEffort: "high", startedAt: now.addingTimeInterval(-120), sessionTotalTokens: 128000,
            recentSteps: [.init(id: "read", title: "阅读项目文档", state: .done),
                          .init(id: "sort", title: "梳理资料目录", state: .done),
                          .init(id: "write", title: "整理更新说明", state: .running)])
        let other = ActivitySessionSnapshot(sessionID: "preview-other", turnID: "other-turn", projectID: "preview", projectName: "示例项目",
            title: "检查说明文档", phase: .completed, actionText: "文档已检查", updatedAt: now,
            tokenUsage: .init(sessionID: "preview-other", turnID: "other-turn", total: 2400))
        return [focus, other].map { privacy ? $0.hidingDetails() : $0 }
    }

    var rows: [ActivitySessionSnapshot] { Self.sampleRows(now: referenceDate, privacy: privacyMode) }
    var listHeight: CGFloat {
        ActivityIslandPanelMetrics.stageHeight(rowCount: rows.count,
            focusHeight: ActivityIslandPanelMetrics.focusHeight(for: rows.first))
    }
    var stageHeight: CGFloat { ActivityIslandPanelMetrics.headerHeight + listHeight + ActivityIslandPanelMetrics.footerHeight }
    var showsUsage: Bool { floatingUsageEnabled && !privacyMode }

    func stage(width: CGFloat) -> ActivityIslandExpandedList {
        ActivityIslandExpandedList(rows: rows, width: width, rowHeight: 62, listHeight: listHeight,
            animated: animated, effect: effect, focusedID: rows.first?.id, reduceMotion: reduceMotion,
            quotaTitle: privacyMode ? "额度已隐藏" : "5h 72% · 7d 46%")
    }

    /// Compact strip so the pet switch and size are visible in the preview.
    private var compactSample: some View {
        let focus = rows.first
        return HStack(spacing: 6) {
            IslandClawdBadge(mood: focus.map { .mood(for: $0) } ?? .idle, pixel: clawdSize.pixel,
                             reduceMotion: reduceMotion, playing: animated,
                             species: focus.map { IslandPetSpecies(provider: $0.provider) } ?? .codex)
                .frame(width: clawdSize.pixel * 14, height: clawdSize.pixel * 12)
            Text(privacyMode ? "—" : "72%").monospacedDigit().foregroundStyle(FloatingSurfaceTheme.accent())
            Spacer(minLength: 12)
            Text(privacyMode ? "会话详情已隐藏" : focus?.title ?? "").lineLimit(1)
                .foregroundStyle(FloatingSurfaceTheme.primary(.dark))
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 14).frame(width: 300, height: 32)
        .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 24, 510) * min(1, CGFloat(expandedWidth) / max(1, maximumExpandedWidth))
            ZStack(alignment: .top) {
                if let image = ActivityIslandPreviewAssets.image("Wallpaper") {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                stage(width: width)
                    .background {
                        IslandHardwareBackdrop(radius: 24, compact: false, degree: degree,
                            mood: IslandHardwareBlack.mood(rows: rows, focusedID: rows.first?.id,
                                compact: false, showsCompactQuota: false, receipt: nil), reduceMotion: reduceMotion)
                    }
                    .environment(\.islandHardwareBlack, true)
                    .environment(\.colorScheme, .dark)
                if showsUsage {
                    IslandUsageCapsuleContent(windows: [
                        .init(usedPercent: 28, windowDurationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 12000)),
                        .init(usedPercent: 54, windowDurationMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 345600))
                    ], current: true, now: Date(timeIntervalSince1970: 0))
                        .modifier(IslandGlassChrome()).padding(.top, stageHeight + 8)
                }
                if clawdEnabled { compactSample.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12) }
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .environment(\.islandClawdCardsAnimate, clawdEnabled)
        }.environment(\.islandLiquidGlassEnabled, material == .liquidGlass)
            .modifier(IslandGlassAppearanceContext(appearance: glassAppearance, material: material))
            .allowsHitTesting(false).accessibilityElement(children: .ignore)
            .accessibilityLabel("灵动岛外观预览")
            .accessibilityValue("\(effect.title)，隐私模式\(privacyMode ? "已开启" : "已关闭")，展开宽度 \(Int(expandedWidth)) pt")
    }
}
