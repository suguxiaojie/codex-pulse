import AppKit
import SwiftUI

private struct WorkbenchPreviewHeightKey: EnvironmentKey { static let defaultValue = CGFloat.infinity }
extension EnvironmentValues {
    var workbenchPreviewHeight: CGFloat {
        get { self[WorkbenchPreviewHeightKey.self] }
        set { self[WorkbenchPreviewHeightKey.self] = newValue }
    }
}

/// Keep a preview visible while the inspector scrolls; narrow windows stack both.
struct SettingsWorkbench<Preview: View, Controls: View>: View {
    var isAdjusting = false
    var fullWidthPreview = false
    let preview: Preview
    let controls: Controls
    init(isAdjusting: Bool = false, fullWidthPreview: Bool = false, @ViewBuilder preview: () -> Preview, @ViewBuilder controls: () -> Controls) {
        self.isAdjusting = isAdjusting
        self.fullWidthPreview = fullWidthPreview
        self.preview = preview(); self.controls = controls()
    }
    var body: some View {
        GeometryReader { geometry in
            if fullWidthPreview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        preview.frame(maxWidth: .infinity)
                        controls
                    }.padding(16).padding(.bottom, 20)
                }.scrollDisabled(isAdjusting)
            } else if geometry.size.width >= 700 {
                HStack(alignment: .top, spacing: 30) {
                    ScrollView { preview.frame(maxWidth: .infinity, alignment: .topLeading)
                        .environment(\.workbenchPreviewHeight, max(180, geometry.size.height - 18)) }
                        .scrollIndicators(.hidden).frame(width: min(280, geometry.size.width * 0.34))
                    ScrollView { controls.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 28) }
                        .scrollDisabled(isAdjusting)
                }
                .padding(.horizontal, 16).padding(.top, 18)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        preview.frame(maxWidth: 460).frame(maxWidth: .infinity, alignment: .leading)
                        controls
                    }.padding(16).padding(.bottom, 20)
                }.scrollDisabled(isAdjusting)
            }
        }
    }
}

struct WorkbenchSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(MonitorDesktopTypography.metadataMedium)
                .foregroundStyle(MonitorDesktopTheme.tertiaryText).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchPreviewHeading: View {
    let title: String
    let status: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(status).monospacedDigit()
        }.font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.tertiaryText)
    }
}

/// The actual GlanceView and native glass, sharing current-account state.
struct GlanceSettingsPreview: View {
    @ObservedObject var store: MonitorStore
    let preferences: GlanceContentPreferences
    @State private var panelHeight: CGFloat = GlanceLayout.height
    @ObservedObject private var appearance = IslandSystemAppearance.shared
    @Environment(\.workbenchPreviewHeight) private var availableHeight
    private var count: Int {
        [preferences.showPrimaryQuota, preferences.showCreditBalance,
         preferences.showResetEntry, preferences.showDailyTokens, preferences.showThirtyDayTokens,
         preferences.showTokenActivity, preferences.showCostEstimate].filter { $0 }.count
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(PanelSettingsTheme.clay).frame(width: 5, height: 5)
                Text("实时面板").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("只读预览").font(.system(size: 10))
                    .foregroundStyle(PanelSettingsTheme.secondary)
            }
            .foregroundStyle(PanelSettingsTheme.primary)
            ProportionalSettingsPreview(width: GlanceLayout.width + 24, height: panelHeight + 24,
                                        maximumHeight: max(140, availableHeight - 70)) {
                ZStack {
                    if let image = ActivityIslandPreviewAssets.image("Wallpaper") {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: GlanceLayout.width + 24, height: panelHeight + 24).clipped()
                    }
                    LiveGlanceSettingsSurface(store: store, panelHeight: $panelHeight,
                        opacity: preferences.surfaceOpacity, colorScheme: appearance.colorScheme)
                        .frame(width: GlanceLayout.width, height: panelHeight).padding(12)
                }
                .frame(width: GlanceLayout.width + 24, height: panelHeight + 24)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("当前账号真实数据 · 只读预览")
                .font(.system(size: 10)).foregroundStyle(PanelSettingsTheme.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前账号实时面板预览")
        .accessibilityValue("已启用 \(count) 项，背景不透明度 \(Int((preferences.surfaceOpacity * 100).rounded()))%")
    }
}

private struct LiveGlanceSettingsSurface: NSViewRepresentable {
    let store: MonitorStore
    @Binding var panelHeight: CGFloat
    let opacity: Double
    let colorScheme: ColorScheme
    final class Coordinator {
        var composition: GlanceGlassCompositionView?
        var host: NSHostingView<AnyView>?
        var scheme: ColorScheme?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    private var content: AnyView {
        AnyView(GlanceView(store: store, onQuit: {}, onOpenCenter: { _ in }, onPreferredHeightChange: { height in
            guard height.isFinite && height > 0 else { return }
            DispatchQueue.main.async {
                if panelHeight != height { panelHeight = height }
            }
        }).environment(\.colorScheme, colorScheme).allowsHitTesting(false).accessibilityHidden(true))
    }
    func makeNSView(context: Context) -> NSView {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
        let result = GlanceGlassSurface.make(size: .init(width: GlanceLayout.width, height: panelHeight),
            contentView: host, surfaceOpacity: CGFloat(opacity), blendingMode: .withinWindow)
        context.coordinator.host = host; context.coordinator.composition = result.composition
        context.coordinator.scheme = colorScheme
        result.view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        return result.view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.composition?.updateSurfaceOpacity(CGFloat(opacity))
        if context.coordinator.scheme != colorScheme {
            context.coordinator.host?.rootView = content
            view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            context.coordinator.scheme = colorScheme
        }
    }
}

/// Layout at a stable logical size, then scale the whole scene rather than
/// compressing its individual labels or clipping fixed-size capsule content.
struct ProportionalSettingsPreview<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let maximumHeight: CGFloat
    let content: Content
    init(width: CGFloat, height: CGFloat, maximumHeight: CGFloat = .infinity, @ViewBuilder content: () -> Content) {
        self.width = width; self.height = height; self.maximumHeight = maximumHeight; self.content = content()
    }
    var body: some View {
        GeometryReader { proxy in
            content.frame(width: width, height: height)
                .scaleEffect(min(proxy.size.width / width, proxy.size.height / height), anchor: .topLeading)
        }
        .aspectRatio(width / height, contentMode: .fit)
        .frame(maxHeight: maximumHeight)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
