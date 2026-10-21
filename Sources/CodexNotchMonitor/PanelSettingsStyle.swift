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
                .foregroundStyle(configuration.isOn ? MonitorDesktopTheme.secondaryText : MonitorDesktopTheme.faintText)
                .accessibilityHidden(true)
            Button { configuration.isOn.toggle() } label: {
                Capsule().fill(configuration.isOn ? PanelSettingsTheme.clay : MonitorDesktopTheme.primaryText.opacity(0.14))
                    .frame(width: 36, height: 21)
                    .overlay {
                        Circle().fill(.white).frame(width: 17, height: 17)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            .offset(x: configuration.isOn ? 7.5 : -7.5)
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
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background {
                            if selection == option {
                                Capsule().fill(PanelSettingsTheme.thumb)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
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
        SettingsSection(title: title) { content }
    }
}

struct SettingsGlyph: View {
    let symbol: String
    var tint: Color = MonitorDesktopTheme.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(MonitorDesktopTypography.sectionLabel).tracking(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(MonitorDesktopTypography.metadata) }
            }
            .foregroundStyle(MonitorDesktopTheme.tertiaryText).padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .modifier(MonitorDesktopCardSurface(cornerRadius: 14))
        }
    }
}

struct SettingsRow<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MonitorDesktopTypography.rowTitle)
                .foregroundStyle(MonitorDesktopTheme.primaryText)
            if !detail.isEmpty {
                Text(detail).font(MonitorDesktopTypography.rowDetail)
                    .foregroundStyle(MonitorDesktopTheme.secondaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                SettingsGlyph(symbol: symbol)
                label.frame(minWidth: detail.isEmpty ? nil : 120, maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                control.fixedSize()
            }
            HStack(alignment: .top, spacing: 12) {
                SettingsGlyph(symbol: symbol)
                VStack(alignment: .leading, spacing: 10) {
                    label
                    control.fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 12).frame(minHeight: 58)
    }
}

/// The enclosing section already supplies the first 14 points of inset.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle().fill(MonitorDesktopTheme.hairline).frame(height: 0.5)
            .padding(.leading, 40).accessibilityHidden(true)
    }
}

struct SettingsStageSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MonitorDesktopTheme.surface)
                    .overlay {
                        RadialGradient(colors: [MonitorDesktopTheme.stageHighlight, .clear],
                                       center: .top, startRadius: 0, endRadius: geometry.size.width * 0.7)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.07), radius: 10, y: 3)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(contrast == .increased ? MonitorDesktopTheme.contrastOutline : MonitorDesktopTheme.border.opacity(0.5), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

struct SettingsStage<Accessory: View, Content: View>: View {
    let title: String
    let status: String
    let caption: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(MonitorDesktopTheme.accent).frame(width: 6, height: 6)
                    .opacity(reduceMotion || breathes ? 1 : 0.55)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                Text(status).font(MonitorDesktopTypography.metadata)
                    .foregroundStyle(MonitorDesktopTheme.secondaryText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(MonitorDesktopTheme.primaryText.opacity(0.05), in: Capsule())
                    .fixedSize()
            }
            content()
            ViewThatFits(in: .horizontal) {
                HStack { captionLabel; Spacer(minLength: 8); accessory() }
                VStack(alignment: .leading, spacing: 8) { captionLabel; accessory() }
            }
        }
        .padding(14).modifier(SettingsStageSurface())
        .task(id: reduceMotion) {
            breathes = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathes = true }
        }
        .onDisappear { breathes = false }
    }

    private var captionLabel: some View {
        Text(caption).font(MonitorDesktopTypography.metadata)
            .foregroundStyle(MonitorDesktopTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsStage where Accessory == EmptyView {
    init(title: String, status: String, caption: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.status = status; self.caption = caption
        self.accessory = { EmptyView() }; self.content = content
    }
}
