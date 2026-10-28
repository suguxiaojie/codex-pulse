import AppKit
import SwiftUI

enum IslandMascotMood: Equatable {
    case think, tool, approve, reply, done, fail, idle

    static func mood(for row: ActivitySessionSnapshot?) -> Self {
        guard let row, row.endReason != .cancelled else { return .idle }
        switch row.phase {
        case .starting, .working: return .think
        case .usingTool: return .tool
        case .waitingApproval: return row.waitReason == .userInput ? .reply : .approve
        case .completed: return .done
        case .failed: return .fail
        case .ended: return .idle
        }
    }
    var middleColor: Color { colors.0 }
    var colors: (Color, Color) {
        let values: (UInt32, UInt32)
        switch self {
        case .think: values = (0x9AA8FF, 0x4B3CB0)
        case .tool: values = (0x62D0FF, 0x1D5F9A)
        case .approve, .reply: values = (0xFFB340, 0xA8520E)
        case .done: values = (0x4CD47A, 0x16733A)
        case .fail: values = (0xFF5A4E, 0x8E1C16)
        case .idle: values = (0xA2A8B6, 0x3C4150)
        }
        func color(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
        }
        return (color(values.0), color(values.1))
    }
}

enum IslandMascotGeometry {
    // Normalized to the design's 100 pt canvas; scale by size / 100 at the view boundary.
    static func gazeOffset(pointer: CGPoint, islandRect: CGRect) -> CGSize {
        guard !islandRect.isEmpty, pointer.x.isFinite, pointer.y.isFinite else { return .zero }
        let dx = max(islandRect.minX - pointer.x, 0, pointer.x - islandRect.maxX)
        let dy = max(islandRect.minY - pointer.y, 0, pointer.y - islandRect.maxY)
        guard hypot(dx, dy) <= 240 else { return .zero }
        let x = pointer.x - islandRect.midX, y = pointer.y - islandRect.midY
        let length = hypot(x, y)
        guard length > 0 else { return .zero }
        let amount = min(1, length / 120) * 9 * 0.35
        return CGSize(width: x / length * amount, height: -y / length * amount)
    }
}

/// Model-owned history survives SwiftUI identity changes and compact/expanded handoffs.
@MainActor final class IslandMascotContext: ObservableObject {
    @Published private(set) var gaze: CGSize = .zero
    private var local: Any?
    private var global: Any?
    private var lastMouseUpdate = Date.distantPast
    private var islandRect = CGRect.zero
    private(set) var enabled = false
    var monitorCount: Int { (local == nil ? 0 : 1) + (global == nil ? 0 : 1) }
    private var completionOwner: String?
    private var completionSerial = 0
    private var playedCompletionSerial = 0
    private var replies: [String: Set<String>] = [:]
    private var failures: Set<String> = []
    private func identity(_ row: ActivitySessionSnapshot) -> String { row.id + "/" + (row.turnID ?? "") }

    func noteCompletion(_ row: ActivitySessionSnapshot, serial: Int, playable: Bool) {
        completionOwner = identity(row); completionSerial = serial
        if !playable { playedCompletionSerial = max(playedCompletionSerial, serial) }
    }
    func claimCompletion(_ row: ActivitySessionSnapshot, serial: Int) -> Bool {
        guard !row.isRetainedReceipt, identity(row) == completionOwner, serial > 0,
              serial == completionSerial, serial > playedCompletionSerial else { return false }
        playedCompletionSerial = serial
        return true
    }
    func claimReply(_ row: ActivitySessionSnapshot) -> Bool {
        let key = identity(row)
        let ids = row.replyRequestIDs.isEmpty ? Set(["fallback"]) : row.replyRequestIDs
        let seen = replies[key] ?? []
        replies[key] = seen.union(ids)
        return !ids.subtracting(seen).isEmpty && !seen.contains("fallback")
    }
    func claimFailure(_ row: ActivitySessionSnapshot) -> Bool { failures.insert(identity(row)).inserted }

    func update(visible: Bool, reduceMotion: Bool, islandRect: CGRect) {
        self.islandRect = islandRect
        let next = visible && !reduceMotion
        guard enabled != next else { return }
        enabled = next
        if next {
            local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.mouseMoved(); return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMoved() }
            }
        } else {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
            local = nil; global = nil; gaze = .zero
        }
    }
    private func mouseMoved() {
        guard enabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMouseUpdate) >= 1.0 / 30 else { return }
        lastMouseUpdate = now
        let next = IslandMascotGeometry.gazeOffset(pointer: NSEvent.mouseLocation, islandRect: islandRect)
        if gaze != next { gaze = next }
    }
    deinit {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
    }
}

private struct MascotContextKey: EnvironmentKey { static let defaultValue: IslandMascotContext? = nil }
private struct MascotSerialKey: EnvironmentKey { static let defaultValue = 0 }
private struct ClawdCardsAnimateKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var islandMascotContext: IslandMascotContext? {
        get { self[MascotContextKey.self] } set { self[MascotContextKey.self] = newValue }
    }
    var islandMascotSerial: Int {
        get { self[MascotSerialKey.self] } set { self[MascotSerialKey.self] = newValue }
    }
    /// The "显示桌宠" preference: when off, card Clawds stay a still avatar.
    var islandClawdCardsAnimate: Bool {
        get { self[ClawdCardsAnimateKey.self] } set { self[ClawdCardsAnimateKey.self] = newValue }
    }

}

