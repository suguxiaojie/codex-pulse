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

struct IslandMascotOneShot: Equatable {
    enum Kind { case none, reply, done, fail }
    var kind: Kind = .none
    var startedAt = Date.distantPast
}

struct IslandMascotMotionFrame: Equatable {
    let orbitDegrees: Double
    let toolDegrees: Double
    let breathingScale: CGFloat
    let lookX: CGFloat

    static func frame(mood: IslandMascotMood, time: TimeInterval, animated: Bool, reduceMotion: Bool) -> Self {
        let moving = animated && !reduceMotion
        let time = moving ? time : 0
        let running = mood == .think || mood == .tool
        let period = running ? 3.2 : 5.0
        return Self(orbitDegrees: time.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360,
            toolDegrees: time.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360,
            breathingScale: moving && (running || mood == .idle) ? 1 + 0.035 * sin(time * .pi * 2 / period) : 1,
            lookX: mood == .think ? 1.4 + (moving ? sin(time * .pi * 2 / 3.6) * 1.3 : 0) : 0)
    }
    static func gaze(_ offset: CGSize, mood: IslandMascotMood, animated: Bool, reduceMotion: Bool) -> CGSize {
        animated && !reduceMotion && mood != .fail ? offset : .zero
    }
    static func eyeScale(mood: IslandMascotMood, closed: Bool, animated: Bool, reduceMotion: Bool) -> CGFloat {
        (mood == .tool ? 0.45 : 1) * (closed && animated && !reduceMotion ? 0.12 : 1)
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

@MainActor final class IslandMascotBlink: ObservableObject {
    @Published private(set) var closed = false
    private var work: Task<Void, Never>?
    var isRunning: Bool { work != nil }
    func update(active: Bool) {
        guard active else { work?.cancel(); work = nil; closed = false; return }
        guard work == nil else { return }
        work = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(Double.random(in: 3...6) * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.closed = true
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
                self?.closed = false
            }
        }
    }
    deinit { work?.cancel() }
}

private struct MascotContextKey: EnvironmentKey { static let defaultValue: IslandMascotContext? = nil }
private struct MascotSerialKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var islandMascotContext: IslandMascotContext? {
        get { self[MascotContextKey.self] } set { self[MascotContextKey.self] = newValue }
    }
    var islandMascotSerial: Int {
        get { self[MascotSerialKey.self] } set { self[MascotSerialKey.self] = newValue }
    }
}

struct IslandMascotView: View {
    let mood: IslandMascotMood
    let size: CGFloat
    let animated: Bool
    let reduceMotion: Bool
    var gaze: CGSize = .zero
    var oneShot = IslandMascotOneShot()
    @StateObject private var blink = IslandMascotBlink()
    private var moving: Bool { animated && !reduceMotion }
    private var blinks: Bool { moving && [.think, .tool, .approve].contains(mood) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { clock in
            let time = moving ? clock.date.timeIntervalSinceReferenceDate : 0
            let motion = IslandMascotMotionFrame.frame(mood: mood, time: time, animated: animated, reduceMotion: reduceMotion)
            let elapsed = moving ? clock.date.timeIntervalSince(oneShot.startedAt) : 10
            let pulse = max(0, 1 - elapsed / 0.8)
            let jump = oneShot.kind == .done && elapsed >= 0 && elapsed < 0.65 ? -sin(elapsed / 0.65 * .pi) * size * 0.18 : 0
            let shake = oneShot.kind == .fail && elapsed >= 0 && elapsed < 0.45 ? sin(elapsed * 65) * pulse * size * 0.1 : 0
            ZStack {
                Circle().fill(RadialGradient(colors: [.white, mood.colors.0, mood.colors.1],
                    center: UnitPoint(x: 0.36, y: 0.30), startRadius: 0, endRadius: size * 0.72))
                    .shadow(color: mood.colors.0.opacity(0.35), radius: size * 0.16)
                if mood == .think {
                    Circle().fill(.white).frame(width: size * 0.08, height: size * 0.08)
                        .offset(x: size * 0.5)
                        .rotationEffect(.degrees(motion.orbitDegrees))
                } else if mood == .tool {
                    Circle().trim(from: 0, to: 0.25)
                        .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                        .frame(width: size * 0.70, height: size * 0.70)
                        .rotationEffect(.degrees(motion.toolDegrees))
                }
                if mood == .approve {
                    let phase = moving ? time.truncatingRemainder(dividingBy: 1.4) / 1.4 : 0
                    Circle().stroke(mood.colors.0.opacity(moving ? (1 - phase) * 0.65 : 0.35), lineWidth: 1)
                        .scaleEffect(1 + phase * 0.35)
                }
                eyes(time: time)
                if mood == .reply {
                    Text("?").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(mood.colors.0)
                        .offset(x: size * 0.43, y: -size * 0.4 + (oneShot.kind == .reply ? -sin(max(0, elapsed) * 8) * pulse * size * 0.07 : 0))
                }
                if oneShot.kind == .done && moving && elapsed >= 0 && elapsed < 0.8 {
                    ForEach(0..<5) { index in
                        let angle = Double(index) * .pi * 2 / 5 - .pi / 2
                        Circle().fill([Color.green, .yellow, .cyan, .pink, .orange][index])
                            .frame(width: size * 0.09, height: size * 0.09)
                            .offset(x: cos(angle) * size * elapsed, y: sin(angle) * size * elapsed)
                            .opacity(pulse)
                    }
                }
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(mood == .reply ? -9 : 0))
            .scaleEffect(motion.breathingScale)
            .offset(x: shake, y: jump)
        }
        .frame(width: size, height: size)
        .animation(moving ? .easeInOut(duration: 0.3) : nil, value: mood)
        .onAppear { blink.update(active: blinks) }
        .onChange(of: blinks) { _ in blink.update(active: blinks) }
        .onDisappear { blink.update(active: false) }
        .accessibilityHidden(true)
    }
    private func eyes(time: TimeInterval) -> some View {
        let eyeScale = size < 22 ? 1.15 : 1.0
        let width = size * 0.09 * eyeScale
        let height = size * 0.17 * eyeScale
        let look = IslandMascotMotionFrame.gaze(gaze, mood: mood, animated: animated, reduceMotion: reduceMotion)
        let ownX = IslandMascotMotionFrame.frame(mood: mood, time: time, animated: animated, reduceMotion: reduceMotion).lookX
        return HStack(spacing: size * 0.21 - width) {
            ForEach(0..<2) { _ in
                Group {
                    if mood == .fail {
                        Image(systemName: "xmark").font(.system(size: height, weight: .heavy))
                    } else if mood == .done || mood == .idle {
                        MascotEyeArc(smiling: mood == .done).stroke(style: StrokeStyle(lineWidth: max(1, size * 0.025), lineCap: .round))
                    } else {
                        Capsule().frame(height: mood == .approve ? width : height)
                    }
                }
                .frame(width: width, height: height)
                .scaleEffect(x: 1, y: IslandMascotMotionFrame.eyeScale(mood: mood, closed: blink.closed,
                    animated: animated, reduceMotion: reduceMotion))
            }
        }
        .foregroundStyle(Color(red: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x38 / 255.0))
        .offset(x: (look.width + ownX) * size / 100, y: (look.height + (mood == .think ? -1.4 : 0)) * size / 100)
        .animation(moving ? .spring(response: 0.35, dampingFraction: 0.75) : nil, value: gaze)
        .animation(moving ? .spring(response: 0.12, dampingFraction: 0.6) : nil, value: blink.closed)
    }
}

