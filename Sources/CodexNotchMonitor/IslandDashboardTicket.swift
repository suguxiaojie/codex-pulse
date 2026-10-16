// Adapted from QuotaView f779531 (MIT), Copyright (c) 2026 Duoasa.
import AppKit
import SwiftUI
struct DashboardResetTicket: View {
    let playbackEnabled: Bool
    var size = CGSize(width: 53.6774, height: 32)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = CGSize.zero
    @State private var hovered = false
    private var scale: CGFloat { size.height / 32 }
    private var motion: CGSize { reduceMotion ? .zero : tilt }
    private func asset(_ name: String) -> NSImage {
        Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
    }
    var body: some View {
        ZStack {
            ZStack {
                Image(nsImage: asset("DashboardResetTicket")).resizable().scaledToFit()
                RadialGradient(colors: [.white.opacity(hovered ? 0.28 : 0), .clear],
                    center: UnitPoint(x: 0.5 + motion.width * 0.25, y: 0.5 + motion.height * 0.25),
                    startRadius: 0, endRadius: 42 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2.3 * scale))
                Group { Image(nsImage: asset("DashboardResetMark")).resizable().scaledToFit()
                }.frame(width: 12.0973 * scale, height: 12.0805 * scale)
                    .offset(x: motion.width * 0.9 * scale, y: motion.height * 0.6 * scale)
                DashboardResetTicketSweep(active: playbackEnabled).allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
            .rotation3DEffect(.degrees(Double(-motion.height * 7)), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.degrees(Double(motion.width * 10)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: .black.opacity(hovered ? 0.3 : 0), radius: hovered ? 4 * min(2, scale) : 0,
                x: -motion.width * 2 * scale, y: hovered ? 3 * min(2, scale) : 0)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height).contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: tilt)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard point.x.isFinite, point.y.isFinite else { return }
                hovered = true
                tilt = CGSize(width: min(1, max(-1, point.x / size.width * 2 - 1)),
                    height: min(1, max(-1, point.y / size.height * 2 - 1)))
            case .ended: hovered = false; tilt = .zero
            }
        }
        .onDisappear { hovered = false; tilt = .zero }
    }
}

final class DashboardResetTicketSweepHost: NSView {
    private let stripe = CAGradientLayer()
    private static let animationKey = "island.reset-ticket.sweep"
    private var enabled = false
    private var renderedSize = CGSize.zero
    var sweepAnimation: CAKeyframeAnimation? { stripe.animation(forKey: Self.animationKey) as? CAKeyframeAnimation }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true; layer?.cornerRadius = 2.3
        stripe.colors = [NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0.70).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        stripe.locations = [0, 0.3, 0.5, 0.7, 1]
        stripe.startPoint = CGPoint(x: 0, y: 0.5); stripe.endPoint = CGPoint(x: 1, y: 0.5)
        stripe.isHidden = true; layer?.addSublayer(stripe)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }
    func configure(active: Bool, reduceMotion: Bool) {
        let next = active && !reduceMotion
        guard enabled != next else { return }
        enabled = next; updateAnimation()
    }
    override func layout() {
        super.layout()
        if renderedSize != bounds.size {
            renderedSize = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.cornerRadius = 2.3 * bounds.height / 32
            stripe.bounds = CGRect(x: 0, y: 0, width: 20 * bounds.height / 32, height: bounds.height * 3)
            stripe.position = CGPoint(x: bounds.midX, y: bounds.midY)
            stripe.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 7))
            CATransaction.commit()
            stripe.removeAnimation(forKey: Self.animationKey)
        }
        updateAnimation()
    }
    private func updateAnimation() {
        guard enabled, window != nil, bounds.width > 0, bounds.height > 0 else { stop(); return }
        CATransaction.begin(); CATransaction.setDisableActions(true); stripe.isHidden = false; CATransaction.commit()
        guard sweepAnimation == nil else { return }
        let travel = bounds.width + bounds.height
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-travel, -travel, travel, travel]
        animation.keyTimes = [0, 0.10, 0.90, 1]
        animation.timingFunctions = [.init(name: .linear), .init(name: .easeInEaseOut), .init(name: .linear)]
        animation.duration = 2; animation.repeatCount = .infinity
        animation.beginTime = stripe.convertTime(CACurrentMediaTime(), from: nil)
        stripe.add(animation, forKey: Self.animationKey)
    }
    func stop() {
        stripe.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin(); CATransaction.setDisableActions(true); stripe.isHidden = true; CATransaction.commit()
    }
}
private struct DashboardResetTicketSweep: NSViewRepresentable {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> DashboardResetTicketSweepHost { .init(frame: .zero) }
    func updateNSView(_ view: DashboardResetTicketSweepHost, context: Context) {
        view.configure(active: active, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: DashboardResetTicketSweepHost, coordinator: ()) { view.stop() }
}
