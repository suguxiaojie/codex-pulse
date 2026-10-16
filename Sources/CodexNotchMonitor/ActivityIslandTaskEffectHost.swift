// Reused from QuotaView d16307f (MIT), Copyright (c) 2026 Duoasa.
// Full notice: Resources/ThirdPartyNotices.txt.
import AppKit
import QuartzCore
import SwiftUI

enum CodexActivityIslandEdgeEmphasis: Equatable {
    case none
    case completion
    case confirmationReminder
}

struct CodexActivityIslandConfirmationReminderContract {
    // Match the awaiting-confirmation orb’s warm upper highlight. Keep quota
    // warning and quantum particle palettes independent.
    static let approvalColor = NSColor(srgbRed: 1, green: 0.56, blue: 0.12, alpha: 1)
    static let warningColor = NSColor(
        srgbRed: 1,
        green: 0.80,
        blue: 0,
        alpha: 1
    )
    static let revealDuration: CFTimeInterval = 0.20

    static func edgeEmphasis(
        visualState: CodexActivityVisualState,
        reminderActive: Bool,
        completionEffectAvailable: Bool
    ) -> CodexActivityIslandEdgeEmphasis {
        if visualState == .completed, completionEffectAvailable {
            return .completion
        }
        if visualState == .awaitingConfirmation, reminderActive {
            return .confirmationReminder
        }
        return .none
    }
}

struct CodexActivityIslandCompletionPalette {
    static let violet = NSColor(
        srgbRed: 0.55,
        green: 0.36,
        blue: 1.00,
        alpha: 1
    )
    static let blue = NSColor(
        srgbRed: 0.31,
        green: 0.63,
        blue: 1.00,
        alpha: 1
    )
    static let cyan = NSColor(
        srgbRed: 0.43,
        green: 0.89,
        blue: 1.00,
        alpha: 1
    )
    static let gradientLocations: [NSNumber] = [0, 0.52, 1]
}

struct CodexActivityIslandCompletionGlowGeometry {
    static let sourceInset: CGFloat = 1.25
    static let outlineWidth: CGFloat = 1
    static let restingShadowRadius: CGFloat = 5.5
    static let peakShadowRadius: CGFloat = 9.5
    static let shadowOpacity: Float = 1

    static func sourceRect(in islandRect: NSRect) -> NSRect {
        islandRect.insetBy(dx: sourceInset, dy: sourceInset)
    }

    static func sourceCornerRadius(
        in islandRect: NSRect,
        islandCornerRadius: CGFloat
    ) -> CGFloat {
        max(
            0,
            min(islandCornerRadius, islandRect.height / 2)
                - sourceInset
        )
    }
}

final class ActivityIslandCompletionGlowView: NSView {
    var consoleContour: CGPath?
    var usesContinuousCorners = false
    var drawsOnlyEdge = false {
        didSet {
            guard drawsOnlyEdge != oldValue else { return }
            applyColors()
            needsLayout = true
        }
    }
    // Optional satellite styling; nil preserves the existing main-island palette
    // and completion sequence.
    var completionColor: NSColor? { didSet { applyColors() } }
    var completionRevealDelay: CFTimeInterval?
    private enum AnimationKey {
        static let reveal = "quotaview.activity.completion-glow.reveal"
        static let breathRadius =
            "quotaview.activity.completion-glow.radius"
    }

