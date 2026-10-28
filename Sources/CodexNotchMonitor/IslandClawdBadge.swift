import AppKit
import QuartzCore
import SwiftUI

// In-island Clawd: lives in the compact island's left wing instead of hanging below it.
// Every pose is pre-rendered once per (state, pixel, scale, gaze) and played by Core Animation,
// so the app does no per-frame work; state changes are the only time this code runs.

/// What the in-island Clawd is showing. `start` is a one-shot played when work begins after idle.
enum IslandClawdBadgeState: Equatable, Hashable {
    case idle, start, think, tool, approve, reply, done, fail

    init(mood: IslandMascotMood) {
        switch mood {
        case .idle: self = .idle
        case .think: self = .think
        case .tool: self = .tool
        case .approve: self = .approve
        case .reply: self = .reply
        case .done: self = .done
        case .fail: self = .fail
        }
    }
}

/// Which pet stands in for the task's client: Clawd for Claude Code, the Prompt terminal for Codex.
enum IslandPetSpecies: Hashable {
    case clawd, codex
    init(provider: String) { self = provider == "Claude Code" ? .clawd : .codex }
}

/// One frame of the Codex pet: a small terminal whose face is the ">_" prompt and whose cursor is its mouth.
struct IslandCodexFrame: Equatable {
    enum Face: Equatable { case sleep, prompt(cursor: Bool), alert(cursor: Bool), code(Int), check, cross }
    var face: Face
    var liftLeft = false
    var liftRight = false
    var dots = 0
    var bang = false
    /// `true` shows the cursor inside the speech bubble, `false` the bubble alone.
    var speech: Bool?
}

struct IslandCodexClip {
    var frames: [IslandCodexFrame]
    var fps: Double
    var loops: Bool
    var duration: CFTimeInterval { Double(frames.count) / fps }
}

/// The same eight states as Clawd, timed so state changes and reactions line up between the two pets.
enum IslandCodexClips {
    static func clip(_ state: IslandClawdBadgeState) -> IslandCodexClip {
        switch state {
        case .idle:
            return .init(frames: [.init(face: .sleep)], fps: 1, loops: true)
        case .start:
            return .init(frames: [.init(face: .sleep), .init(face: .prompt(cursor: true))], fps: 3, loops: false)
        case .think:
            // The cursor blinks while the ellipsis fills, as if waiting on the model.
            return .init(frames: [.init(face: .prompt(cursor: true)), .init(face: .prompt(cursor: false), dots: 1),
                                  .init(face: .prompt(cursor: true), dots: 2), .init(face: .prompt(cursor: false), dots: 3),
                                  .init(face: .prompt(cursor: true), dots: 3), .init(face: .prompt(cursor: false))],
                         fps: 4, loops: true)
        case .tool:
            // Output scrolls on the screen while the feet shuffle.
            return .init(frames: [.init(face: .code(0), liftLeft: true), .init(face: .code(1), liftRight: true),
                                  .init(face: .code(2), liftLeft: true), .init(face: .code(0), liftRight: true),
                                  .init(face: .code(1), liftLeft: true), .init(face: .code(2), liftRight: true)],
                         fps: 8, loops: true)
        case .approve:
            return .init(frames: [.init(face: .alert(cursor: true), bang: true), .init(face: .alert(cursor: true))],
                         fps: 4, loops: true)
        case .reply:
            return .init(frames: [.init(face: .alert(cursor: true), speech: true), .init(face: .alert(cursor: false), speech: false)],
                         fps: 2, loops: true)
        case .done:
            return .init(frames: [.init(face: .check), .init(face: .check, liftLeft: true, liftRight: true)], fps: 4, loops: true)
        case .fail:
            return .init(frames: [.init(face: .cross)], fps: 1, loops: true)
        }
    }

    /// Single frame for static card avatars; no props, expression only.
    static func still(_ state: IslandClawdBadgeState) -> IslandCodexFrame {
        switch state {
        case .idle: return .init(face: .sleep)
        case .start, .think: return .init(face: .prompt(cursor: true))
        case .tool: return .init(face: .code(1))
        case .approve, .reply: return .init(face: .alert(cursor: true))
        case .done: return .init(face: .check)
        case .fail: return .init(face: .cross)
        }
    }
}

