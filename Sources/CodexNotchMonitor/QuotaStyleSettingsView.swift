// Activity Island child page, adapted from QuotaView d16307f (MIT).
// Settings follow the app desktop theme; the QuotaView preview renderer is retained.
import SwiftUI

struct QuotaStyleSettingsView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(ActivityIslandPreferenceKey.material) private var material = ActivityIslandMaterial.liquidGlass.rawValue
    @AppStorage(ActivityIslandPreferenceKey.glassDegree) private var glassDegree = 0.45
    @AppStorage(ActivityIslandPreferenceKey.expandedWidth) private var expandedWidth = 680.0
    @AppStorage(ActivityIslandPreferenceKey.progressEffect) private var effect = ActivityIslandProgressEffect.dropField.rawValue
    @AppStorage(ActivityIslandPreferenceKey.privacyMode) private var privacyMode = false
    @AppStorage(ActivityIslandPreferenceKey.floatingUsageEnabled) private var floatingUsageEnabled = true
    @AppStorage(ActivityIslandPreferenceKey.usageCapsuleTone) private var usageCapsuleTone = ActivityIslandUsageCapsuleTone.dark.rawValue
    @AppStorage(ActivityIslandPreferenceKey.automaticPopup) private var automaticPopup = true
    @AppStorage(ActivityIslandPreferenceKey.expandedHold) private var expandedHold = 3.0
    @State private var previewVisible = true
    @State private var geometry = ActivityIslandWidthGeometry.current()


    private var widthBinding: Binding<Double> {
        Binding(get: { min(geometry.settingsRange.upperBound, max(geometry.settingsRange.lowerBound, expandedWidth)) },
                set: { expandedWidth = ActivityIslandPreferences.normalizedWidth($0) })
    }
    private var durationBinding: Binding<Int> {
        Binding(get: { Int(ActivityIslandPreferences.normalizedDuration(expandedHold)) }, set: { expandedHold = Double($0) })
    }
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                settingsGroup("外观预览", status: "更改即时生效") {
                    ActivityIslandDesktopPreview(material: ActivityIslandMaterial(rawValue: material) ?? .liquidGlass,
                        degree: glassDegree, effect: ActivityIslandProgressEffect(rawValue: effect) ?? .dropField,
                        expandedWidth: geometry.expandedWidth(preferred: expandedWidth),
                        maximumExpandedWidth: geometry.maximumExpandedWidth,
                        animated: previewVisible, reduceMotion: systemReduceMotion, privacyMode: privacyMode,
                        floatingUsageEnabled: floatingUsageEnabled,
                        usageCapsuleTone: ActivityIslandUsageCapsuleTone(rawValue: usageCapsuleTone) ?? .dark)
                        .frame(height: 210).padding(.top, 14)
                    Text("预览使用示例数据，实际任务与额度以本机数据为准。")
                        .font(MonitorDesktopTypography.metadata)
                        .foregroundStyle(MonitorDesktopTheme.tertiaryText).padding(.vertical, 12)
                }
                settingsGroup("材质与尺寸") {
                    materialOption(.liquidGlass, subtitle: "通透背景、自然高光与深色玻璃卡片。")
                    divider
                    materialOption(.classic, subtitle: "使用纯色背景，关闭玻璃材质。")
                    if material == ActivityIslandMaterial.liquidGlass.rawValue {
                        divider
                        settingRow("玻璃程度", detail: "调整黑色遮罩与玻璃区域的比例。") {
                            VStack(alignment: .trailing, spacing: 5) {
                                IslandSettingsSlider(value: $glassDegree, range: 0.2...0.8, step: 0.01, title: "玻璃程度").accessibilityLabel("玻璃程度")
                                    .accessibilityValue("黑色区域 \(Int(((1 - glassDegree) * 100).rounded()))%")
                                Text("黑色区域 \(Int(((1 - glassDegree) * 100).rounded()))%")
                                    .font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.tertiaryText).monospacedDigit()
                            }.frame(width: 220)
                        }
                    }
                    divider
                    settingRow("展开宽度", detail: "调整任务列表宽度，刘海两侧保留安全空间。") {
                        VStack(alignment: .trailing, spacing: 5) {
                            IslandSettingsSlider(value: widthBinding, range: geometry.settingsRange, step: 1, title: "展开宽度").accessibilityLabel("展开宽度")
                            Text("\(Int(widthBinding.wrappedValue)) pt").font(MonitorDesktopTypography.metadata)
                                .foregroundStyle(MonitorDesktopTheme.tertiaryText).monospacedDigit()
                        }.frame(width: 220)
                    }
                }
                if #unavailable(macOS 26.0) {
                    Text("原生液态玻璃需要 macOS 26 或更新版本；当前系统使用半透明材质。")
                        .font(MonitorDesktopTypography.body).foregroundStyle(MonitorDesktopTheme.tertiaryText)
                }
                settingsGroup("显示与隐私") {
                    toggle("悬浮用量胶囊", detail: "在灵动岛下方显示剩余额度和重置倒计时。", value: $floatingUsageEnabled)
                    divider
                    settingRow("胶囊配色", detail: "深色为染色玻璃，浅色为清透玻璃。") {
                        IslandSettingsTonePicker(selection: $usageCapsuleTone)
                            .frame(width: 180).disabled(!floatingUsageEnabled)
                    }
                    divider
                    toggle("隐私模式", detail: "隐藏任务内容、模型与账户数据。", value: $privacyMode)
                }
                settingsGroup("任务特效") {
                    HStack(spacing: 12) {
                        ForEach(ActivityIslandProgressEffect.allCases) { option in
                            Button { effect = option.rawValue } label: { Text(option.title) }
                                .buttonStyle(IslandSettingsEffectOptionStyle(effect: option, selected: effect == option.rawValue))
                                .accessibilityLabel(option.title).accessibilityValue(effect == option.rawValue ? "已选择" : "未选择")
                        }
                    }.padding(.vertical, 14)
                }
                settingsGroup("自动展开") {
                    toggle("自动弹出", detail: "新任务、完成或待确认时自动展开。", value: $automaticPopup)
                    divider
                    settingRow("停留时间", detail: "自动展开后停留的时长；待确认或固定时保持展开。") {
                        Picker("停留时间", selection: durationBinding) {
                            ForEach(1...10, id: \.self) { Text("\($0) 秒").tag($0) }
                        }.pickerStyle(.menu).labelsHidden().frame(width: 110).disabled(!automaticPopup)
                    }
                }
            }
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
        }.font(MonitorDesktopTypography.body).foregroundStyle(MonitorDesktopTheme.primaryText)
            .tint(MonitorDesktopTheme.selection).controlSize(.regular).preferredColorScheme(.dark)
            .onAppear { previewVisible = true; geometry = .current() }
            .onDisappear { previewVisible = false }
            .onChange(of: material) { _ in signal() }.onChange(of: glassDegree) { _ in signal() }
            .onChange(of: expandedWidth) { _ in signal() }.onChange(of: effect) { _ in signal() }
            .onChange(of: privacyMode) { _ in signal() }.onChange(of: automaticPopup) { _ in signal() }
            .onChange(of: expandedHold) { _ in signal() }
            .onChange(of: floatingUsageEnabled) { _ in signal() }.onChange(of: usageCapsuleTone) { _ in signal() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in geometry = .current() }
    }
    private func signal() { ActivityIslandPreferenceSignal.post() }
    private var divider: some View { Divider().overlay(MonitorDesktopTheme.separator) }
    private func settingsGroup<Content: View>(_ title: String, status: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(MonitorDesktopTypography.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let status { Text(status).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.tertiaryText) }
            }.padding(.vertical, 16)
            divider
            content()
        }.padding(.horizontal, 18)
            .background(MonitorDesktopTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MonitorDesktopTheme.separator, lineWidth: 1) }
    }
    private func rowLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(MonitorDesktopTypography.rowTitle)
            Text(detail).font(MonitorDesktopTypography.body).foregroundStyle(MonitorDesktopTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                rowLabel(title, detail: detail).frame(minWidth: 210, maxWidth: .infinity, alignment: .leading)
                control().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                rowLabel(title, detail: detail)
                HStack { Spacer(minLength: 0); control() }
            }
        }.font(MonitorDesktopTypography.control).padding(.vertical, 14).frame(minHeight: 68)
    }
    private func toggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        settingRow(title, detail: detail) {
            Toggle(title, isOn: value).labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: MonitorDesktopTheme.selection)).controlSize(.regular)
                .accessibilityLabel(title)
        }
    }
    private func materialOption(_ option: ActivityIslandMaterial, subtitle: String) -> some View {
        Button { material = option.rawValue } label: {
            settingRow(option.title, detail: subtitle) {
                Image(systemName: material == option.rawValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(material == option.rawValue ? MonitorDesktopTheme.selection : MonitorDesktopTheme.tertiaryText)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityLabel(option.title)
            .accessibilityHint(subtitle).accessibilityValue(material == option.rawValue ? "已选择" : "未选择")
    }

}

struct ActivityIslandDesktopPreview: View {
    let material: ActivityIslandMaterial
    let degree: Double
    let effect: ActivityIslandProgressEffect
    let expandedWidth: Double
    var maximumExpandedWidth: CGFloat = 680
    let animated: Bool
    let reduceMotion: Bool
    var privacyMode = false
    var floatingUsageEnabled = true
    var usageCapsuleTone: ActivityIslandUsageCapsuleTone = .dark
    private var sample: ActivitySessionSnapshot {
        ActivitySessionSnapshot(sessionID: "preview", turnID: "preview", projectID: "preview", projectName: "示例项目",
            title: "整理项目资料", phase: .usingTool, actionText: "汇总文档，准备更新说明", updatedAt: Date(),
            tokenUsage: .init(sessionID: "preview", turnID: "preview", total: 128000),
            modelName: "gpt-6.1-sol", reasoningEffort: "high", startedAt: Date().addingTimeInterval(-120), sessionTotalTokens: 128000)
    }
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 24, 510 * min(1, CGFloat(expandedWidth) / max(1, maximumExpandedWidth)))
            let shape = IslandNotchShape(bottomRadius: 24)
            ZStack(alignment: .top) {
                if let image = ActivityIslandPreviewAssets.image("Wallpaper") {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("1 个会话").font(.system(size: 12, weight: .medium))
                        Spacer()
                        icon("pin"); icon("chevron.up")
                    }.padding(.horizontal, 28).frame(height: 36)
                    ActivityIslandTaskCard(row: privacyMode ? sample.hidingDetails() : sample, animated: animated,
                        rowHeight: 62, selected: true, effect: effect, reduceMotion: reduceMotion, preview: true)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                    HStack { Text("1 个会话"); Spacer(); Text("1 工作中"); icon("arrow.clockwise"); icon("gearshape") }
                        .font(.system(size: 12)).padding(.horizontal, 28).padding(.bottom, 12).frame(height: 36)
                }.frame(width: width).background {
                    if material == .classic { shape.fill(.black) }
                    else {
                        ZStack {
                            if #available(macOS 26.0, *) { Color.clear.glassEffect(.clear, in: shape) }
                            else { shape.fill(.regularMaterial) }
                            LinearGradient(stops: ActivityIslandGlassDegree.gradientStops(degree), startPoint: .top, endPoint: .bottom).clipShape(shape)
                        }
                    }
                }
                if floatingUsageEnabled && !privacyMode {
                    IslandUsageCapsuleContent(windows: [
                        .init(usedPercent: 28, windowDurationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 12000)),
                        .init(usedPercent: 54, windowDurationMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 345600))
                    ], current: true, now: Date(timeIntervalSince1970: 0), tone: usageCapsuleTone)
                    .padding(.top, 166)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }.environment(\.islandLiquidGlassEnabled, material == .liquidGlass)
            .allowsHitTesting(false).accessibilityElement(children: .ignore)
            .accessibilityLabel("灵动岛外观预览")
            .accessibilityValue("\(effect.title)，隐私模式\(privacyMode ? "已开启" : "已关闭")，展开宽度 \(Int(expandedWidth)) pt")
            .transaction { $0.animation = nil }
    }
    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
            .frame(width: 24, height: 24).islandGlass(Circle(), tint: .white.opacity(0.04), clearSurface: true)
    }
}
