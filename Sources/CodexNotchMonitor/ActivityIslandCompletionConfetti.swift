import AppKit
import QuartzCore

/// One finite completion burst, owned by the existing island canvas. No timer,
/// display link, extra window, input interception or persistent particle state.
@MainActor
final class ActivityIslandCompletionConfetti {
    private var emitters: [CAEmitterLayer] = []
    private var stopEmission: DispatchWorkItem?
    private var cleanup: DispatchWorkItem?
    private(set) var lastSerial = 0
    private(set) var burstCount = 0
    var isActive: Bool { !emitters.isEmpty }

    func update(serial: Int, in parent: CALayer, rect: CGRect, reduceMotion: Bool, visible: Bool) {
        if reduceMotion || !visible { stop() }
        guard serial != lastSerial else { return }
        lastSerial = serial
        guard serial > 0, !reduceMotion, visible, rect.width > 0 else { return }
        stop()
        burstCount += 1
        let colors: [NSColor] = [.systemPink, .systemYellow, .systemCyan, .systemPurple, .systemGreen]
        for side in 0..<2 {
            let layer = CAEmitterLayer()
            layer.beginTime = CACurrentMediaTime()
            layer.frame = parent.bounds
            layer.emitterShape = .point
            layer.emitterPosition = CGPoint(x: side == 0 ? rect.minX + 10 : rect.maxX - 10, y: rect.maxY - 14)
            layer.zPosition = 100
            layer.emitterCells = colors.enumerated().map { index, color in
                let cell = CAEmitterCell()
                cell.contents = Self.paper
                cell.color = color.cgColor
                cell.birthRate = 55
                cell.lifetime = 1.6; cell.lifetimeRange = 0.3
                cell.velocity = 155; cell.velocityRange = 55
                cell.emissionLongitude = side == 0 ? -.pi / 3 : -.pi * 2 / 3
                cell.emissionRange = .pi / 3
                cell.yAcceleration = 180
                cell.spin = CGFloat(index.isMultiple(of: 2) ? 4 : -4); cell.spinRange = 5
                cell.scale = 0.75; cell.scaleRange = 0.3
                cell.alphaSpeed = -0.45
                return cell
            }
            parent.addSublayer(layer); emitters.append(layer)
        }
        let stopEmission = DispatchWorkItem { [weak self] in self?.emitters.forEach { $0.birthRate = 0 } }
        self.stopEmission = stopEmission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: stopEmission)
        let cleanup = DispatchWorkItem { [weak self] in self?.stop() }
        self.cleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: cleanup)
    }
    func stop() {
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