/// Extra sprite pieces the badge draws on top of the shared `IslandClawdSprite` body.
struct IslandClawdBadgeProps: Equatable {
    enum Hands: Equatable { case none, rest, left, right, chin }
    var keyboard = false
    var hands = Hands.none
    var dots = 0
    var bulb = false
    /// `true` shows the cursor inside the empty speech bubble, `false` the bubble alone.
    var speech: Bool?
    var wrench: CGFloat?
}

struct IslandClawdBadgeFrame: Equatable {
    var pose: IslandClawdPose
    var props = IslandClawdBadgeProps()
}

struct IslandClawdBadgeClip {
    var frames: [IslandClawdBadgeFrame]
    var fps: Double
    var loops: Bool
    var duration: CFTimeInterval { Double(frames.count) / fps }
}

enum IslandClawdBadgeClips {
    /// How long done/fail stay up before Clawd settles back to the idle pose.
    static let reactionHold: CFTimeInterval = 2.2

    static func pose(_ eyes: IslandClawdPose.Eyes, arms: IslandClawdPose.Arms = .down, raised: Bool = false,
                     look: CGSize = .zero, legs: [Bool] = [false, false, false, false], tucked: Bool = false,
                     squash: CGFloat = 1) -> IslandClawdPose {
        var pose = IslandClawdPose(mood: .think, arms: arms)
        pose.eyes = eyes; pose.armRaised = raised; pose.look = look
        pose.legLift = legs; pose.legsTucked = tucked; pose.squashY = squash
        return pose
    }

    static func clip(_ state: IslandClawdBadgeState) -> IslandClawdBadgeClip {
        let l = [true, false, true, false], r = [false, true, false, true], n = [false, false, false, false]
        switch state {
        case .idle:
            return .init(frames: [.init(pose: pose(.closed, tucked: true))], fps: 1, loops: true)
        case .start:
            return .init(frames: [.init(pose: pose(.closed, tucked: true)), .init(pose: pose(.wide, arms: .side))],
                         fps: 3, loops: false)
        case .think:
            // A short typing burst, then a long chin-on-hand think with the ellipsis filling, then a light bulb.
            let down = CGSize(width: 0, height: 0.4), up = CGSize(width: 0.3, height: -0.4)
            func typing(_ hands: IslandClawdBadgeProps.Hands, tap: Bool) -> IslandClawdBadgeFrame {
                .init(pose: pose(.open, look: down, tucked: true, squash: tap ? 0.96 : 1),
                      props: .init(keyboard: true, hands: hands))
            }
            func thinking(dots: Int, blink: Bool = false) -> IslandClawdBadgeFrame {
                .init(pose: pose(blink ? .closed : .open, look: up, tucked: true),
                      props: .init(keyboard: true, hands: .chin, dots: dots))
            }
            let idea = IslandClawdBadgeFrame(pose: pose(.wide, look: CGSize(width: 0, height: -0.3), tucked: true),
                                             props: .init(keyboard: true, hands: .rest, bulb: true))
            return .init(frames: [
                typing(.left, tap: true), typing(.rest, tap: false), typing(.right, tap: true),
                typing(.rest, tap: false), typing(.left, tap: true), typing(.right, tap: true),
                thinking(dots: 0), thinking(dots: 1), thinking(dots: 1), thinking(dots: 2),
                thinking(dots: 2, blink: true), thinking(dots: 3), thinking(dots: 3), thinking(dots: 3),
                idea, idea,
            ], fps: 6, loops: true)
        case .tool:
            return .init(frames: [
                .init(pose: pose(.squint, legs: l), props: .init(wrench: 0)),
                .init(pose: pose(.squint, legs: n), props: .init(wrench: -0.8)),
                .init(pose: pose(.squint, legs: r), props: .init(wrench: 0)),
                .init(pose: pose(.squint, legs: n), props: .init(wrench: -0.8)),
            ], fps: 8, loops: true)
        case .approve:
            return .init(frames: [.init(pose: pose(.wide, arms: .up, raised: true)), .init(pose: pose(.wide, arms: .up))],
                         fps: 4, loops: true)
        case .reply:
            let look = CGSize(width: -0.4, height: 0)
            return .init(frames: [.init(pose: pose(.wide, look: look), props: .init(speech: true)),
                                  .init(pose: pose(.wide, look: look), props: .init(speech: false))],
                         fps: 2, loops: true)
        case .done:
            return .init(frames: [.init(pose: pose(.happy, arms: .up)),
                                  .init(pose: pose(.happy, arms: .up, raised: true, legs: [true, false, false, true]))],
                         fps: 4, loops: true)
        case .fail:
            return .init(frames: [.init(pose: pose(.cross, squash: 0.92)),
                                  .init(pose: pose(.cross, look: CGSize(width: 0, height: 0.2), squash: 0.92))],
                         fps: 3, loops: true)
        }
    }

