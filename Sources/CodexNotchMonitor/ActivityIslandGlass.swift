// Adapted from QuotaView v0.8.2 Build 2, d16307f4666f75b94a40cdb3933777a028d8fa8a.
// Copyright (c) 2026 Duoasa, MIT; full license: Resources/ThirdPartyNotices.txt.
import AppKit
import SwiftUI

// CDS content tokens and physical presets adapted from open-claude-ui ddf3aea (MIT).
// Copyright (c) 2026 Caho1. Native glass composition stays independent of these inks.
enum FloatingSurfaceTheme {
    private static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255)
    }
    static func primary(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0x151515 : 0xf5f5f5) }
    static func secondary(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0x525252 : 0xa3a3a3) }
    static func detail(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0x454442 : 0xd2d1c7) }
    static func tertiary(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0x6d6b67 : 0x898781) }
    static func faint(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0x898781 : 0x7b7974) }
    static func accent(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0xd97757 : 0xe08264) }
    static func usageData(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0x39786e : 0x86b9ac) }
    static func costData(_ scheme: ColorScheme = .dark) -> Color { accent(scheme) }
    static func surface(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0xfcfcfb : 0x151515) }
    static func track(_ scheme: ColorScheme = .dark) -> Color { primary(scheme).opacity(0.12) }
    static func chipFill(_ scheme: ColorScheme = .dark) -> Color { primary(scheme).opacity(0.06) }
    static func rowFill(_ scheme: ColorScheme = .dark) -> Color { primary(scheme).opacity(0.025) }
    static func separator(_ scheme: ColorScheme = .dark) -> Color { primary(scheme).opacity(scheme == .light ? 0.10 : 0.09) }
    static func hairline(_ scheme: ColorScheme = .dark) -> Color { primary(scheme).opacity(scheme == .light ? 0.075 : 0.065) }
    static func outline(_ scheme: ColorScheme = .dark, strong: Bool = false) -> Color { primary(scheme).opacity(strong ? 0.22 : 0.10) }
    static func popover(_ scheme: ColorScheme = .dark) -> Color { rgb(scheme == .light ? 0xffffff : 0x2c2c2a) }
    static let darkSurface = rgb(0x151515)
    static let success = Color(red: 0.36, green: 0.80, blue: 0.55)
    static func quotaHealth(_ remaining: Int?) -> Color {
        guard let remaining else { return .gray }
        if remaining < 20 { return .red }
        if remaining < 50 { return .orange }
        return success
    }
    static let danger = Color.red
    static let onDanger = Color.white
    static let dangerStrong = Color(red: 0.68, green: 0.10, blue: 0.12)
    static let dangerSolid = Color(red: 0.68, green: 0.18, blue: 0.19)
    static let selectionMotion = Animation.interpolatingSpring(mass: 1, stiffness: 320, damping: 28)
    static let pressMotion = Animation.interpolatingSpring(mass: 1, stiffness: 600, damping: 30)
    static let hoverMotion = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.15)
}

/// Compact type sizes are preserved so labels retain the existing panel geometry.
enum FloatingSurfaceTypography {
    static let title = Font.system(size: 15, weight: .semibold)
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    static let section = Font.system(size: 10.5, weight: .semibold)
    static let label = Font.system(size: 10.5)
    static let body = Font.system(size: 12)
    static let control = Font.system(size: 12, weight: .medium)
    static let action = Font.system(size: 12, weight: .semibold)
    static let dialogAction = Font.system(size: 11.5, weight: .medium)
    static let dialogPrimaryAction = Font.system(size: 11.5, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
    static let metadata = Font.system(size: 10)
    static let metadataStrong = Font.system(size: 10, weight: .semibold)
    static let badge = Font.system(size: 9.5, weight: .semibold)
    static let fine = Font.system(size: 9)
    static let fineStrong = Font.system(size: 9, weight: .semibold)
    static let micro = Font.system(size: 8, weight: .semibold)
    static let primaryMetric = Font.system(size: 21, weight: .semibold)
    static let resetMetric = Font.system(size: 26, weight: .semibold)
    static let heroMetric = Font.system(size: 34, weight: .semibold)
}

/// Feedback only: keeps the label's native glass, geometry and existing semantics.
struct FloatingSurfaceButtonStyle: ButtonStyle {
    var circularFocus = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(enabled && hovered ? 0.035 : 0)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .overlay {
                if circularFocus {
                    Circle().strokeBorder(enabled && focused ? FloatingSurfaceTheme.accent(scheme) : .clear, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(enabled && focused ? FloatingSurfaceTheme.accent(scheme) : .clear, lineWidth: 1.5)
                }
            }
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : FloatingSurfaceTheme.hoverMotion, value: hovered)
            .animation(reduceMotion ? nil : FloatingSurfaceTheme.pressMotion, value: configuration.isPressed)
    }
}

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

// Reused/adapted from QuotaView v0.8.3 Build 1, IslandConceptBoard.swift (MIT).
private struct IslandGlassColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.dark }
extension EnvironmentValues {
    var islandGlassColorScheme: ColorScheme {
        get { self[IslandGlassColorSchemeKey.self] }
        set { self[IslandGlassColorSchemeKey.self] = newValue }
    }
}

@MainActor
final class IslandSystemAppearance: ObservableObject {
    static let shared = IslandSystemAppearance()
    @Published private(set) var colorScheme: ColorScheme
    private var observation: NSKeyValueObservation?
    private init() {
        colorScheme = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                let scheme: ColorScheme = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
                if self?.colorScheme != scheme { self?.colorScheme = scheme }
            }
        }
    }
}

struct IslandGlassAppearanceContext: ViewModifier {
    var appearance: ActivityIslandGlassAppearance
    var material: ActivityIslandMaterial
    @ObservedObject private var system = IslandSystemAppearance.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.environment(\.islandGlassColorScheme,
            appearance.colorScheme(system: system.colorScheme, material: material, reduceTransparency: reduceTransparency))
    }
}

// Apply to exposed chrome only. Cards and the black header retain their dark environment.
struct IslandGlassChrome: ViewModifier {
    @Environment(\.islandGlassColorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.colorScheme, scheme)
            .foregroundStyle(FloatingSurfaceTheme.primary(scheme).opacity(0.90))
    }
}

struct IslandChromeIcon: View {
    let name: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(systemName: name).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(FloatingSurfaceTheme.accent(scheme))
            .frame(width: 24, height: 24)
            .islandGlass(Circle(), tint: .white.opacity(scheme == .light ? 0.22 : 0.04), clearSurface: true)
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
    @ObservedObject var model: ActivityIslandViewModel
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
        .modifier(IslandGlassChrome())
        .modifier(IslandGlassAppearanceContext(appearance: model.glassAppearance, material: model.material))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Island and floating capsule share this untinted native material.
struct IslandNativeBackdropMaterial<Outline: Shape>: ViewModifier {
    var shape: Outline
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandLiquidGlassEnabled) private var enabled
    func body(content: Content) -> some View {
        if !enabled || reduceTransparency {
            content.background(Color(white: 0.12), in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
