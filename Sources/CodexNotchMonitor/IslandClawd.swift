import AppKit

/// Clawd on its original pixel grid. One unit is one sprite pixel; the origin sits at the feet and the body extends upward.
struct IslandClawdPose: Equatable {
    enum Arms: Equatable { case side, up, down, hang, oneLeft, oneRight, oneWave }
    enum Eyes: Equatable { case open, squint, closed, wide, happy, cross }
    var arms = Arms.hang
    var armRaised = false
    var eyes = Eyes.open
    var look = CGSize.zero
    var legLift = [false, false, false, false]
    var legsTucked = false
    var squashY: CGFloat = 1
    /// Springy secondary motion: body stretch (anchored at the top of the body), leg trail angle, eye drop.
    var stretch = CGSize(width: 1, height: 1)
    var legSwing: CGFloat = 0
    var eyeDrop: CGFloat = 0

    init(mood: IslandMascotMood, arms: Arms = .hang) {
        self.arms = arms
        switch mood {
        case .think: eyes = .open
        case .tool: eyes = .squint
        case .approve, .reply: eyes = .wide
        case .done: eyes = .happy
        case .fail: eyes = .cross
        case .idle: eyes = .closed; legsTucked = true
        }
    }
}

enum IslandClawdSprite {
    enum Ink: Equatable { case body, arm, leg, eye, glint }
    struct Pixel: Equatable { var rect: CGRect; var ink: Ink }
    static let width: CGFloat = 11
    static let height: CGFloat = 6
    static let bodyTop: CGFloat = -6
    /// Distance from the gripping hands to the feet while hanging, in sprite pixels.
    static let hangDepth: CGFloat = 8.4

    static func pixels(_ pose: IslandClawdPose) -> [Pixel] {
        var result: [Pixel] = []
        let sy = pose.squashY
        func add(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ ink: Ink = .body) {
            result.append(.init(rect: CGRect(x: x, y: y * sy, width: w, height: h * sy), ink: ink))
        }
        let ox: CGFloat = -5.5, top = bodyTop
        add(ox + 2, top, 7, 4)
        // Hanging arms reach 0.6 px into the body so they stay joined while it stretches.
        switch pose.arms {
        case .side: add(ox, top + 2, 2, 1, .arm); add(ox + 9, top + 2, 2, 1, .arm)
        case .up:
            let a: CGFloat = pose.armRaised ? 1 : 0
            add(ox + 1, top - 1 - a, 1, 3 + a, .arm); add(ox + 9, top - 2 + a, 1, 4 - a, .arm)
        case .down: add(ox + 1, top + 3, 1, 1, .arm); add(ox + 9, top + 3, 1, 1, .arm)
        case .hang: add(ox + 2, top - 2.4, 1, 3, .arm); add(ox + 8, top - 2.4, 1, 3, .arm)
        case .oneLeft: add(ox + 2, top - 2.4, 1, 3, .arm); add(ox + 9, top + 2.5, 1, 1.5, .arm)
        case .oneRight: add(ox + 8, top - 2.4, 1, 3, .arm); add(ox + 1, top + 2.5, 1, 1.5, .arm)
        case .oneWave:
            add(ox + 2, top - 2.4, 1, 3, .arm)
            if pose.armRaised { add(ox + 8, top - 2.4, 1, 3, .arm) } else { add(ox + 9, top + 1, 2, 1, .arm) }
        }
        if pose.legsTucked { add(ox + 2, top + 4, 7, 0.6, .leg) }
        else {
            for (index, column) in [2, 4, 6, 8].enumerated() {
                add(ox + CGFloat(column), top + 4, 1, pose.legLift[index] ? 1 : 2, .leg)
            }
        }
        for column in [ox + 3, ox + 7] {
            let x = column + pose.look.width, y = top + 1 + pose.look.height + pose.eyeDrop
            switch pose.eyes {
            case .open: add(x, y, 1, 2, .eye)
            case .squint: add(x - 0.2, y + 0.8, 1.4, 0.55, .eye)
            case .closed: add(x - 0.25, y + 1.2, 1.5, 0.45, .eye)
            case .wide: add(x - 0.15, y - 0.2, 1.3, 2.3, .eye)
            case .happy: add(x - 0.4, y + 1, 0.6, 0.6, .eye); add(x + 0.2, y + 0.4, 0.6, 0.6, .eye); add(x + 0.8, y + 1, 0.6, 0.6, .eye)
            case .cross:
                for step in 0..<3 {
                    let d = CGFloat(step) * 0.55
                    add(x - 0.3 + d, y + 0.1 + d, 0.6, 0.6, .eye)
                    if step != 1 { add(x + 0.8 - d, y + 0.1 + d, 0.6, 0.6, .eye) }
                }
            }
        }
        return result
    }