// Card slots play the same pre-rendered Core Animation clips as the compact island;
// unfocused, preview, hidden and Reduce Motion cards fall back to the still avatar.
struct IslandMascotView: View {
    let mood: IslandMascotMood
    let size: CGFloat
    let animated: Bool
    let reduceMotion: Bool
    var species = IslandPetSpecies.clawd
    @Environment(\.islandClawdCardsAnimate) private var cardsAnimate
    var body: some View {
        Group {
            if animated && cardsAnimate && !reduceMotion {
                IslandClawdBadge(mood: mood, pixel: size / 14, reduceMotion: false, playing: true, species: species)
            } else {
                IslandClawdStill(mood: mood, pixel: size / 14, species: species)
            }
        }
        .frame(width: size, height: size)
    }
}

struct IslandSessionMascot: View {
    let row: ActivitySessionSnapshot
    let size: CGFloat
    let animated: Bool
    let reduceMotion: Bool
    var replyCueActive = false
    var body: some View {
        IslandMascotView(mood: .mood(for: row), size: size, animated: animated, reduceMotion: reduceMotion,
                         species: IslandPetSpecies(provider: row.provider))
    }
}

struct IslandMascotCompactQuotaContent: View {
    @ObservedObject var model: ActivityIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var leading: some View {
        HStack(spacing: 6) {
            if model.clawdEnabled {
                IslandClawdBadge(mood: .idle, pixel: model.compactClawdPixel,
                    reduceMotion: reduceMotion || model.reduceMotionOverride,
                    playing: model.clawdEnabled && model.playbackVisible, species: model.idlePetSpecies)
                    .frame(width: model.compactClawdPixel * 14, height: model.compactClawdPixel * 12)
                    .accessibilityHidden(true)
            }
            Text(model.compactQuotaPercent).monospacedDigit().fixedSize().foregroundStyle(FloatingSurfaceTheme.accent())
        }
    }
    private var trailing: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text(model.idleSummary)
                if !model.sessions.isEmpty {
                    let done = model.sessions.filter { $0.phase == .completed }.count
                    ZStack(alignment: .trailing) {
                        Text("\(model.sessions.count) 会话").hidden()
                        Text("\(done) 完成").hidden()
                        Text(model.showsCompletedStatistic && done > 0 ? "\(done) 完成" : "\(model.sessions.count) 会话")
                    }.foregroundStyle(FloatingSurfaceTheme.secondary()).monospacedDigit().fixedSize()
                }
            }.fixedSize()
            Text(model.idleSummary).fixedSize()
        }.font(.system(size: 12, weight: .semibold))
    }
    var body: some View {
        let width = model.metrics.compactRect.width, gap = model.metrics.hardwareGap
        Button { model.onOpenUsage?() } label: {
            Group {
                if gap > 0 {
                    let side = max(0, (width - 40 - gap - 16) / 2)
                    HStack(spacing: 0) {
                        leading.frame(width: side, alignment: .leading)
                        Color.clear.frame(width: gap + 16)
                        trailing.frame(width: side, alignment: .trailing)
                    }
                } else { HStack { leading; Spacer(minLength: 0); trailing } }
            }.padding(.horizontal, 20).frame(width: width, height: model.metrics.compactRect.height)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).font(FloatingSurfaceTypography.action)
            .accessibilityLabel(model.compactQuotaAccessibilitySummary)
            .help("悬停展开灵动岛，点击查看额度与用量")
            .accessibilityHint("悬停展开灵动岛，点击查看额度与用量")
    }
}

/// Compact-only contour. Core Animation owns the pulse; SwiftUI has no frame clock.
struct IslandCompactGlow: NSViewRepresentable {
    var mood: IslandMascotMood
    var reduceMotion: Bool
    var playing: Bool
    func makeNSView(context: Context) -> IslandCompactGlowView { IslandCompactGlowView() }
    func updateNSView(_ view: IslandCompactGlowView, context: Context) {
        view.apply(state: IslandClawdBadgeState(mood: mood), reduceMotion: reduceMotion, playing: playing)
    }
}

final class IslandCompactGlowView: NSView {
    override var isFlipped: Bool { true }
    private let stroke = CAShapeLayer()
    private var state: IslandClawdBadgeState?
    private var reduced = false
    private var playing = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        stroke.fillColor = nil
        stroke.lineWidth = 1.5
        layer?.addSublayer(stroke)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stroke.frame = bounds
        stroke.path = IslandNotchShape(bottomRadius: 13).path(in: bounds.insetBy(dx: 1, dy: 1)).cgPath
        CATransaction.commit()
    }
    func apply(state: IslandClawdBadgeState, reduceMotion: Bool, playing: Bool) {
        guard self.state != state || reduced != reduceMotion || self.playing != playing else { return }
        self.state = state; reduced = reduceMotion; self.playing = playing
        stroke.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stroke.strokeColor = IslandClawdGlow.color(for: state)?.cgColor
        stroke.opacity = playing ? IslandClawdGlow.restingOpacity(for: state, reduceMotion: reduceMotion) : 0
        CATransaction.commit()
        if playing && !reduceMotion, let animation = IslandClawdGlow.animation(for: state, reduceMotion: false) {
            stroke.add(animation, forKey: "clawdGlow")
        }
    }
}
