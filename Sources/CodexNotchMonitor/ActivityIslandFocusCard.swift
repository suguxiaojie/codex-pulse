import SwiftUI
import AppKit

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
    private var moodColor: Color { IslandMascotMood.mood(for: row).middleColor }
    private var live: Bool { animated && selected && !preview }
    /// The last three steps become timeline nodes; a failed turn marks its final node.
    private var timelineSteps: [IslandStep] { Array(row.recentSteps.suffix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 3) {
                    statusCapsule
                    Text(row.title).font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(FloatingSurfaceTheme.primary())
                        .lineLimit(1).truncationMode(.tail)
                    detailLine
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                clock
            }
            if row.isPrivate {
                Text("会话详情已隐藏").font(FloatingSurfaceTypography.caption)
                    .foregroundStyle(FloatingSurfaceTheme.secondary()).frame(height: 14)
            } else if !timelineSteps.isEmpty {
                timeline
            }
            metadataLine
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight)
        .background {
            if selected && (!presentation.isResult || row.phase == .completed) {
                ActivityIslandTaskEffect(row: row, effect: effect, playback: animated && !row.isRetainedReceipt,
                    reduceMotion: reduceMotion, preview: preview, replyCueActive: replyCueActive)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .background {
            if selected && (row.phase == .waitingApproval || presentation.isResult) {
                resultGlow.allowsHitTesting(false).accessibilityHidden(true)
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
        .modifier(IslandReplyCue(row: row, visible: live, reduceMotion: reduceMotion, claim: claimReplyCue, active: $replyCueActive))
    }

    /// Pixel Clawd placed directly on the card; 35 pt keeps each sprite pixel at 2.5 pt.
    private var badge: some View {
        IslandSessionMascot(row: row, size: 35, animated: live, reduceMotion: reduceMotion, replyCueActive: replyCueActive)
            .frame(width: 35, height: 35)
            .scaleEffect(replyCueActive ? 1.08 : 1)
            .animation(reduceMotion ? nil : MonitorDesktopTheme.selectionMotion, value: replyCueActive)
            .accessibilityHidden(true)
    }

    /// Faint state-colour light for cards that have no running effect behind them.
    private var resultGlow: some View {
        ZStack {
            RadialGradient(colors: [moodColor.opacity(0.22), moodColor.opacity(0)], center: UnitPoint(x: 0.12, y: 0),
                           startRadius: 0, endRadius: 260)
            RadialGradient(colors: [moodColor.opacity(0.10), moodColor.opacity(0)], center: .bottomTrailing,
                           startRadius: 0, endRadius: 220)
        }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusCapsule: some View {
        HStack(spacing: 5) {
            IslandPulseDot(color: moodColor, style: .status,
                playing: live && !presentation.isResult, reduceMotion: reduceMotion)
                .frame(width: 6, height: 6)
            Text(presentation.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 8).frame(height: 18)
        // Same state hue as the rim, badge border and timeline.
        .background(moodColor.opacity(0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(moodColor.opacity(0.5), lineWidth: 1))
        .animation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion, value: presentation.title)
    }

    @ViewBuilder private var detailLine: some View {
        // The timeline already names the step, so this line carries only the concrete action.
        let text = presentation.runningDetail
        if row.isPrivate || presentation.isResult {
            Text(row.isPrivate ? "会话详情已隐藏" : text).font(.system(size: 11.5))
                .foregroundStyle(FloatingSurfaceTheme.secondary()).lineLimit(1).frame(height: 14)
        } else {
            IslandScrollingText(text: text, font: .systemFont(ofSize: 11.5), color: IslandTextPalette.secondary,
                visible: live && row.waitReason != .userInput, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 14)
        }
    }

    /// Secondary elapsed clock; ticks every second only while the focused card is live.
    private var clock: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Group {
                if live && !presentation.isResult && row.startedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in Text(Self.clockTitle(row: row, at: context.date)) }
                } else { Text(Self.clockTitle(row: row, at: Date())) }
            }
            .font(.system(size: 17, weight: .regular, design: .monospaced)).monospacedDigit()
            .foregroundStyle(FloatingSurfaceTheme.primary().opacity(0.8))
            Text(presentation.isResult ? "耗时" : "已用时长").font(.system(size: 10)).foregroundStyle(FloatingSurfaceTheme.secondary())
        }.fixedSize()
    }

    static func clockTitle(row: ActivitySessionSnapshot, at now: Date) -> String {
        guard let startedAt = row.startedAt else { return "—" }
        let seconds = max(0, Int((row.endReason == nil && row.phase.isActive ? now : row.updatedAt).timeIntervalSince(startedAt)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Horizontal track: completed nodes green, the running node glows and breathes, waiting is amber, failure red.
    private var timeline: some View {
        let steps = timelineSteps
        let current = steps.lastIndex { $0.state == .running || $0.state == .waiting } ?? (steps.count - 1)
        return GeometryReader { proxy in
            let slot = proxy.size.width / CGFloat(steps.count)
            let first = slot / 2, last = proxy.size.width - slot / 2
            let reached = first + slot * CGFloat(current)
            ZStack(alignment: .topLeading) {
                Path { $0.move(to: CGPoint(x: first, y: 7)); $0.addLine(to: CGPoint(x: last, y: 7)) }
                    .stroke(Color.white.opacity(0.16), lineWidth: 2)
                Path { $0.move(to: CGPoint(x: first, y: 7)); $0.addLine(to: CGPoint(x: reached, y: 7)) }
                    .stroke(LinearGradient(colors: [Color(red: 0.30, green: 0.83, blue: 0.48), moodColor], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                HStack(spacing: 0) {
                    ForEach(steps) { step in
                        VStack(spacing: 6) {
                            node(step)
                            Text(step.title).font(.system(size: 10, design: .monospaced))
                                .help(step.title)
                                .foregroundStyle(step.state == .done ? FloatingSurfaceTheme.secondary() : FloatingSurfaceTheme.primary())
                                .lineLimit(1).truncationMode(.tail).padding(.horizontal, 4)
                        }.frame(width: slot)
                    }
                }
            }
        }
        .frame(height: 34)
    }

    @ViewBuilder private func node(_ step: IslandStep) -> some View {
        let green = Color(red: 0.30, green: 0.83, blue: 0.48)
        switch step.state {
        case .done:
            Circle().fill(Color(white: 0.06)).overlay(Circle().strokeBorder(green, lineWidth: 2)).frame(width: 14, height: 14)
        case .waiting:
            Circle().fill(Color(red: 1, green: 0.70, blue: 0.25)).frame(width: 14, height: 14)
        case .failed:
            Circle().fill(Color(red: 1, green: 0.35, blue: 0.31)).frame(width: 14, height: 14)
        case .ended:
            Circle().strokeBorder(FloatingSurfaceTheme.secondary(), lineWidth: 2).frame(width: 14, height: 14)
        case .running:
            IslandPulseDot(color: moodColor, style: .step,
                playing: live && !presentation.isResult, reduceMotion: reduceMotion)
                .frame(width: 28, height: 28)
                .frame(width: 14, height: 14)
        }
    }

    /// "gpt-6.1-sol" + "high" reads "GPT-6.1 Sol · High"; other model families keep the shared title.
    static func modelDisplayTitle(_ row: ActivitySessionSnapshot) -> String {
        guard let name = row.modelName?.trimmingCharacters(in: .whitespacesAndNewlines), name.lowercased().hasPrefix("gpt-") else {
            return row.modelDetailsTitle
        }
        let parts = name.dropFirst(4).split(separator: "-").map(String.init)
        let model = (["GPT-" + (parts.first ?? "")] + parts.dropFirst().map(\.capitalized)).joined(separator: " ")
        return [model, row.reasoningEffort?.capitalized].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var metadataLine: some View {
        HStack(spacing: 8) {
            Text((row.provider == "Codex" ? "" : "Claude · ") + (row.isPrivate ? "模型已隐藏" : Self.modelDisplayTitle(row))).lineLimit(1).truncationMode(.tail)
                .help(presentation.modelTitle)
            if !row.fastModeTitle.isEmpty {
                Text(row.fastModeTitle).fixedSize().help("当前会话已开启 Fast 模式")
            }
            if !row.isPrivate && !row.projectName.isEmpty {
                Text(row.projectName).lineLimit(1).padding(.horizontal, 6)
                    .foregroundStyle(FloatingSurfaceTheme.primary().opacity(0.78))
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Spacer(minLength: 4)
            Text(presentation.turnTokens).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(FloatingSurfaceTypography.metadata).foregroundStyle(FloatingSurfaceTheme.secondary())
        .frame(height: 13)
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
                            Circle().fill(IslandMascotMood.mood(for: row).middleColor).frame(width: 6, height: 6)
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

/// The two small pulse cues animate layers without invalidating the SwiftUI card.
struct IslandPulseDot: NSViewRepresentable {
    let color: Color
    let style: IslandPulseDotView.Style
    let playing: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> IslandPulseDotView { IslandPulseDotView() }
    func updateNSView(_ view: IslandPulseDotView, context: Context) {
        view.update(color: NSColor(color), style: style, playing: playing, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: IslandPulseDotView, coordinator: ()) { view.stop() }
}

final class IslandPulseDotView: NSView {
    enum Style { case status, step }
    private let pulse = CALayer()
    private let dot = CAShapeLayer()
    private let halo = CAShapeLayer()
    private var style: Style = .status
    private var playing = false
    private var reduced = false
    private var observers: [NSObjectProtocol] = []
    var isPulsing: Bool { pulse.animation(forKey: "pulse") != nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(pulse)
        pulse.addSublayer(halo); pulse.addSublayer(dot)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: NSColor, style: Style, playing: Bool, reduceMotion: Bool) {
        if self.style != style { pulse.removeAnimation(forKey: "pulse") }
        self.style = style; self.playing = playing; reduced = reduceMotion
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dot.fillColor = color.cgColor
        halo.fillColor = color.withAlphaComponent(0.25).cgColor
        halo.isHidden = style == .status
        pulse.shadowColor = color.cgColor
        // Step cues keep the circular halo without an outer blurred shadow.
        pulse.shadowOpacity = style == .status ? 0.8 : 0
        pulse.shadowRadius = style == .status ? 3 : 6
        pulse.shadowOffset = .zero
        CATransaction.commit()
        needsLayout = true
        synchronizePlayback()
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pulse.frame = bounds
        dot.frame = pulse.bounds; halo.frame = pulse.bounds
        // Keep the 22 pt halo and its 1.15× pulse inside the 28 pt drawing surface.
        let core = style == .step
            ? CGRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14)
            : pulse.bounds
        dot.path = CGPath(ellipseIn: core, transform: nil)
        halo.path = CGPath(ellipseIn: core.insetBy(dx: -4, dy: -4), transform: nil)
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name == NSWindow.willCloseNotification { self?.pulse.removeAnimation(forKey: "pulse") }
                        else { self?.synchronizePlayback() }
                    }
                })
            }
        }
        synchronizePlayback()
    }
    override func viewDidHide() { super.viewDidHide(); synchronizePlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); synchronizePlayback() }
    private func synchronizePlayback() {
        guard playing, !reduced, !isHiddenOrHasHiddenAncestor, let window,
              window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible), !NSApp.isHidden else {
            pulse.removeAnimation(forKey: "pulse")
            return
        }
        guard !isPulsing else { return }
        let animation = CABasicAnimation(keyPath: style == .status ? "opacity" : "transform.scale")
        animation.fromValue = 1
        animation.toValue = style == .status ? 0.35 : 1.15
        animation.duration = 1.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.add(animation, forKey: "pulse")
    }
    func stop() { playing = false; synchronizePlayback() }
}
