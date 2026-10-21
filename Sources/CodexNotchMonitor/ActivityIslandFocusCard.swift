import SwiftUI

struct ActivityIslandFocusCard: View {
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
    var hasInlineApproval = false
    private var presentation: IslandSessionPresentation { .init(row: row, hasInlineApproval: hasInlineApproval) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    IslandSessionMascot(row: row, size: 26, animated: animated && selected && !preview,
                        reduceMotion: reduceMotion, replyCueActive: replyCueActive)
                        .frame(width: 28, height: 28)
                        .scaleEffect(replyCueActive ? 1.10 : 1)
                        .animation(reduceMotion ? nil : MonitorDesktopTheme.selectionMotion, value: replyCueActive)
                        .animation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion, value: presentation.symbol)
                        .background(FloatingSurfaceTheme.accent().opacity(selected ? 0.16 : 0),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    Text(row.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FloatingSurfaceTheme.primary())
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(presentation.title).font(FloatingSurfaceTypography.captionMedium)
                        .foregroundStyle(presentation.color).fixedSize()
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion, value: presentation.title)
                }.frame(height: 28)
                if row.isPrivate {
                    Text("会话详情已隐藏").font(FloatingSurfaceTypography.caption)
                        .foregroundStyle(FloatingSurfaceTheme.secondary())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 29, alignment: .topLeading)
                } else {
                    if presentation.isResult { resultLine }
                    if row.recentSteps.isEmpty {
                        if !presentation.isResult { runningLine }
                    } else { steps }
                    metadataLine
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).frame(height: rowHeight)
        .background {
            if selected && (!presentation.isResult || row.phase == .completed) {
                ActivityIslandTaskEffect(row: row, effect: effect, playback: animated && !row.isRetainedReceipt,
                    reduceMotion: reduceMotion, preview: preview, replyCueActive: replyCueActive)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .islandGlass(RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: row.phase == .completed ? Color(red: 0.025, green: 0.055, blue: 0.035).opacity(hovered ? 0.32 : 0.42) : .black.opacity(hovered ? 0.32 : 0.42),
            solidTint: Color(white: 0.055),
            hardwareTint: row.phase == .completed ? IslandHardwareBlack.completedSurface : IslandHardwareBlack.surface)
        .onHover { hovered = $0 }
        .help(row.isPrivate ? presentation.accessibilitySummary : "\(row.projectName) · \(row.title)\n\(presentation.accessibilitySummary)\n\(row.actionText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary)
        .modifier(IslandReplyCue(row: row, visible: animated && selected && !preview,
            reduceMotion: reduceMotion, claim: claimReplyCue, active: $replyCueActive))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(row.recentSteps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 6) {
                    Image(systemName: step.state == .done ? "checkmark" : step.state == .waiting ? "pause.fill" : "circle.fill")
                        .font(.system(size: 9)).frame(width: 12)
                        .foregroundStyle(step.state == .waiting ? Color.orange : step.state == .running ? FloatingSurfaceTheme.accent() : FloatingSurfaceTheme.secondary())
                    if index == row.recentSteps.count - 1 && !presentation.isResult {
                        IslandScrollingText(text: presentation.currentStepDetail, font: .systemFont(ofSize: 11),
                            color: IslandTextPalette.secondary, visible: animated, reduceMotion: reduceMotion)
                    } else {
                        Text(step.title).font(.system(size: 11)).foregroundStyle(FloatingSurfaceTheme.secondary())
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(height: 14)
            }
        }
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
            Text((row.provider == "Codex" ? "" : "Claude · ") + presentation.modelTitle).lineLimit(1).truncationMode(.tail)
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
                Text(presentation.turnTokens).monospacedDigit().lineLimit(1).fixedSize()
            }
        }
        .font(FloatingSurfaceTypography.metadata).foregroundStyle(FloatingSurfaceTheme.secondary())
        .frame(height: 12)
    }
}

struct ActivityIslandSessionRail: View {
    let rows: [ActivitySessionSnapshot]
    var onSelect: ((String) -> Void)?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rows) { row in
                    let presentation = IslandSessionPresentation(row: row)
                    Button { onSelect?(row.id) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(presentation.color).frame(width: 5, height: 5)
                            Text(row.title).lineLimit(1).frame(maxWidth: 130)
                            Group {
                                if presentation.isResult {
                                    Text(row.statusTitle)
                                } else {
                                    TimelineView(.periodic(from: .now, by: 60)) { context in
                                        Text(presentation.duration(at: context.date))
                                    }
                                }
                            }.monospacedDigit()
                        }.font(FloatingSurfaceTypography.caption)
                            .foregroundStyle(FloatingSurfaceTheme.secondary())
                            .padding(.horizontal, 10).frame(height: 30)
                            .islandGlass(Capsule(), tint: row.phase == .completed
                                ? Color(red: 0.025, green: 0.055, blue: 0.035).opacity(0.42) : .black.opacity(0.42),
                                hardwareTint: row.phase == .completed ? IslandHardwareBlack.completedSurface : IslandHardwareBlack.surface)
                            .opacity(row.isRetainedReceipt ? 0.6 : 1)
                    }.buttonStyle(.plain).help(presentation.accessibilitySummary)
                        .accessibilityLabel(presentation.accessibilitySummary)
                        .accessibilityHint("切换焦点会话")
                }
            }
        }.frame(height: 30)
    }
}
