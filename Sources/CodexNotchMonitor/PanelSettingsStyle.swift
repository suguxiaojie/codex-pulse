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
                                MonitorSegmentThumb()
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
        .modifier(MonitorSegmentTrack())
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
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.06)], startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.06)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                // A short ember tick anchors each group without adding another box.
                Capsule().fill(MonitorDesktopTheme.accent.opacity(0.85)).frame(width: 3, height: 11)
                    .accessibilityHidden(true)
                Text(title).font(MonitorDesktopTypography.sectionLabel).tracking(0.8)
                    .foregroundStyle(MonitorDesktopTheme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.tertiaryText) }
            }
            .padding(.horizontal, 4)
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
    var numericDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let control: Control

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MonitorDesktopTypography.rowTitle)
                .foregroundStyle(MonitorDesktopTheme.primaryText)
            if !detail.isEmpty {
                Text(detail).font(MonitorDesktopTypography.rowDetail)
                    .contentTransition(numericDetail && !reduceMotion ? .numericText() : .identity)
                    .animation(numericDetail && !reduceMotion ? PanelSettingsTheme.selectionMotion : nil, value: detail)
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
                        RadialGradient(colors: [MonitorDesktopTheme.accent.opacity(scheme == .dark ? 0.10 : 0.06), .clear],
                                       center: .top, startRadius: 0, endRadius: geometry.size.width * 0.7)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.07), radius: 14, y: 6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(contrast == .increased
                    ? AnyShapeStyle(MonitorDesktopTheme.contrastOutline)
                    : AnyShapeStyle(LinearGradient(colors: [MonitorDesktopTheme.rimHighlight.opacity(scheme == .dark ? 0.12 : 0.5),
                                                            MonitorDesktopTheme.rimHighlight.opacity(scheme == .dark ? 0.03 : 0.2)],
                                                   startPoint: .top, endPoint: .bottom)), lineWidth: 0.75)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SettingsStageIndicator(reduceMotion: reduceMotion).frame(width: 6, height: 6)
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
    }

    private var captionLabel: some View {
        Text(caption).font(MonitorDesktopTypography.metadata)
            .foregroundStyle(MonitorDesktopTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsStageIndicator: NSViewRepresentable {
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SettingsStageIndicatorView { SettingsStageIndicatorView() }
    func updateNSView(_ view: SettingsStageIndicatorView, context: Context) {
        view.reduceMotion = reduceMotion
        view.layer?.backgroundColor = NSColor(MonitorDesktopTheme.accent).cgColor
        view.updatePlayback()
    }
}

private final class SettingsStageIndicatorView: NSView {
    var reduceMotion = false
    private var observers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name == NSWindow.willCloseNotification { self?.layer?.removeAnimation(forKey: "breath") }
                        else { self?.updatePlayback() }
                    }
                })
            }
        }
        updatePlayback()
    }
    override func viewDidHide() { super.viewDidHide(); updatePlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); updatePlayback() }

    func updatePlayback() {
        guard !reduceMotion, !isHiddenOrHasHiddenAncestor, let window,
              window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) else {
            layer?.removeAnimation(forKey: "breath")
            return
        }
        guard layer?.animation(forKey: "breath") == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.55
        animation.toValue = 1
        animation.duration = 2.4
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(animation, forKey: "breath")
    }
}

extension SettingsStage where Accessory == EmptyView {
    init(title: String, status: String, caption: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.status = status; self.caption = caption
        self.accessory = { EmptyView() }; self.content = content
    }
}