private struct MascotEyeArc: Shape {
    var smiling: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.midX, y: smiling ? 0 : rect.maxY * 0.85))
        }
    }
}

struct IslandSessionMascot: View {
    let row: ActivitySessionSnapshot
    let size: CGFloat
    let animated: Bool
    let reduceMotion: Bool
    var replyCueActive = false
    @Environment(\.islandMascotContext) private var context
    @Environment(\.islandMascotSerial) private var serial
    @Environment(\.islandGlassActive) private var activeSurface
    @State private var oneShot = IslandMascotOneShot()
    @State private var actionOwner: String?
    var body: some View {
        Group {
            if let context {
                MascotObservedView(context: context, mood: .mood(for: row), size: size,
                    animated: animated, reduceMotion: reduceMotion, oneShot: oneShot)
            } else {
                IslandMascotView(mood: .mood(for: row), size: size, animated: animated, reduceMotion: reduceMotion)
            }
        }
        .onAppear { update() }
        .onChange(of: row) { _ in update() }
        .onChange(of: serial) { _ in update() }
        .onChange(of: replyCueActive) { _ in update() }
        .onChange(of: animated) { _ in if animated { update() } else { oneShot = .init() } }
        .onChange(of: reduceMotion) { _ in if reduceMotion { oneShot = .init() } }
    }
    private func update() {
        guard activeSurface, let context else { return }
        let mood = IslandMascotMood.mood(for: row)
        let owner = row.id + "/" + (row.turnID ?? "")
        if actionOwner != owner || (oneShot.kind == .done && mood != .done)
            || (oneShot.kind == .reply && mood != .reply) || (oneShot.kind == .fail && mood != .fail) {
            oneShot = .init(); actionOwner = owner
        }
        var kind = IslandMascotOneShot.Kind.none
        if mood == .done && context.claimCompletion(row, serial: serial) { kind = .done }
        if mood == .fail && context.claimFailure(row) { kind = .fail }
        if mood == .reply && replyCueActive && context.claimReply(row) { kind = .reply }
        if kind != .none && animated && !reduceMotion { oneShot = .init(kind: kind, startedAt: Date()) }
    }
}

private struct MascotObservedView: View {
    @ObservedObject var context: IslandMascotContext
    let mood: IslandMascotMood
    let size: CGFloat
    let animated: Bool
    let reduceMotion: Bool
    var oneShot = IslandMascotOneShot()
    var body: some View {
        IslandMascotView(mood: mood, size: size, animated: animated, reduceMotion: reduceMotion,
            gaze: context.gaze, oneShot: oneShot)
    }
}

// The original quota view lives outside the allowed edit scope; retain its layout here with an idle mascot.
struct IslandMascotCompactQuotaContent: View {
    @ObservedObject var model: ActivityIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var leading: some View {
        HStack(spacing: 6) {
            MascotObservedView(context: model.mascotContext, mood: .idle, size: 18,
                animated: model.playbackVisible && model.presentation == .compact,
                reduceMotion: reduceMotion || model.reduceMotionOverride)
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