    /// Single frame for static card avatars; no props, expression only.
    static func still(_ state: IslandClawdBadgeState) -> IslandClawdBadgeFrame {
        switch state {
        case .idle: return .init(pose: pose(.closed, tucked: true))
        case .start, .think: return .init(pose: pose(.open))
        case .tool: return .init(pose: pose(.squint))
        case .approve: return .init(pose: pose(.wide, arms: .up))
        case .reply: return .init(pose: pose(.wide, look: CGSize(width: -0.4, height: 0)))
        case .done: return .init(pose: pose(.happy, arms: .up))
        case .fail: return .init(pose: pose(.cross, squash: 0.92))
        }
    }
}

@MainActor
enum IslandClawdBadgeRenderer {
    /// Sprite grid of one frame, in sprite pixels; the feet sit at `feet`.
    static let grid = CGSize(width: 14, height: 12)
    static let feet = CGPoint(x: 7, y: 10)

    static func size(pixel: CGFloat) -> CGSize { CGSize(width: grid.width * pixel, height: grid.height * pixel) }

    private struct Key: Hashable {
        var state: IslandClawdBadgeState; var pixel: CGFloat; var scale: CGFloat; var gaze: Int
        var species = IslandPetSpecies.clawd
    }
    private static var cache: [Key: [CGImage]] = [:]
    private static var stillCache: [Key: CGImage] = [:]

    static func images(_ state: IslandClawdBadgeState, pixel: CGFloat, scale: CGFloat, gaze: Int,
                       species: IslandPetSpecies = .clawd) -> [CGImage] {
        let key = Key(state: state, pixel: pixel, scale: scale, gaze: species == .codex ? 0 : gaze, species: species)
        if let hit = cache[key] { return hit }
        let made: [CGImage]
        switch species {
        case .clawd:
            made = IslandClawdBadgeClips.clip(state).frames.compactMap { image(gazing($0, gaze), pixel: pixel, scale: scale) }
        case .codex:
            made = IslandCodexClips.clip(state).frames.compactMap { frame in
                render(pixel: pixel, scale: scale) { drawCodex(frame, pixel: pixel, in: $0) }
            }
        }
        cache[key] = made
        return made
    }

    static func stillImage(_ state: IslandClawdBadgeState, pixel: CGFloat, scale: CGFloat,
                           species: IslandPetSpecies = .clawd) -> CGImage? {
        let key = Key(state: state, pixel: pixel, scale: scale, gaze: 0, species: species)
        if let hit = stillCache[key] { return hit }
        let made: CGImage?
        switch species {
        case .clawd: made = image(IslandClawdBadgeClips.still(state), pixel: pixel, scale: scale)
        case .codex:
            let frame = IslandCodexClips.still(state)
            made = render(pixel: pixel, scale: scale) { drawCodex(frame, pixel: pixel, in: $0) }
        }
        stillCache[key] = made
        return made
    }

    /// Clip timing for whichever pet is shown, so the view schedules both identically.
    static func timing(_ state: IslandClawdBadgeState, species: IslandPetSpecies) -> (duration: CFTimeInterval, loops: Bool) {
        switch species {
        case .clawd: let clip = IslandClawdBadgeClips.clip(state); return (clip.duration, clip.loops)
        case .codex: let clip = IslandCodexClips.clip(state); return (clip.duration, clip.loops)
        }
    }

    /// Discrete gaze: open eyes shift a fraction of a sprite pixel left or right.
    private static func gazing(_ frame: IslandClawdBadgeFrame, _ gaze: Int) -> IslandClawdBadgeFrame {
        guard gaze != 0, frame.pose.eyes == .open || frame.pose.eyes == .wide else { return frame }
        var copy = frame
        copy.pose.look.width += CGFloat(max(-1, min(1, gaze))) * 0.3
        return copy
    }

