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
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? (primary && !destructive ? Color(white: 0.10) : Color.white) : Color.white.opacity(0.45))
                .islandGlass(RoundedRectangle(cornerRadius: 10, style: .continuous),
                    tint: enabled && destructive ? (emphasized ? Color(red: 0.68, green: 0.10, blue: 0.12).opacity(0.78) : Color.red.opacity(0.22))
                        : enabled && primary ? Color.white.opacity(0.90) : Color.white.opacity(0.04),
                    solidTint: enabled && destructive ? Color(red: 0.68, green: 0.18, blue: 0.19)
                        : enabled && primary ? Color(white: 0.94) : Color(white: 0.14),
                    clearSurface: !(enabled && ((primary && !destructive) || (destructive && emphasized))))
                .brightness(configuration.isPressed && enabled ? -0.08 : hovered && enabled ? 0.04 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}