    static func color(_ ink: Ink) -> NSColor {
        switch ink {
        case .body, .arm: return NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
        case .leg: return NSColor(srgbRed: 0xB8 / 255.0, green: 0x5F / 255.0, blue: 0x40 / 255.0, alpha: 1)
        case .eye: return NSColor(srgbRed: 0x1B / 255.0, green: 0x13 / 255.0, blue: 0x10 / 255.0, alpha: 1)
        case .glint: return NSColor.white.withAlphaComponent(0.85)
        }
    }
    static func shaded(_ color: NSColor, _ amount: CGFloat) -> NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        func f(_ v: CGFloat) -> CGFloat { amount > 0 ? v + (1 - v) * amount : v * (1 + amount) }
        return NSColor(srgbRed: f(c.redComponent), green: f(c.greenComponent), blue: f(c.blueComponent), alpha: c.alphaComponent)
    }

    /// Fills a block snapped to whole device pixels, so the sprite stays crisp at any point size.
    static func fillPixelBlock(_ rect: CGRect, color: NSColor, in context: CGContext) {
        let device = context.convertToDeviceSpace(rect)
        let minX = device.minX.rounded(), minY = device.minY.rounded()
        let snapped = CGRect(x: minX, y: minY, width: max(1, device.maxX.rounded() - minX), height: max(1, device.maxY.rounded() - minY))
        context.setFillColor(color.cgColor)
        context.fill(context.convertToUserSpace(snapped))
    }

    /// Flat pixel-art blocks, as in Claude Code's original Clawd.
    /// Draws with the feet at the current origin; callers own the transform.
    static func draw(_ pose: IslandClawdPose, pixel: CGFloat, in context: CGContext, alpha: CGFloat = 1) {
        let items = pixels(pose)
        context.saveGState(); defer { context.restoreGState() }
        context.setShouldAntialias(false)
        func block(_ item: Pixel) {
            let r = item.rect
            let base = color(item.ink)
            fillPixelBlock(CGRect(x: r.minX * pixel, y: r.minY * pixel, width: r.width * pixel, height: r.height * pixel),
                           color: base.withAlphaComponent(base.alphaComponent * alpha), in: context)
        }
        // Arms belong to the grip and do not stretch with the body.
        items.filter { $0.ink == .arm }.forEach(block)
        context.saveGState()
        let top = bodyTop * pixel
        context.translateBy(x: 0, y: top); context.scaleBy(x: pose.stretch.width, y: pose.stretch.height); context.translateBy(x: 0, y: -top)
        for item in items where item.ink == .leg {
            // Legs pivot where they meet the body and trail the swing.
            context.saveGState()
            let pivot = CGPoint(x: item.rect.midX * pixel, y: item.rect.minY * pixel)
            let index = items.filter { $0.ink == .leg }.firstIndex(of: item) ?? 0
            context.translateBy(x: pivot.x, y: pivot.y)
            context.rotate(by: pose.legsTucked ? 0 : pose.legSwing * (index % 2 == 0 ? 0.85 : 1.15))
            context.translateBy(x: -pivot.x, y: -pivot.y)
            block(item)
            context.restoreGState()
        }
        items.filter { $0.ink == .body }.forEach(block)
        items.filter { $0.ink == .eye || $0.ink == .glint }.forEach(block)
        context.restoreGState()
    }
}

