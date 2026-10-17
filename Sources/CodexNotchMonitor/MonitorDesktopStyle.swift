import AppKit
import SwiftUI

/// Desktop windows have room for readable type; the menu bar and island keep
/// their existing compact typography and geometry.
enum MonitorDesktopTypography {
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let pageSubtitle = Font.system(size: 12)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let metadata = Font.system(size: 11)
    static let metadataMedium = Font.system(size: 11, weight: .medium)
    static let control = Font.system(size: 12, weight: .medium)
    static let controlLarge = Font.system(size: 13, weight: .medium)
    static let primaryMetric = Font.system(size: 28, weight: .semibold)
    static let secondaryMetric = Font.system(size: 20, weight: .semibold)
}

// CDS tokens and motion adapted from open-claude-ui ddf3aea (MIT).
// Copyright (c) 2026 Caho1. See Resources/ThirdPartyNotices.txt.
enum MonitorDesktopTheme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }

    static let controlCornerRadius: CGFloat = 8
    static let canvas = adaptive(0xf3f3f0, 0x1b1b19)
    static let surface = adaptive(0xfcfcfb, 0x21211e)
    static let elevated = adaptive(0xffffff, 0x282824)
    static let primaryText = adaptive(0x151515, 0xf5f5f5)
    static let secondaryText = adaptive(0x525252, 0xa3a3a3)
    static let tertiaryText = secondaryText.opacity(0.88)
    static let faintText = secondaryText.opacity(0.72)
    static let accent = adaptive(0xd97757, 0xe08264)
    // Data colors supplement the clay brand; they do not encode quota health.
    static let usageData = adaptive(0x39786e, 0x86b9ac)
    static let costData = accent
    static let costSecondary = adaptive(0x927044, 0xc6ad80)
    static let border = adaptive(0xe1e0d9, 0x383835)
    static let track = adaptive(0xf0efec, 0x1e1e1b)
    static let thumb = adaptive(0xffffff, 0x32322d)
    static let cardFill = surface
    static let subtleCardFill = adaptive(0xf7f7f5, 0x1e1e1b)
    static let prominentCardFill = elevated
    static let controlFill = elevated
    static let separator = border.opacity(0.55)
    static let hairline = border.opacity(0.45)
    static let chartGrid = primaryText.opacity(0.05)
    static let chartGuide = primaryText.opacity(0.12)
    static let contrastOutline = primaryText.opacity(0.45)
    static let selection = accent.opacity(0.13)
    static let windowBackground = canvas
    static let sidebarBackground = adaptive(0xf0efec, 0x171715)

    // Actual ClaudeMotionPresets.ts exports mapped to SwiftUI physics.
    static let selectionMotion = Animation.interpolatingSpring(mass: 1, stiffness: 320, damping: 28)
    static let pressMotion = Animation.interpolatingSpring(mass: 1, stiffness: 600, damping: 30)
    static let hoverMotion = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.15)
}

/// Desktop elevation only; native floating glass keeps its own material stack.
struct MonitorDesktopCardSurface: ViewModifier {
    var prominent = false
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(prominent ? MonitorDesktopTheme.prominentCardFill : MonitorDesktopTheme.cardFill)
                    .shadow(color: .black.opacity(scheme == .dark ? (prominent ? 0.16 : 0.08) : (prominent ? 0.07 : 0.035)),
                            radius: prominent ? 10 : 3, y: prominent ? 3 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(contrast == .increased ? MonitorDesktopTheme.contrastOutline : MonitorDesktopTheme.border.opacity(prominent ? 0.70 : 0.45), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

struct MonitorDesktopReveal: ViewModifier {
    var delay: Double = 0
    var reduceMotion: Bool = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let reduced = systemReduceMotion || reduceMotion
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduced || isVisible ? 0 : 10)
            .onAppear {
                withAnimation(reduced
                              ? .easeOut(duration: 0.16)
                              : MonitorDesktopTheme.selectionMotion.delay(delay)) {
                    isVisible = true
                }
            }
            .onDisappear { isVisible = false }
    }
}

/// Styles only the native Menu/Picker label; never intercepts selection or keyboard input.
struct MonitorMenuTrigger: ViewModifier {
    var minimumHeight: CGFloat = 34
    var horizontalPadding: CGFloat = 10
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .font(MonitorDesktopTypography.control)
            .padding(.horizontal, horizontalPadding).frame(minHeight: minimumHeight)
            .background(MonitorDesktopTheme.primaryText.opacity(enabled && hovered ? 0.045 : 0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(enabled && focused ? MonitorDesktopTheme.accent : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : MonitorDesktopTheme.hoverMotion, value: hovered)
    }
}

struct MonitorMenuLabel: View {
    let title: String
    var symbol: String? = nil
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MonitorDesktopTheme.secondaryText)
            }
            Text(title).lineLimit(1).foregroundStyle(MonitorDesktopTheme.primaryText)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MonitorDesktopTheme.secondaryText)
        }
        .modifier(MonitorMenuTrigger(minimumHeight: compact ? 30 : 34, horizontalPadding: compact ? 8 : 10))
    }
}

struct MonitorPopoverSurface: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .font(MonitorDesktopTypography.body)
            .foregroundStyle(MonitorDesktopTheme.primaryText)
            .padding(padding)
            .background(MonitorDesktopTheme.elevated)
            .tint(MonitorDesktopTheme.accent)
    }
}