    static func image(_ frame: IslandClawdBadgeFrame, pixel: CGFloat, scale: CGFloat) -> CGImage? {
        render(pixel: pixel, scale: scale) { draw(frame, pixel: pixel, in: $0) }
    }

    private static func render(pixel: CGFloat, scale: CGFloat, _ body: (CGContext) -> Void) -> CGImage? {
        let size = size(pixel: pixel)
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        // The sprite is authored y-down with the feet at the origin.
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        context.translateBy(x: feet.x * pixel, y: feet.y * pixel)
        body(context)
        return context.makeImage()
    }

    /// The Codex pet, authored y-down with the feet at the origin: an 11×7 terminal on two feet.
    static func drawCodex(_ frame: IslandCodexFrame, pixel px: CGFloat, in context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.setShouldAntialias(false)
        func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32) {
            IslandClawdSprite.fillPixelBlock(CGRect(x: x * px, y: y * px, width: w * px, height: h * px), color: srgb(hex), in: context)
        }
        let failed = frame.face == .cross
        let body: UInt32 = failed ? 0xB9C0CA : 0xE9EEF6, feet: UInt32 = 0x9FB0C8
        let ice: UInt32 = 0x8FB4FF, amber: UInt32 = 0xFFB340
        fill(-3.5, -1, 2, frame.liftLeft ? 0.5 : 1, feet)
        fill(1.5, -1, 2, frame.liftRight ? 0.5 : 1, feet)
        fill(-4.5, -8, 9, 1, body); fill(-5.5, -7, 11, 5, body); fill(-4.5, -2, 9, 1, body)
        fill(-4.5, -7, 9, 5, 0x162030)
        func chevron(_ hex: UInt32) { fill(-3.5, -6, 1, 1, hex); fill(-2.5, -5, 1, 1, hex); fill(-3.5, -4, 1, 1, hex) }
        switch frame.face {
        case .sleep:
            chevron(0x4E6A9A)
        case .prompt(let cursor):
            chevron(ice)
            if cursor { fill(-0.5, -4, 2, 1, ice) }
        case .alert(let cursor):
            chevron(ice)
            if cursor { fill(-0.5, -4, 2.5, 1, amber) }
        case .code(let offset):
            chevron(ice)
            let widths: [CGFloat] = [3, 2, 2.5]
            for row in 0..<3 { fill(-0.5, -6.4 + CGFloat(row) * 1.4, widths[(row + offset) % 3], 0.6, 0x5D7FB8) }
        case .check:
            for (x, y) in [(-2.5, -4.0), (-1.5, -3.0), (-0.5, -4.0), (0.5, -5.0), (1.5, -6.0)] { fill(x, y, 1, 1, 0x7BE3A0) }
        case .cross:
            for (x, y) in [(-1.5, -6.0), (0.5, -6.0), (-0.5, -5.0), (-1.5, -4.0), (0.5, -4.0)] { fill(x, y, 1, 1, 0xFF7A70) }
        }
        // Props stay inside the 10-pixel headroom of the shared 14×12 grid.
        for dot in 0..<frame.dots { fill(3.2 + CGFloat(dot) * 1.3, -9.6, 0.8, 0.8, 0xC9D6EE) }
        if frame.bang { fill(5.7, -10, 0.8, 1.3, amber); fill(5.7, -8.4, 0.8, 0.6, amber) }
        if let cursor = frame.speech {
            fill(3.2, -10, 3.6, 2, 0xF2F2F2); fill(3.6, -8, 0.8, 0.6, 0xF2F2F2)
            if cursor { fill(4.0, -9.7, 0.35, 1.3, 0x162030) }
        }
    }

    static func draw(_ frame: IslandClawdBadgeFrame, pixel: CGFloat, in context: CGContext) {
        IslandClawdSprite.draw(frame.pose, pixel: pixel, in: context)
        drawProps(frame.props, squash: frame.pose.squashY, pixel: pixel, in: context)
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func drawProps(_ props: IslandClawdBadgeProps, squash sy: CGFloat, pixel px: CGFloat, in context: CGContext) {
        let ox: CGFloat = -5.5, top = IslandClawdSprite.bodyTop
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * px, y: y * sy * px, width: w * px, height: h * sy * px)
        }
        context.saveGState(); defer { context.restoreGState() }
        context.setShouldAntialias(false)
        // Props and hands are flat pixel blocks, like the body.
        func flat(_ r: CGRect, _ color: NSColor) { IslandClawdSprite.fillPixelBlock(r, color: color, in: context) }
        func hand(_ r: CGRect) { flat(r, IslandClawdSprite.color(.arm)) }

        if let lift = props.wrench {
            let tool = srgb(0x9AA4AE)
            flat(rect(ox + 10.2, top + 1.4 + lift, 0.8, 2.6), tool)
            flat(rect(ox + 9.8, top + 0.6 + lift, 1.6, 0.9), tool)
        }
        if props.keyboard {
            flat(rect(ox + 0.4, top + 5.1, 10.2, 1.1), srgb(0x3A3F47))
            for key in 0..<6 { flat(rect(ox + 0.9 + CGFloat(key) * 1.6, top + 5.3, 1.1, 0.45), srgb(0x5B626C)) }
            let lit: Int? = props.hands == .left ? 1 : props.hands == .right ? 4 : nil
            if let lit { flat(rect(ox + 0.9 + CGFloat(lit) * 1.6, top + 5.3, 1.1, 0.45), srgb(0xF2B38F)) }
        }
        switch props.hands {
        case .none: break
        case .rest, .left, .right:
            hand(rect(ox + 1, top + 3, 1, props.hands == .left ? 2.4 : 1.2))
            hand(rect(ox + 9, top + 3, 1, props.hands == .right ? 2.4 : 1.2))
        case .chin:
            hand(rect(ox + 1, top + 3, 1, 1.2))
            hand(rect(ox + 9.1, top + 2.6, 0.9, 2.6))
            hand(rect(ox + 7.6, top + 3.3, 2.4, 0.9))
        }
        for dot in 0..<props.dots { flat(rect(ox + 4 + CGFloat(dot) * 1.5, top - 2, 0.8, 0.8), srgb(0xA3AAB3)) }
        if props.bulb {
            flat(rect(ox + 4.9, top - 3.6, 1.4, 1.4), srgb(0xF6D365))
            flat(rect(ox + 5.2, top - 2.2, 0.8, 0.45), srgb(0x8E959E))
        }
        if let cursor = props.speech {
            let paper = srgb(0xF2F2F2)
            flat(rect(ox + 8.6, top - 3.6, 3.6, 2.3), paper)
            flat(rect(ox + 8.9, top - 1.5, 0.8, 0.8), paper)
            if cursor { flat(rect(ox + 9.4, top - 3.1, 0.35, 1.3), IslandClawdSprite.color(.eye)) }
        }
    }
}

