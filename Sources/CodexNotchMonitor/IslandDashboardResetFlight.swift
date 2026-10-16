// Reused from QuotaView f779531 IslandResetPage (MIT), Copyright (c) 2026 Duoasa.
import AppKit
import SwiftUI
enum DashboardResetTicketSlot: Hashable { case usage, reset }
struct DashboardResetTicketAnchors: PreferenceKey {
    static var defaultValue: [DashboardResetTicketSlot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DashboardResetTicketSlot: Anchor<CGRect>], nextValue: () -> [DashboardResetTicketSlot: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

enum DashboardResetTicketFlight {
    static let cardSize = CGSize(width: 201.29, height: 120)
    static let duration: TimeInterval = 0.76
    struct Sample {
        let position: CGPoint
        let transform: CATransform3D
    }
    static func sample(progress: CGFloat, source: CGRect, destination: CGRect) -> Sample {
        let lift = sin(.pi * progress)
        let width = source.width + (destination.width - source.width) * progress
        let height = source.height + (destination.height - source.height) * progress
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 650
        transform = CATransform3DRotate(transform, lift * .pi / 10, 1, 0, 0)
        // Unwrapped yaw completes a full turn; sampled matrices preserve the
        // 90°/180°/270° faces instead of interpolating identical 0°/360° endpoints.
        transform = CATransform3DRotate(transform, -progress * .pi * 2, 0, 1, 0)
        transform = CATransform3DRotate(transform, -lift * .pi / 30, 0, 0, 1)
        transform = CATransform3DScale(transform, width / cardSize.width, height / cardSize.height, 1)
        return Sample(position: .init(x: source.midX + (destination.midX - source.midX) * progress,
            y: source.midY + (destination.midY - source.midY) * progress - 24 * lift), transform: transform)
    }
    // Both directions start moving immediately, then gently overshoot and settle.
    // Reverse the spatial progress on return, keeping the elapsed-time easing forward.
    static func progress(at time: Double) -> CGFloat {
        let t = min(1, max(0, time))
        if t <= 0.72 {
            let u = t / 0.72
            return CGFloat(1.025 * (1 - pow(1 - u, 3)))
        }
        let u = (t - 0.72) / 0.28
        return CGFloat(1 + 0.025 * pow(1 - u, 2))
    }
}

private final class DashboardResetTicketFlightObserver: NSObject, CAAnimationDelegate {
    let onStart: () -> Void
    let onStop: () -> Void
    init(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onStart = onStart; self.onStop = onStop
    }
    func animationDidStart(_ anim: CAAnimation) { onStart() }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) { onStop() }
}

final class DashboardResetTicketFlightHost: NSView {
    override var isFlipped: Bool { true }
    private let card = CALayer()
    private let face = CALayer()
    private let mark = CALayer()
    private static let animationKey = "island.reset-ticket.flight"
    private struct Request {
        let serial: UInt64
        let toReset: Bool
        let source: CGRect
        let destination: CGRect
    }
    private var pendingRequest: Request?
    private var animationGeneration: UInt64 = 0
    var onStart: (UInt64) -> Void = { _ in }
    var onCompletion: (UInt64) -> Void = { _ in }
    private var serial: UInt64?
    private var movingToReset = false
    private var startedAt: CFTimeInterval = 0
    private var flightDuration: TimeInterval = 0
    private var startProgress: CGFloat = 0
    private var endProgress: CGFloat = 1
    private var source = CGRect.zero
    private var destination = CGRect.zero
    var flightAnimation: CAAnimationGroup? { card.animation(forKey: Self.animationKey) as? CAAnimationGroup }
    var cardPosition: CGPoint { card.position }
    var cardTransform: CATransform3D { card.transform }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(card)
        card.bounds = CGRect(origin: .zero, size: DashboardResetTicketFlight.cardSize)
        card.isDoubleSided = true
        card.addSublayer(face); card.addSublayer(mark)
        face.frame = card.bounds
        mark.bounds = CGRect(x: 0, y: 0, width: 45.3649, height: 45.302)
        mark.position = CGPoint(x: card.bounds.midX, y: card.bounds.midY)
        applyArtwork()
        face.contentsGravity = .resizeAspect; mark.contentsGravity = .resizeAspect
        face.contentsScale = 2; mark.contentsScale = 2
        card.shadowColor = NSColor.black.cgColor; card.shadowOpacity = 0.2
        card.shadowRadius = 5; card.shadowOffset = CGSize(width: 0, height: 3)
        card.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: 8.625, cornerHeight: 8.625, transform: nil)
        card.isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    private func applyArtwork() {
        var faceRect = face.bounds, markRect = mark.bounds
        face.contents = Bundle.main.url(forResource: "DashboardResetTicket", withExtension: "svg").flatMap(NSImage.init(contentsOf:))?
            .cgImage(forProposedRect: &faceRect, context: nil, hints: nil)
        mark.contents = Bundle.main.url(forResource: "DashboardResetMark", withExtension: "svg").flatMap(NSImage.init(contentsOf:))?.cgImage(forProposedRect: &markRect, context: nil, hints: nil)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
        else { needsLayout = true }
    }
    override func layout() {
        super.layout()
        startIfReady()
    }
    func configure(serial: UInt64, toReset: Bool, active: Bool, source: CGRect, destination: CGRect, reduceMotion: Bool) {
        guard active, !reduceMotion else { stop(); return }
        pendingRequest = Request(serial: serial, toReset: toReset, source: source, destination: destination)
        startIfReady()
    }
    private func startIfReady() {
        // updateNSView can precede window attachment and the first layout. Keep
        // the request until those arrive instead of silently dropping its start.
        guard let request = pendingRequest, window != nil, Self.valid(bounds),
              Self.valid(request.source), Self.valid(request.destination) else { return }
        let serial = request.serial, toReset = request.toReset
        let source = request.source, destination = request.destination
        guard self.serial != serial else { return }
        let reversing = flightAnimation != nil && movingToReset != toReset
        let now = CACurrentMediaTime()
        let from = reversing ? currentProgress(at: now) : (toReset ? CGFloat(0) : CGFloat(1))
        let to: CGFloat = toReset ? 1 : 0
        let oldPosition = card.presentation()?.position
        let oldTransform = card.presentation()?.transform
        if !reversing { self.source = source; self.destination = destination }
        self.serial = serial; movingToReset = toReset
        animationGeneration &+= 1
        let generation = animationGeneration
        startedAt = now; flightDuration = DashboardResetTicketFlight.duration
        startProgress = from; endProgress = to
        let steps = 60
        let samples = (0...steps).map { index -> DashboardResetTicketFlight.Sample in
            let time = Double(index) / Double(steps)
            let p = DashboardResetTicketFlight.progress(at: time)
            return DashboardResetTicketFlight.sample(progress: from + (to - from) * p, source: self.source, destination: self.destination)
        }
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = samples.map { NSValue(point: $0.position) }
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = samples.map { NSValue(caTransform3D: $0.transform) }
        if reversing, let oldPosition, let oldTransform {
            position.values?[0] = NSValue(point: oldPosition)
            transform.values?[0] = NSValue(caTransform3D: oldTransform)
        }
        let final = DashboardResetTicketFlight.sample(progress: to, source: self.source, destination: self.destination)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        card.isHidden = false; card.position = final.position; card.transform = final.transform
        CATransaction.commit()
        let animation = CAAnimationGroup()
        position.duration = flightDuration; transform.duration = flightDuration
        animation.animations = [position, transform]; animation.duration = flightDuration
        // Let the compositor assign the start at transaction commit. Using the
        // pre-layout wall clock would consume early frames while glass settles.
        animation.beginTime = 0
        animation.isRemovedOnCompletion = false; animation.fillMode = .forwards
        animation.delegate = DashboardResetTicketFlightObserver(onStart: { [weak self] in
            let beganAt = CACurrentMediaTime()
            // Deliver outside SwiftUI's update/layout transaction. Generation
            // guards discard callbacks from a replaced or reversed flight.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.animationGeneration == generation, self.serial == serial else { return }
                self.startedAt = beganAt
                self.onStart(serial)
            }
        }, onStop: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.animationGeneration == generation, self.serial == serial else { return }
                self.onCompletion(serial)
            }
        })
        card.add(animation, forKey: Self.animationKey)
    }
    private func currentProgress(at now: CFTimeInterval) -> CGFloat {
        let time = min(1, max(0, (now - startedAt) / max(0.001, flightDuration)))
        let p = DashboardResetTicketFlight.progress(at: time)
        return startProgress + (endProgress - startProgress) * p
    }
    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
    func stop() {
        let stoppedSerial = pendingRequest?.serial ?? serial
        let completion = onCompletion
        pendingRequest = nil; animationGeneration &+= 1
        serial = nil; card.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin(); CATransaction.setDisableActions(true); card.isHidden = true; CATransaction.commit()
        // A dismantled/hidden host must also restore the page's static ticket.
        if let stoppedSerial { DispatchQueue.main.async { completion(stoppedSerial) } }
    }
}
struct DashboardResetTicketFlightView: NSViewRepresentable {
    let serial: UInt64
    let toReset: Bool
    let active: Bool
    let source: CGRect
    let destination: CGRect
    let reduceMotion: Bool
    var onStart: (UInt64) -> Void = { _ in }
    var onCompletion: (UInt64) -> Void = { _ in }
    func makeNSView(context: Context) -> DashboardResetTicketFlightHost { .init(frame: .zero) }
    func updateNSView(_ view: DashboardResetTicketFlightHost, context: Context) {
        view.onStart = onStart; view.onCompletion = onCompletion
        view.configure(serial: serial, toReset: toReset, active: active, source: source, destination: destination, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: DashboardResetTicketFlightHost, coordinator: ()) { view.stop() }
}
