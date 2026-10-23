import AppKit
import QuartzCore

/// Finite particles; larger bursts use a non-interactive, screen-aligned canvas.
@MainActor
final class ActivityIslandCompletionConfetti {
    private var overlay: CompletionConfettiWindow?
    private var emitters: [CAEmitterLayer] = []
    private var stopEmission: DispatchWorkItem?
    private var cleanup: DispatchWorkItem?
    private(set) var lastSerial = 0
    private(set) var burstCount = 0
    var isActive: Bool { !emitters.isEmpty }

    func update(serial: Int, in parent: CALayer, rect: CGRect, reduceMotion: Bool, visible: Bool,
                intensity: ActivityIslandConfettiIntensity = .light, islandWindow: NSWindow? = nil, screen: NSScreen? = nil) {
        if reduceMotion || !visible { stop() }
        guard serial != lastSerial else { return }
        lastSerial = serial
        guard serial > 0, !reduceMotion, visible, rect.width > 0 else { return }
        stop()
        burstCount += 1
        let parameters = intensity.parameters
        var canvas = parent
        var emissionRect = rect
        if intensity != .light, let islandWindow, let screen {
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - screen.frame.height * 0.4,
                               width: screen.frame.width, height: screen.frame.height * 0.4)
            let window = CompletionConfettiWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.level = islandWindow.level
            window.isReleasedWhenClosed = false
            let view = CompletionConfettiCanvas(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            window.contentView = view
            guard let layer = view.layer else { return }
            canvas = layer
            // Island canvas and overlay both use top-left, downward coordinates.
            emissionRect = rect.offsetBy(dx: islandWindow.frame.minX - frame.minX,
                                         dy: frame.maxY - islandWindow.frame.maxY)
            window.orderFrontRegardless(); overlay = window
        }
        var colors: [NSColor] = [.systemPink, .systemYellow, .systemCyan, .systemPurple, .systemGreen]
        if intensity == .festive { colors.append(NSColor(srgbRed: 76/255, green: 212/255, blue: 122/255, alpha: 1)) }
        for side in 0..<2 {
            let layer = CAEmitterLayer()
            layer.beginTime = CACurrentMediaTime()
            layer.frame = canvas.bounds
            layer.emitterShape = .point
            layer.emitterPosition = CGPoint(x: side == 0 ? emissionRect.minX + 10 : emissionRect.maxX - 10, y: emissionRect.maxY - 14)
            layer.zPosition = 100
            layer.emitterCells = colors.enumerated().map { index, color in
                let cell = CAEmitterCell()
                cell.contents = Self.paper
                cell.color = color.cgColor
                cell.birthRate = parameters.birthRate
                cell.lifetime = parameters.lifetime; cell.lifetimeRange = 0.3
                cell.velocity = parameters.velocity; cell.velocityRange = 55
                if intensity == .light {
                    cell.emissionLongitude = side == 0 ? -CGFloat.pi / 3 : -CGFloat.pi * 2 / 3
                } else {
                    cell.emissionLongitude = side == 0 ? CGFloat.pi * 2 / 3 : CGFloat.pi / 3
                }
                cell.emissionRange = .pi / 3
                cell.yAcceleration = parameters.gravity
                cell.spin = index.isMultiple(of: 2) ? parameters.spin : -parameters.spin; cell.spinRange = 5
                cell.scale = parameters.scale; cell.scaleRange = 0.3
                cell.alphaSpeed = parameters.alphaSpeed
                return cell
            }
            canvas.addSublayer(layer); emitters.append(layer)
        }
        let stopEmission = DispatchWorkItem { [weak self] in self?.emitters.forEach { $0.birthRate = 0 } }
        self.stopEmission = stopEmission
        DispatchQueue.main.asyncAfter(deadline: .now() + parameters.emissionDuration, execute: stopEmission)
        let cleanup = DispatchWorkItem { [weak self] in self?.stop() }
        self.cleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + parameters.cleanupDelay, execute: cleanup)
    }
    func stop() {
        overlay?.orderOut(nil); overlay = nil
        stopEmission?.cancel(); stopEmission = nil
        cleanup?.cancel(); cleanup = nil
        emitters.forEach { $0.removeFromSuperlayer() }; emitters.removeAll()
    }
    private static let paper: CGImage? = {
        guard let context = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        return context.makeImage()
    }()
}

private final class CompletionConfettiWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class CompletionConfettiCanvas: NSView {
    override var isFlipped: Bool { true }
}
