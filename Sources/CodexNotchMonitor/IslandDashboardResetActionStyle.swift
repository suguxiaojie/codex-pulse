// Reused from QuotaView f779531 IslandApprovalActionStyle (MIT), Copyright (c) 2026 Duoasa.
import SwiftUI

struct DashboardResetActionStyle: ButtonStyle {
    let primary: Bool
    var destructive = false
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, primary: primary, destructive: destructive, emphasized: emphasized)
    }
    private struct Surface: View {
        let configuration: Configuration
        let primary: Bool
        let destructive: Bool
        let emphasized: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? (primary && !destructive ? FloatingSurfaceTheme.accent() : (destructive ? FloatingSurfaceTheme.onDanger : FloatingSurfaceTheme.primary())) : FloatingSurfaceTheme.faint())
                .islandGlass(RoundedRectangle(cornerRadius: 10, style: .continuous),
                    tint: enabled && destructive ? (emphasized ? FloatingSurfaceTheme.dangerStrong.opacity(0.78) : FloatingSurfaceTheme.danger.opacity(0.22))
                        : enabled && primary ? FloatingSurfaceTheme.accent().opacity(0.20) : FloatingSurfaceTheme.chipFill(),
                    solidTint: enabled && destructive ? FloatingSurfaceTheme.dangerSolid
                        : enabled && primary ? FloatingSurfaceTheme.accent().opacity(0.25) : FloatingSurfaceTheme.darkSurface,
                    clearSurface: !(enabled && ((primary && !destructive) || (destructive && emphasized))))
                .brightness(configuration.isPressed && enabled ? -0.08 : hovered && enabled ? 0.04 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(enabled && focused ? (destructive ? FloatingSurfaceTheme.danger : FloatingSurfaceTheme.accent()) : .clear, lineWidth: 1.5))
                .animation(reduceMotion ? nil : FloatingSurfaceTheme.hoverMotion, value: hovered)
                .animation(reduceMotion ? nil : FloatingSurfaceTheme.pressMotion, value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}
