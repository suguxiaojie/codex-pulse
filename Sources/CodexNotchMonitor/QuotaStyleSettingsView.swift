// Activity Island child page, adapted from QuotaView d16307f (MIT).
// Settings follow the app desktop theme; previews reuse the production focus stage.
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
    @AppStorage(ActivityIslandPreferenceKey.glassAppearance) private var glassAppearance = ActivityIslandGlassAppearance.dark.rawValue
    @AppStorage(ActivityIslandPreferenceKey.automaticPopup) private var automaticPopup = true
    @AppStorage(ActivityIslandPreferenceKey.expandedHold) private var expandedHold = 3.0
    @State private var previewVisible = true
    @State private var isAdjustingSlider = false
    @State private var showsLargePreview = false
    @State private var geometry = ActivityIslandWidthGeometry.current()


    private var widthBinding: Binding<Double> {
        Binding(get: { min(geometry.settingsRange.upperBound, max(geometry.settingsRange.lowerBound, expandedWidth)) },
                set: { expandedWidth = ActivityIslandPreferences.normalizedWidth($0) })
    }
    private var durationBinding: Binding<Int> {
        Binding(get: { Int(ActivityIslandPreferences.normalizedDuration(expandedHold)) }, set: { expandedHold = Double($0) })
    }
    var body: some View {
        GeometryReader { layout in
            SettingsWorkbench(isAdjusting: isAdjustingSlider, fullWidthPreview: true) {
                previewSection
            } controls: {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 26) { appearanceGroup; effectsGroup }
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 26) { contentGroup; automaticGroup }
                            .frame(maxWidth: .infinity)
                    }.frame(width: max(670, layout.size.width - 8)).frame(minWidth: 670)
                    VStack(spacing: 26) { appearanceGroup; contentGroup; effectsGroup; automaticGroup }
                }
            }
        }
        .font(MonitorDesktopTypography.body).foregroundStyle(PanelSettingsTheme.primary)
        .tint(PanelSettingsTheme.clay).accentColor(PanelSettingsTheme.clay)
        .onAppear { previewVisible = true; geometry = .current() }
        .onDisappear { previewVisible = false; isAdjustingSlider = false }
        .onChange(of: material) { _ in signal() }.onChange(of: glassDegree) { _ in signal() }
        .onChange(of: expandedWidth) { _ in signal() }.onChange(of: effect) { _ in signal() }
        .onChange(of: privacyMode) { _ in signal() }.onChange(of: automaticPopup) { _ in signal() }
        .onChange(of: expandedHold) { _ in signal() }
        .onChange(of: floatingUsageEnabled) { _ in signal() }.onChange(of: glassAppearance) { _ in signal() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in geometry = .current() }
    }

    private var previewSection: some View {
        SettingsStage(title: "完整预览", status: "示例数据", caption: "外观设置即时联动", accessory: { enlargeButton }) {
            ProportionalSettingsPreview(width: 620, height: 340) {
                islandPreview(animated: previewVisible && !showsLargePreview)
            }
            .frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .modifier(MonitorDesktopReveal(delay: 0))
        .sheet(isPresented: $showsLargePreview) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("灵动岛完整预览").font(MonitorDesktopTypography.cardTitle)
                    Spacer()
                    Button("完成") { showsLargePreview = false }
                        .buttonStyle(PanelSettingsActionStyle()).keyboardShortcut(.cancelAction)
                }
                islandPreview(animated: previewVisible).frame(width: 620, height: 340)
                Text("示例数据 · 展示当前外观设置，实际任务与额度以本机数据为准。")
                    .font(MonitorDesktopTypography.rowDetail).foregroundStyle(PanelSettingsTheme.secondary)
            }
            .padding(24).frame(width: 668)
            .foregroundStyle(PanelSettingsTheme.primary).background(PanelSettingsTheme.canvas)
            .preferredColorScheme(.dark).onExitCommand { showsLargePreview = false }
        }
    }
    private var enlargeButton: some View {
        Button { showsLargePreview = true } label: {
            Label("放大预览", systemImage: "arrow.up.left.and.arrow.down.right")
        }.buttonStyle(PanelSettingsActionStyle())
    }
    private var appearanceGroup: some View {
        PanelSettingsGroup(title: "外观与布局", symbol: "slider.horizontal.3") {
            SettingsRow(symbol: "square.stack.3d.up", title: "岛外胶囊材质", detail: "仅影响悬浮额度胶囊；岛体始终为纯黑。") {
                PanelSettingsSegments(options: ActivityIslandMaterial.allCases.map(\.title), selection: Binding(
                    get: { (ActivityIslandMaterial(rawValue: material) ?? .liquidGlass).title },
                    set: { title in
                        if let option = ActivityIslandMaterial.allCases.first(where: { $0.title == title }) { material = option.rawValue }
                    }
                ), width: 220, title: "岛外胶囊材质")
            }
            if material == ActivityIslandMaterial.liquidGlass.rawValue {
                SettingsRowDivider()
                SettingsRow(symbol: "circle.lefthalf.filled", title: "岛外胶囊外观", detail: "仅影响悬浮额度胶囊；自动模式跟随系统外观。") {
                    PanelSettingsSegments(options: ActivityIslandGlassAppearance.allCases.map(\.title), selection: Binding(
                        get: { (ActivityIslandGlassAppearance(rawValue: glassAppearance) ?? .dark).title },
                        set: { title in
                            if let option = ActivityIslandGlassAppearance.allCases.first(where: { $0.title == title }) { glassAppearance = option.rawValue }
                        }
                    ), width: 220, title: "岛外胶囊外观")
                }
            }
            SettingsRowDivider()
            IslandSettingsSliderRow(title: "边缘光强度", detail: "岛体为纯黑；边缘光颜色跟随任务状态", value: Binding(
                get: { IslandHardwareBlack.sliderValue(glassDegree) }, set: { glassDegree = IslandHardwareBlack.sliderValue($0) }
            ), range: 0.2...0.8, step: 0.01, display: "\(Int((IslandHardwareBlack.sliderValue(glassDegree) * 100).rounded()))%",
                lowerLabel: "更暗", upperLabel: "更亮", onEditingChanged: { isAdjustingSlider = $0 }, symbol: "circle.dotted")
            SettingsRowDivider()
            IslandSettingsSliderRow(title: "展开宽度", detail: "刘海两侧保留安全空间。", value: widthBinding,
                      range: geometry.settingsRange, step: 1, display: "\(Int(widthBinding.wrappedValue)) pt",
                      lowerLabel: "更窄", upperLabel: "更宽", onEditingChanged: { isAdjustingSlider = $0 }, symbol: "arrow.left.and.right")
            if #unavailable(macOS 26.0) {
                Label("岛外悬浮胶囊的液态玻璃需要 macOS 26 或更新版本；当前系统使用半透明材质。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(MonitorDesktopTheme.caution).padding(.leading, 40).padding(.bottom, 14)
            }
        }.modifier(MonitorDesktopReveal(delay: 0.04))
    }
    private var contentGroup: some View {
        PanelSettingsGroup(title: "显示内容", symbol: "rectangle.on.rectangle") {
            toggle("悬浮用量胶囊", symbol: "capsule.portrait", detail: "显示剩余额度和重置倒计时。", value: $floatingUsageEnabled)
            SettingsRowDivider()
            toggle("隐私模式", symbol: "eye.slash", detail: "隐藏任务内容、模型与账户数据。", value: $privacyMode)
        }.modifier(MonitorDesktopReveal(delay: 0.08))
    }
    private var effectsGroup: some View {
        PanelSettingsGroup(title: "任务特效", symbol: "sparkles") {
            HStack(spacing: 10) {
                ForEach(ActivityIslandProgressEffect.allCases) { option in
                    Button { effect = option.rawValue } label: { Text(option.title) }
                        .buttonStyle(IslandSettingsEffectOptionStyle(effect: option, selected: effect == option.rawValue))
                        .accessibilityLabel(option.title).accessibilityValue(effect == option.rawValue ? "已选择" : "未选择")
                        .accessibilityAddTraits(effect == option.rawValue ? .isSelected : [])
                }
            }.padding(.vertical, 14)
        }.modifier(MonitorDesktopReveal(delay: 0.12))
    }
    private var automaticGroup: some View {
        PanelSettingsGroup(title: "自动展开", symbol: "arrow.up.left.and.arrow.down.right") {
            toggle("自动弹出", symbol: "bolt", detail: "新任务、完成或待确认时展开。", value: $automaticPopup)
            SettingsRowDivider()
            SettingsRow(symbol: "timer", title: "停留时间", detail: "待确认或固定时保持展开。") {
                Picker("停留时间", selection: durationBinding) {
                    ForEach(1...10, id: \.self) { Text("\($0) 秒").tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(width: 100)
                    .modifier(MonitorMenuTrigger(minimumHeight: 30, horizontalPadding: 8))
                    .disabled(!automaticPopup)
            }
        }.modifier(MonitorDesktopReveal(delay: 0.12))
    }
    private func islandPreview(animated: Bool) -> some View {
        ActivityIslandDesktopPreview(material: ActivityIslandMaterial(rawValue: material) ?? .liquidGlass,
            degree: glassDegree, effect: ActivityIslandProgressEffect(rawValue: effect) ?? .dropField,
            expandedWidth: geometry.expandedWidth(preferred: expandedWidth),
            maximumExpandedWidth: geometry.maximumExpandedWidth,
            animated: animated, reduceMotion: systemReduceMotion, privacyMode: privacyMode,
            floatingUsageEnabled: floatingUsageEnabled,
            glassAppearance: ActivityIslandGlassAppearance(rawValue: glassAppearance) ?? .dark)
    }
    private func signal() { ActivityIslandPreferenceSignal.post() }
    private func toggle(_ title: String, symbol: String, detail: String, value: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, detail: detail) {
            Toggle(title, isOn: value).labelsHidden()
                .toggleStyle(PanelSettingsToggleStyle(onTitle: "开启", offTitle: "关闭"))
                .accessibilityLabel(title)
        }
    }
}