    private let violetGlowLayer = CAShapeLayer()
    private let cyanGlowLayer = CAShapeLayer()
    private let edgeOnlyMask = CAShapeLayer()
    private var edgeEmphasis = CodexActivityIslandEdgeEmphasis.none
    private var reduceMotion = false
    private var playbackVisible = false
    private var islandCornerRadius: CGFloat = 34
    private var islandInset: CGFloat = 30

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        configureGlowLayer(
            violetGlowLayer,
            color: CodexActivityIslandCompletionPalette.violet,
            horizontalOffset: -2
        )
        configureGlowLayer(
            cyanGlowLayer,
            color: CodexActivityIslandCompletionPalette.cyan,
            horizontalOffset: 2
        )
        layer?.addSublayer(violetGlowLayer)
        layer?.addSublayer(cyanGlowLayer)
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let islandRect = bounds.insetBy(
            dx: islandInset,
            dy: islandInset
        )
        let islandRadius = min(
            islandCornerRadius,
            islandRect.height / 2
        )
        let glowSourceRect =
            CodexActivityIslandCompletionGlowGeometry.sourceRect(
                in: islandRect
            )
        let glowSourceRadius =
            CodexActivityIslandCompletionGlowGeometry
            .sourceCornerRadius(
                in: islandRect,
                islandCornerRadius: islandRadius
            )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let glowPath = consoleContour ?? (usesContinuousCorners
            ? ActivityIslandCardContour.path(in: glowSourceRect, radius: glowSourceRadius)
            : CGPath(
            roundedRect: glowSourceRect,
            cornerWidth: glowSourceRadius,
            cornerHeight: glowSourceRadius,
            transform: nil
        ))
        let shadowPath = drawsOnlyEdge
            ? glowPath.copy(strokingWithWidth: CodexActivityIslandCompletionGlowGeometry.outlineWidth,
                lineCap: .round, lineJoin: .round, miterLimit: 2)
            : glowPath
        for glowLayer in [violetGlowLayer, cyanGlowLayer] {
            glowLayer.frame = bounds
            glowLayer.path = glowPath
            glowLayer.shadowPath = shadowPath
        }
        if drawsOnlyEdge && consoleContour == nil {
            // Cut out the text area from the glow only, never from a glass
            // ancestor. Keep a narrow inner rim and the existing outer bloom.
            let rimWidth: CGFloat = 2
            let interior = islandRect.insetBy(dx: rimWidth, dy: rimWidth)
            let maskPath = CGMutablePath()
            maskPath.addRect(bounds)
            if interior.width > 0 && interior.height > 0 {
                let radius = max(0, islandRadius - rimWidth)
                maskPath.addPath(usesContinuousCorners
                    ? ActivityIslandCardContour.path(in: interior, radius: radius)
                    : CGPath(roundedRect: interior, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            edgeOnlyMask.frame = bounds
            edgeOnlyMask.fillColor = NSColor.black.cgColor
            edgeOnlyMask.fillRule = .evenOdd
            edgeOnlyMask.path = maskPath
            layer?.mask = edgeOnlyMask
        } else {
            layer?.mask = nil
        }
        CATransaction.commit()
    }

    func setIslandInset(_ inset: CGFloat) {
        let normalized = max(0, inset)
        guard islandInset != normalized else { return }
        islandInset = normalized
        needsLayout = true
    }

    func setIslandCornerRadius(_ radius: CGFloat) {
        let normalized = max(0, radius)
        guard islandCornerRadius != normalized else { return }
        islandCornerRadius = normalized
        needsLayout = true
    }

    func update(
        edgeEmphasis: CodexActivityIslandEdgeEmphasis,
        reduceMotion: Bool,
        playbackVisible: Bool
    ) {
        guard self.edgeEmphasis != edgeEmphasis
                || self.reduceMotion != reduceMotion
                || self.playbackVisible != playbackVisible
        else {
            return
        }

        let previousEmphasis = self.edgeEmphasis
        let wasShowing = previousEmphasis != .none
            && self.playbackVisible
        self.edgeEmphasis = edgeEmphasis
        self.reduceMotion = reduceMotion
        self.playbackVisible = playbackVisible
        applyColors()
        applyState(
            delaysReveal: !wasShowing
                || previousEmphasis != edgeEmphasis
        )
    }

    private func applyState(delaysReveal: Bool) {
        let glowLayers = [violetGlowLayer, cyanGlowLayer]
        glowLayers.forEach { $0.removeAllAnimations() }

        let shouldShow = edgeEmphasis != .none && playbackVisible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for glowLayer in glowLayers {
            glowLayer.opacity = shouldShow ? 1 : 0
            glowLayer.shadowOpacity = shouldShow
                ? CodexActivityIslandCompletionGlowGeometry
                    .shadowOpacity
                : 0
            glowLayer.shadowRadius = shouldShow
                ? CodexActivityIslandCompletionGlowGeometry
                    .restingShadowRadius
                : 0
        }
        CATransaction.commit()
        isHidden = !shouldShow

        guard shouldShow, !reduceMotion else { return }

        let now = violetGlowLayer.convertTime(
            CACurrentMediaTime(),
            from: nil
        )
        let revealDelay: CFTimeInterval = edgeEmphasis == .completion
            ? (completionRevealDelay ?? CodexActivityStateSmokeContract.completionGlowDelay)
            : 0
        let revealDuration: CFTimeInterval =
            edgeEmphasis == .confirmationReminder
            ? CodexActivityIslandConfirmationReminderContract
                .revealDuration
            : CodexActivityStateSmokeContract.completionGlowFadeDuration
        var breathBeginTime = now
        if delaysReveal {
            let reveal = CABasicAnimation(keyPath: "opacity")
            reveal.fromValue = 0
            reveal.toValue = 1
            reveal.beginTime = now + revealDelay
            reveal.duration = revealDuration
            reveal.fillMode = .backwards
            reveal.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            for glowLayer in glowLayers {
                glowLayer.add(reveal, forKey: AnimationKey.reveal)
            }
            breathBeginTime = reveal.beginTime + reveal.duration
        }

        let breathRadius = CAKeyframeAnimation(keyPath: "shadowRadius")
        breathRadius.values = [
            CodexActivityIslandCompletionGlowGeometry
                .restingShadowRadius,
            CodexActivityIslandCompletionGlowGeometry
                .peakShadowRadius,
            CodexActivityIslandCompletionGlowGeometry
                .restingShadowRadius,
        ]
        breathRadius.keyTimes = [0, 0.5, 1]
        breathRadius.beginTime = breathBeginTime
        breathRadius.duration =
            CodexActivityStateSmokeContract
                .completionGlowBreathDuration
        breathRadius.repeatCount = .infinity
        breathRadius.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        for glowLayer in glowLayers {
            glowLayer.add(
                breathRadius,
                forKey: AnimationKey.breathRadius
            )
        }
    }

    private func applyColors() {
        let colors: (NSColor, NSColor)
        switch edgeEmphasis {
        case .completion, .none:
            colors = (
                completionColor ?? CodexActivityIslandCompletionPalette.violet,
                completionColor ?? CodexActivityIslandCompletionPalette.cyan
            )
        case .confirmationReminder:
            let warning =
                CodexActivityIslandConfirmationReminderContract
                .approvalColor
            colors = (warning, warning)
        }
        for (layer, color) in zip(
            [violetGlowLayer, cyanGlowLayer],
            [colors.0, colors.1]
        ) {
            layer.fillColor = drawsOnlyEdge ? NSColor.clear.cgColor : color.cgColor
            layer.strokeColor = drawsOnlyEdge ? color.cgColor : nil
            layer.lineWidth = CodexActivityIslandCompletionGlowGeometry.outlineWidth
            layer.shadowColor = color.cgColor
        }
    }

    private func configureGlowLayer(
        _ glowLayer: CAShapeLayer,
        color: NSColor,
        horizontalOffset: CGFloat
    ) {
        glowLayer.fillColor = color.cgColor
        glowLayer.strokeColor = nil
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowOffset = CGSize(
            width: horizontalOffset,
            height: 0
        )
        glowLayer.masksToBounds = false
    }
}

final class ActivityIslandCompletionOutlineView: NSView {
    var usesContinuousCorners = false
    var completionColor: NSColor? { didSet { applyColors() } }
    var completionRevealDelay: CFTimeInterval?
    private enum AnimationKey {
        static let reveal =
            "quotaview.activity.completion-outline.reveal"
    }

    private let outlineGradientLayer = CAGradientLayer()
    private let outlineMaskLayer = CAShapeLayer()
    private var edgeEmphasis = CodexActivityIslandEdgeEmphasis.none
    private var reduceMotion = false
    private var playbackVisible = false
    private var islandCornerRadius: CGFloat = 34

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        outlineGradientLayer.colors = [
            CodexActivityIslandCompletionPalette.violet.cgColor,
            CodexActivityIslandCompletionPalette.blue.cgColor,
            CodexActivityIslandCompletionPalette.cyan.cgColor,
        ]
        outlineGradientLayer.locations =
            CodexActivityIslandCompletionPalette.gradientLocations
        outlineGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        outlineGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        outlineMaskLayer.fillColor = NSColor.clear.cgColor
        outlineMaskLayer.strokeColor = NSColor.white.cgColor
        outlineMaskLayer.lineWidth =
            CodexActivityIslandCompletionGlowGeometry.outlineWidth
        outlineGradientLayer.mask = outlineMaskLayer
        layer?.addSublayer(outlineGradientLayer)
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let halfWidth =
            CodexActivityIslandCompletionGlowGeometry.outlineWidth / 2
        let outlineRect = bounds.insetBy(
            dx: halfWidth,
            dy: halfWidth
        )
        let outlineRadius = max(
            0,
            min(islandCornerRadius, bounds.height / 2) - halfWidth
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = usesContinuousCorners
            ? ActivityIslandCardContour.path(in: outlineRect, radius: outlineRadius)
            : CGPath(
            roundedRect: outlineRect,
            cornerWidth: outlineRadius,
            cornerHeight: outlineRadius,
            transform: nil
        )
        outlineGradientLayer.frame = bounds
        outlineMaskLayer.frame = bounds
        outlineMaskLayer.path = path
        CATransaction.commit()
    }

    func setIslandCornerRadius(_ radius: CGFloat) {
        let normalized = max(0, radius)
        guard islandCornerRadius != normalized else { return }
        islandCornerRadius = normalized
        needsLayout = true
    }

    func update(
        edgeEmphasis: CodexActivityIslandEdgeEmphasis,
        reduceMotion: Bool,
        playbackVisible: Bool
    ) {
        guard self.edgeEmphasis != edgeEmphasis
                || self.reduceMotion != reduceMotion
                || self.playbackVisible != playbackVisible
        else {
            return
        }

        let previousEmphasis = self.edgeEmphasis
        let wasShowing = previousEmphasis != .none
            && self.playbackVisible
        self.edgeEmphasis = edgeEmphasis
        self.reduceMotion = reduceMotion
        self.playbackVisible = playbackVisible
        applyColors()
        applyState(
            delaysReveal: !wasShowing
                || previousEmphasis != edgeEmphasis
        )
    }

    private func applyState(delaysReveal: Bool) {
        outlineGradientLayer.removeAllAnimations()
        let shouldShow = edgeEmphasis != .none && playbackVisible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineGradientLayer.opacity = shouldShow ? 1 : 0
        CATransaction.commit()
        isHidden = !shouldShow
        needsLayout = true

        guard shouldShow, !reduceMotion, delaysReveal else { return }
        let now = outlineGradientLayer.convertTime(
            CACurrentMediaTime(),
            from: nil
        )
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0
        reveal.toValue = 1
        reveal.beginTime = now + (
            edgeEmphasis == .completion
                ? (completionRevealDelay ?? CodexActivityStateSmokeContract.completionGlowDelay)
                : 0
        )
        reveal.duration = edgeEmphasis == .confirmationReminder
            ? CodexActivityIslandConfirmationReminderContract
                .revealDuration
            : CodexActivityStateSmokeContract.completionGlowFadeDuration
        reveal.fillMode = .backwards
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        outlineGradientLayer.add(
            reveal,
            forKey: AnimationKey.reveal
        )
    }

    private func applyColors() {
        switch edgeEmphasis {
        case .completion, .none:
            outlineGradientLayer.colors = [
                (completionColor?.withAlphaComponent(0.76) ?? CodexActivityIslandCompletionPalette.violet).cgColor,
                (completionColor ?? CodexActivityIslandCompletionPalette.blue).cgColor,
                (completionColor?.withAlphaComponent(0.76) ?? CodexActivityIslandCompletionPalette.cyan).cgColor,
            ]
        case .confirmationReminder:
            let warning =
                CodexActivityIslandConfirmationReminderContract
                .approvalColor
            outlineGradientLayer.colors = [
                warning.withAlphaComponent(0.76).cgColor,
                warning.cgColor,
                warning.withAlphaComponent(0.76).cgColor,
            ]
        }
    }
}

enum IslandConfirmationPulse {
    static let key = "console.confirmation-glow.pulse"
    static let duration: CFTimeInterval = 3
    private static let epoch = CACurrentMediaTime()

    static func update(_ layer: CALayer?, animated: Bool, includesRadius: Bool = false, minimumOpacity: Double = 0) {
        guard let layer else { return }
        guard animated else { layer.removeAnimation(forKey: key); return }
        guard layer.animation(forKey: key) == nil else { return }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [minimumOpacity, minimumOpacity, 1, minimumOpacity, minimumOpacity]
        var animations = [opacity]
        if includesRadius {
            let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
            let resting = CodexActivityIslandCompletionGlowGeometry.restingShadowRadius
            radius.values = [resting, resting, CodexActivityIslandCompletionGlowGeometry.peakShadowRadius, resting, resting]
            animations.append(radius)
        }
        for animation in animations {
            animation.keyTimes = [0, 0.12, 0.52, 0.92, 1]
            animation.duration = duration
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        }
        let pulse = CAAnimationGroup()
        pulse.animations = animations
        pulse.duration = duration
        pulse.repeatCount = .infinity
        pulse.beginTime = layer.convertTime(epoch, from: nil)
        layer.add(pulse, forKey: key)
    }
}

extension ActivityIslandCompletionGlowView {
    func updateIslandConfirmationPulse(animated: Bool) {
        for layer in [violetGlowLayer, cyanGlowLayer] {
            layer.removeAnimation(forKey: AnimationKey.reveal)
            layer.removeAnimation(forKey: AnimationKey.breathRadius)
            IslandConfirmationPulse.update(layer, animated: !isHidden && animated, includesRadius: true)
        }
    }

}

private enum ActivityIslandCardContour {
    static func path(in rect: CGRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
    }
}

@MainActor
final class ActivityIslandTaskEffectHost: NSView {
    let effect = ActivityStateSmokeMetalView(frame: .zero)
    private let glow = ActivityIslandCompletionGlowView(frame: .zero)
    private let outline = ActivityIslandCompletionOutlineView(frame: .zero)
    private var identity: CodexActivityTaskIdentity?
    private var state: CodexActivityVisualState = .standby
    private var playback = false
    private var reduced = false
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(glow); addSubview(effect); addSubview(outline)
        glow.drawsOnlyEdge = true; glow.usesContinuousCorners = true
        outline.usesContinuousCorners = true
        effect.layer?.cornerRadius = 16; effect.layer?.cornerCurve = .continuous; effect.layer?.masksToBounds = true
        effect.setPlaybackEnabled(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        effect.frame = bounds
        glow.frame = bounds.insetBy(dx: -30, dy: -30); glow.setIslandInset(30); glow.setIslandCornerRadius(16)
        outline.frame = bounds; outline.setIslandCornerRadius(16)
        effect.redrawIfPaused()
    }
    func update(row: ActivitySessionSnapshot, selectedEffect: ActivityIslandProgressEffect, playback: Bool, reduceMotion: Bool) {
        let next = Optional(row.phase).rippleGlowVisualState
        let receipt = identity == nil && next == .completed
        identity = .init(sessionID: row.sessionID, turnID: row.turnID)
        state = next; self.playback = playback; reduced = reduceMotion
        effect.setEffect(selectedEffect)
        effect.setReduceMotion(reduceMotion || receipt)
        effect.setState(next, taskIdentity: identity)
        effect.setApproximateProgress(nil)
        effect.setReduceMotion(reduceMotion)
        synchronize()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronize() }
    private func synchronize() {
        let visible = playback && window != nil
        let confirming = state == .awaitingConfirmation
        effect.isHidden = confirming
        effect.setPlaybackEnabled(visible && !confirming)
        let emphasis: CodexActivityIslandEdgeEmphasis = confirming ? .confirmationReminder : state == .completed ? .completion : .none
        glow.update(edgeEmphasis: emphasis, reduceMotion: reduced, playbackVisible: visible)
        outline.update(edgeEmphasis: emphasis, reduceMotion: true, playbackVisible: visible)
        glow.updateIslandConfirmationPulse(animated: visible && !reduced && (state == .completed || confirming))
    }
    func stop() { playback = false; synchronize() }
}