/// Layer-backed view hosting the in-island Clawd. Call `apply` whenever inputs may have changed;
/// it only touches layers when something actually differs.
@MainActor
final class IslandClawdBadgeView: NSView {
    private let sprite = CALayer()
    private var sleepMarks: [CATextLayer] = []
    private var requested: IslandClawdBadgeState?
    private(set) var shown: IslandClawdBadgeState?
    private var pixel: CGFloat = 2
    private(set) var species = IslandPetSpecies.clawd
    private var gaze = 0
    private var reduceMotion = false
    private var playbackRequested = true
    private var windowVisible = true
    private var paused = false
    private var chain: DispatchWorkItem?
    private var occlusionObserver: NSObjectProtocol?

    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { IslandClawdBadgeRenderer.size(pixel: pixel) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        sprite.contentsGravity = .resize
        sprite.actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(sprite)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(mood: IslandMascotMood, pixel: CGFloat, gaze: Int, reduceMotion: Bool, playing: Bool,
               species: IslandPetSpecies = .clawd) {
        let target = IslandClawdBadgeState(mood: mood)
        let restyle = pixel != self.pixel || gaze != self.gaze || reduceMotion != self.reduceMotion || species != self.species
        self.species = species
        if pixel != self.pixel { self.pixel = pixel; invalidateIntrinsicContentSize(); needsLayout = true }
        self.gaze = gaze; self.reduceMotion = reduceMotion
        playbackRequested = playing
        if target != requested {
            let previous = requested
            requested = target
            chain?.cancel(); chain = nil
            switch target {
            case .think, .tool:
                if previous == .idle && !reduceMotion {
                    show(.start)
                    schedule(after: IslandClawdBadgeRenderer.timing(.start, species: species).duration) { $0.show(target) }
                } else {
                    show(target)
                }
            case .done, .fail:
                show(target)
                schedule(after: IslandClawdBadgeClips.reactionHold) { $0.show(.idle) }
            default:
                show(target)
            }
        } else if restyle, let shown {
            show(shown, replayReaction: false)
        }
        updatePause()
    }

    private func schedule(after delay: CFTimeInterval, _ body: @escaping (IslandClawdBadgeView) -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.chain = nil
            body(self)
        }
        chain = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private func show(_ state: IslandClawdBadgeState, replayReaction: Bool = true) {
        shown = state
        let clip = IslandClawdBadgeRenderer.timing(state, species: species)
        let images = IslandClawdBadgeRenderer.images(state, pixel: pixel, scale: backingScale, gaze: gaze, species: species)
        sprite.removeAllAnimations()
        sprite.contentsScale = backingScale
        sprite.setAffineTransform(state == .reply ? CGAffineTransform(rotationAngle: 9 * .pi / 180) : .identity)
        let animate = !reduceMotion && images.count > 1
        sprite.contents = animate ? images.first : (clip.loops ? images.first : images.last)
        if animate {
            let frames = CAKeyframeAnimation(keyPath: "contents")
            frames.values = images
            frames.calculationMode = .discrete
            frames.keyTimes = (0...images.count).map { NSNumber(value: Double($0) / Double(images.count)) }
            frames.duration = clip.duration
            frames.repeatCount = clip.loops ? .infinity : 1
            frames.fillMode = .forwards
            frames.isRemovedOnCompletion = clip.loops
            sprite.add(frames, forKey: "frames")
        }
        if animate && replayReaction { addReaction(for: state) }
        updateSleepMarks(visible: state == .idle && !reduceMotion)
    }

    /// One-shot body motion: done hops twice by about 2 pt, fail shakes once and settles 0.5 pt lower.
    private func addReaction(for state: IslandClawdBadgeState) {
        switch state {
        case .done:
            let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
            hop.values = [0, 2.4, -0.5, 0]
            hop.keyTimes = [0, 0.4, 0.7, 1]
            hop.duration = 0.7
            hop.repeatCount = 2
            sprite.add(hop, forKey: "reaction")
        case .fail:
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -1, 1, -0.5, 0]
            shake.duration = 0.6
            sprite.add(shake, forKey: "reaction")
        default:
            break
        }
    }

