// Adapted from QuotaView v0.8.2 Build 2, d16307f4666f75b94a40cdb3933777a028d8fa8a.
// Copyright (c) 2026 Duoasa, MIT; full license: Resources/ThirdPartyNotices.txt.
import AppKit
import SwiftUI

private struct IslandGlassActiveKey: EnvironmentKey {
    static let defaultValue = true
}
private struct IslandLiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var islandLiquidGlassEnabled: Bool {
        get { self[IslandLiquidGlassEnabledKey.self] }
        set { self[IslandLiquidGlassEnabledKey.self] = newValue }
    }
    var islandGlassActive: Bool {
        get { self[IslandGlassActiveKey.self] }
        set { self[IslandGlassActiveKey.self] = newValue }
    }
}

// Shared native material: static styling, system batching, no per-frame work.
// Applied to cards and controls; chart cells and task archive icons stay plain.
struct IslandGlassSurface<Outline: InsettableShape>: ViewModifier {
    let outline: Outline
    var tint: Color = .black.opacity(0.28)
    var solidTint: Color = Color(white: 0.14)
    var clearSurface = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandGlassActive) private var active
    @Environment(\.islandLiquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.self) private var environment
    private var usesSolidFill: Bool { reduceTransparency || !liquidGlassEnabled }
    private var separatesDarkTint: Bool {
        guard #available(macOS 27.0, *) else { return false }
        let color = tint.resolve(in: environment)
        // macOS 27 composites near-black native tints as an opaque-looking
        // material. Keep light controls and semantic accent tints unchanged.
        return color.opacity > 0 && max(color.red, color.green, color.blue) <= 0.2
    }
    @available(macOS 26.0, *)
    private var material: Glass {
        guard active && !usesSolidFill else { return .identity }
        let glass: Glass = clearSurface ? .clear : .regular
        // Clear glass avoids regular's pale backing under our separate dark
        // fill. The fill supplies the charcoal tone and limited backdrop color.
        return separatesDarkTint ? .clear : glass.tint(tint)
    }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Keep the content/anchor identity when a page becomes hidden.
            // Identity disables the material without replacing the card subtree.
            content
                .background {
                    if active && !usesSolidFill && separatesDarkTint { outline.fill(tint).allowsHitTesting(false) }
                }
                .glassEffect(material, in: outline)
                .background {
                    if active && usesSolidFill { outline.fill(solidTint) }
                }
                .overlay {
                    if active && usesSolidFill {
                        outline.strokeBorder(.white.opacity(reduceTransparency ? 0.30 : 0.12), lineWidth: 0.5).allowsHitTesting(false)
                    }
                }
        } else {
            content.background {
                if active {
                    if usesSolidFill { outline.fill(solidTint) }
                    else if clearSurface { outline.fill(.ultraThinMaterial) }
                    else { outline.fill(.regularMaterial).overlay(outline.fill(solidTint.opacity(0.85))) }
                }
            }
            .overlay {
                if active {
                    outline.strokeBorder(.white.opacity(reduceTransparency ? 0.30 : 0.24), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

extension View {
    func islandGlass<Outline: InsettableShape>(_ outline: Outline, tint: Color = .black.opacity(0.28), solidTint: Color = Color(white: 0.14), clearSurface: Bool = false) -> some View {
        modifier(IslandGlassSurface(outline: outline, tint: tint, solidTint: solidTint, clearSurface: clearSurface))
    }
}


struct IslandNotchShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Vibe Island's visible reference uses small concave top corners and
        // larger convex bottom corners. Scale both continuously on expansion.
        let lip = min(bottomRadius * 2 / 3, min(16, min(w / 6, h / 3)))
        let bottom = min(bottomRadius, min((w - lip * 2) / 2, h / 2))
        let arc: CGFloat = 0.5522847498
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // Small concave upper corners join the screen, with no horizontal shelf.
        p.addCurve(to: CGPoint(x: w - lip, y: lip), control1: CGPoint(x: w - lip * arc, y: 0), control2: CGPoint(x: w - lip, y: lip * (1 - arc)))
        p.addLine(to: CGPoint(x: w - lip, y: h - bottom))
        p.addCurve(to: CGPoint(x: w - lip - bottom, y: h), control1: CGPoint(x: w - lip, y: h - bottom * (1 - arc)), control2: CGPoint(x: w - lip - bottom * (1 - arc), y: h))
        p.addLine(to: CGPoint(x: lip + bottom, y: h))
        p.addCurve(to: CGPoint(x: lip, y: h - bottom), control1: CGPoint(x: lip + bottom * (1 - arc), y: h), control2: CGPoint(x: lip, y: h - bottom * (1 - arc)))
        p.addLine(to: CGPoint(x: lip, y: lip))
        p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: lip, y: lip * (1 - arc)), control2: CGPoint(x: lip * arc, y: 0))
        p.closeSubpath(); return p
    }
}


@MainActor
final class IslandGlassGeometry: ObservableObject {
    struct Value: Equatable {
        var rect: CGRect
        var radius: CGFloat
        var compact: Bool
    }
    @Published private(set) var value: Value
    @Published private(set) var degree: Double
    @Published private(set) var generation = 0
    private var animationDeadline: CFTimeInterval = 0

    init(value: Value, degree: Double) {
        self.value = value
        self.degree = degree
    }

    func update(value: Value, degree: Double, animated: Bool) {
        if self.degree != degree { self.degree = degree }
        if animated {
            guard self.value != value else { return }
            // Stable identity lets SwiftUI retarget from the current interpolated
            // geometry, including an immediate reversal before the first ends.
            animationDeadline = CACurrentMediaTime() + ActivityIslandSurfaceMotion.duration
            withAnimation(ActivityIslandSurfaceMotion.animation) { self.value = value }
        } else {
            let wasAnimating = animationDeadline > CACurrentMediaTime()
            guard self.value != value || wasAnimating else { return }
            animationDeadline = 0
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.value = value
                // Snap only when motion is explicitly disabled or the window
                // geometry changes; normal page changes never reset identity.
                if wasAnimating { generation &+= 1 }
            }
        }
    }

    func stop() {
        guard animationDeadline > CACurrentMediaTime() else { return }
        animationDeadline = 0
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { generation &+= 1 }
    }

}


struct IslandExpandedGlassBackdrop: View {
    @ObservedObject var geometry: IslandGlassGeometry

    var body: some View {
        let value = geometry.value
        let shape = IslandNotchShape(bottomRadius: value.radius)
        let stops = ActivityIslandGlassDegree.gradientStops(geometry.degree)
        ZStack(alignment: .topLeading) {
            Color.clear
            Color.clear
                .frame(width: value.rect.width, height: value.rect.height)
                .modifier(IslandNativeBackdropMaterial(shape: shape))
                .overlay {
                    // Only the shade is clipped. Native glass owns its contour.
                    LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .clipShape(shape)
                }
                .overlay { shape.fill(.black).opacity(value.compact ? 1 : 0) }
                .position(x: value.rect.midX, y: value.rect.midY)
        }
        .id(geometry.generation)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct IslandNativeBackdropMaterial: ViewModifier {
    var shape: IslandNotchShape
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
