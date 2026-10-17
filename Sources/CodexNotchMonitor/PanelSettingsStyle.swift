// CDS token and motion adaptation from open-claude-ui ddf3aea (MIT).
// Copyright (c) 2026 Caho1. See Resources/ThirdPartyNotices.txt.
import AppKit
import SwiftUI

/// Settings controls share the Monitor Center's CDS palette and physics.
enum PanelSettingsTheme {
    static let canvas = MonitorDesktopTheme.canvas
    static let surface = MonitorDesktopTheme.surface
    static let elevated = MonitorDesktopTheme.elevated
    static let primary = MonitorDesktopTheme.primaryText
    static let secondary = MonitorDesktopTheme.secondaryText
    static let clay = MonitorDesktopTheme.accent
    static let border = MonitorDesktopTheme.border
    static let track = MonitorDesktopTheme.track
    static let thumb = MonitorDesktopTheme.thumb
    static let sliderThumb = Color(white: 0.96)
    static let selectionMotion = MonitorDesktopTheme.selectionMotion
    static let pressMotion = MonitorDesktopTheme.pressMotion
    static let hoverMotion = MonitorDesktopTheme.hoverMotion

    static var divider: some View {
        Rectangle().fill(border.opacity(0.45)).frame(height: 0.5).accessibilityHidden(true)
    }
}

/// Keeps native Toggle accessibility while making the on state legible in inactive windows too.
struct PanelSettingsToggleStyle: ToggleStyle {
    var onTitle = "显示"
    var offTitle = "隐藏"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Text(configuration.isOn ? onTitle : offTitle)
                .font(.system(size: 11))
                .foregroundStyle(PanelSettingsTheme.secondary)
                .accessibilityHidden(true)
            Button { configuration.isOn.toggle() } label: {
                Capsule().fill(configuration.isOn ? PanelSettingsTheme.clay : PanelSettingsTheme.border)
                    .frame(width: 34, height: 20)
                    .overlay {
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            .offset(x: configuration.isOn ? 7 : -7)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focused)
            .overlay(Capsule().strokeBorder(enabled && focused ? PanelSettingsTheme.clay : .clear, lineWidth: 1.5).padding(-3))
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : PanelSettingsTheme.pressMotion, value: configuration.isOn)
    }
}

struct PanelSettingsSegments: View {
    let options: [String]
    @Binding var selection: String
    var width: CGFloat = 184
    var title = "面板设置分组"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @FocusState private var focused: String?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
                    Text(option)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == option ? PanelSettingsTheme.primary : PanelSettingsTheme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if selection == option {
                                Capsule().fill(PanelSettingsTheme.thumb)
                                    .matchedGeometryEffect(id: "panel-selection", in: namespace)
                            }
                        }
                }
                .buttonStyle(PanelSettingsPressStyle())
                .focused($focused, equals: option)
                .overlay(Capsule().strokeBorder(focused == option ? PanelSettingsTheme.clay : .clear, lineWidth: 1.5))
                .accessibilityValue(selection == option ? "已选择" : "未选择")
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(PanelSettingsTheme.track, in: Capsule())
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onMoveCommand { direction in
            guard let index = options.firstIndex(of: focused ?? selection) else { return }
            let next: Int
            switch direction {
            case .left: next = max(0, index - 1)
            case .right: next = min(options.count - 1, index + 1)
            default: return
            }
            focused = options[next]
            select(options[next])
        }
    }

    private func select(_ option: String) {
        withAnimation(reduceMotion ? nil : PanelSettingsTheme.selectionMotion) { selection = option }
    }
}

private struct PanelSettingsPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(PanelSettingsTheme.primary.opacity(enabled && hovered ? 0.035 : 0), in: Capsule())
            .scaleEffect(enabled && !reduceMotion && configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : PanelSettingsTheme.hoverMotion, value: hovered)
            .animation(reduceMotion ? nil : PanelSettingsTheme.pressMotion, value: configuration.isPressed)
    }
}

struct PanelSettingsActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? PanelSettingsTheme.clay : PanelSettingsTheme.secondary)
            .padding(.horizontal, 10).frame(minHeight: 32)
            .background(prominent ? PanelSettingsTheme.clay.opacity(enabled && hovered ? 0.18 : 0.10)
                        : PanelSettingsTheme.primary.opacity(enabled && hovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(enabled && focused ? PanelSettingsTheme.clay : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : PanelSettingsTheme.hoverMotion, value: hovered)
            .animation(reduceMotion ? nil : PanelSettingsTheme.pressMotion, value: configuration.isPressed)
    }
}

struct PanelSettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelSettingsTheme.primary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .modifier(MonitorDesktopCardSurface())
        }
    }
}