    private func updateSleepMarks(visible: Bool) {
        sleepMarks.forEach { $0.removeFromSuperlayer() }
        sleepMarks.removeAll()
        guard visible else { return }
        let size = max(7, pixel * 3.2)
        for index in 0..<2 {
            let mark = CATextLayer()
            mark.string = "z"
            mark.font = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            mark.fontSize = size
            mark.foregroundColor = NSColor(white: 0.62, alpha: 1).cgColor
            mark.contentsScale = backingScale
            mark.alignmentMode = .center
            mark.frame = CGRect(x: bounds.midX + pixel * 2.5, y: bounds.minY + pixel * 8, width: size, height: size * 1.2)
            mark.opacity = 0
            let rise = CABasicAnimation(keyPath: "transform.translation")
            rise.fromValue = NSValue(size: CGSize(width: 0, height: -pixel * 1.5))
            rise.toValue = NSValue(size: CGSize(width: pixel * 2, height: pixel * 3))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.3, 1]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 3
            group.repeatCount = .infinity
            group.timeOffset = Double(index) * 1.5
            mark.add(group, forKey: "sleep")
            layer?.addSublayer(mark)
            sleepMarks.append(mark)
        }
    }

    override func layout() {
        super.layout()
        let size = IslandClawdBadgeRenderer.size(pixel: pixel)
        sprite.frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        if let shown, !sleepMarks.isEmpty { updateSleepMarks(visible: shown == .idle && !reduceMotion) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let shown { show(shown, replayReaction: false) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else { windowVisible = false; updatePause(); return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.windowVisible = window.occlusionState.contains(.visible)
                self.updatePause()
            }
        }
        windowVisible = window.occlusionState.contains(.visible)
        if let shown { show(shown, replayReaction: false) }
        updatePause()
    }

    /// Freezes every layer animation in place (speed 0) and resumes from the same frame.
    private func updatePause() {
        guard let root = layer else { return }
        let shouldPause = !(playbackRequested && windowVisible) || isHiddenOrHasHiddenAncestor
        guard shouldPause != paused else { return }
        paused = shouldPause
        if shouldPause {
            let now = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
            root.timeOffset = now
        } else {
            let pausedAt = root.timeOffset
            root.speed = 1
            root.timeOffset = 0
            root.beginTime = 0
            root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }

    override func viewDidHide() { super.viewDidHide(); updatePause() }
    override func viewDidUnhide() { super.viewDidUnhide(); updatePause() }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
}

/// SwiftUI host for the compact island's left wing. Keep it out of any per-frame SwiftUI clock:
/// all motion happens inside Core Animation.
struct IslandClawdBadge: NSViewRepresentable {
    var mood: IslandMascotMood
    var pixel: CGFloat
    var gaze: Int = 0
    var reduceMotion: Bool
    var playing: Bool
    var species = IslandPetSpecies.clawd

    func makeNSView(context: Context) -> IslandClawdBadgeView { IslandClawdBadgeView(frame: .zero) }
    func updateNSView(_ view: IslandClawdBadgeView, context: Context) {
        view.apply(mood: mood, pixel: pixel, gaze: gaze, reduceMotion: reduceMotion, playing: playing, species: species)
    }
}

/// Static expression for task cards; renders once per state and scale.
struct IslandClawdStill: View {
    var mood: IslandMascotMood
    var pixel: CGFloat
    var species = IslandPetSpecies.clawd
    @Environment(\.displayScale) private var scale

    var body: some View {
        let size = IslandClawdBadgeRenderer.size(pixel: pixel)
        Group {
            if let image = IslandClawdBadgeRenderer.stillImage(IslandClawdBadgeState(mood: mood), pixel: pixel, scale: scale, species: species) {
                Image(decorative: image, scale: scale)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Island outline cue paired with the badge: approve and reply breathe, done and fail flash once.
/// Apply the animation to the opacity of a stroke layer that follows the island shape.
enum IslandClawdGlow {
    static func color(for state: IslandClawdBadgeState) -> NSColor? {
        switch state {
        case .approve: return NSColor(srgbRed: 0xF0 / 255.0, green: 0x8C / 255.0, blue: 0x69 / 255.0, alpha: 1)
        case .reply: return NSColor(srgbRed: 0xF0 / 255.0, green: 0xCD / 255.0, blue: 0x64 / 255.0, alpha: 1)
        case .done: return NSColor(srgbRed: 0x8F / 255.0, green: 0xB9 / 255.0, blue: 0x8B / 255.0, alpha: 1)
        case .fail: return NSColor(srgbRed: 0xD2 / 255.0, green: 0x65 / 255.0, blue: 0x5F / 255.0, alpha: 1)
        default: return nil
        }
    }

    static func animation(for state: IslandClawdBadgeState, reduceMotion: Bool) -> CAAnimation? {
        switch state {
        case .approve, .reply:
            guard !reduceMotion else { return nil }
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 0.45
            breathe.toValue = 1
            breathe.duration = state == .approve ? 0.8 : 0.9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return breathe
        case .done, .fail:
            let flash = CABasicAnimation(keyPath: "opacity")
            flash.fromValue = 1
            flash.toValue = 0
            flash.duration = reduceMotion ? 0.6 : 1.3
            flash.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flash.fillMode = .forwards
            flash.isRemovedOnCompletion = false
            return flash
        default:
            return nil
        }
    }

    /// Resting opacity when no animation runs: steady for approve/reply under Reduce Motion, otherwise hidden.
    static func restingOpacity(for state: IslandClawdBadgeState, reduceMotion: Bool) -> Float {
        (state == .approve || state == .reply) && reduceMotion ? 1 : 0
    }
}
