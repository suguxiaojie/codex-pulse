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
        SettingsWorkbench(isAdjusting: isAdjustingSlider, fullWidthPreview: true) {
            previewSection
        } controls: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 22) { appearanceGroup; effectsGroup }
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 22) { contentGroup; automaticGroup }
                        .frame(maxWidth: .infinity)
                }.frame(minWidth: 670)
                VStack(spacing: 22) { appearanceGroup; contentGroup; effectsGroup; automaticGroup }
            }
        }
        .font(MonitorDesktopTypography.body).foregroundStyle(PanelSettingsTheme.primary)
        .tint(PanelSettingsTheme.clay).accentColor(PanelSettingsTheme.clay)
        .background(PanelSettingsTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("完整预览", systemImage: "rectangle.topthird.inset.filled")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("示例数据").font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
            }
            ProportionalSettingsPreview(width: 620, height: 240) {
                islandPreview(animated: previewVisible && !showsLargePreview)
            }
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("完整场景 · 外观设置即时联动").font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
                    Spacer()
                    enlargeButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("完整场景 · 外观设置即时联动").font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
                    enlargeButton
                }
            }
        }
        .padding(16)
        .background(PanelSettingsTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PanelSettingsTheme.border.opacity(0.55), lineWidth: 0.5))
        .sheet(isPresented: $showsLargePreview) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("灵动岛完整预览").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button("完成") { showsLargePreview = false }
                        .buttonStyle(PanelSettingsActionStyle()).keyboardShortcut(.cancelAction)
                }
                islandPreview(animated: previewVisible).frame(width: 620, height: 240)
                Text("示例数据 · 展示当前外观设置，实际任务与额度以本机数据为准。")
                    .font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
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
            VStack(alignment: .leading, spacing: 10) {
                rowLabel("材质", detail: "")
                PanelSettingsSegments(options: ActivityIslandMaterial.allCases.map(\.title), selection: Binding(
                    get: { (ActivityIslandMaterial(rawValue: material) ?? .liquidGlass).title },
                    set: { title in
                        if let option = ActivityIslandMaterial.allCases.first(where: { $0.title == title }) { material = option.rawValue }
                    }
                ), width: 220, title: "灵动岛材质")
            }.padding(.vertical, 14)
            if material == ActivityIslandMaterial.liquidGlass.rawValue {
                PanelSettingsTheme.divider
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("玻璃外观", detail: "影响底栏与悬浮胶囊，自动跟随系统外观。")
                    PanelSettingsSegments(options: ActivityIslandGlassAppearance.allCases.map(\.title), selection: Binding(
                        get: { (ActivityIslandGlassAppearance(rawValue: glassAppearance) ?? .dark).title },
                        set: { title in
                            if let option = ActivityIslandGlassAppearance.allCases.first(where: { $0.title == title }) { glassAppearance = option.rawValue }
                        }
                    ), width: 220, title: "玻璃外观")
                }.padding(.vertical, 14)
                PanelSettingsTheme.divider
                IslandSettingsSliderRow(title: "黑色遮罩比例", detail: "数值越高，黑色遮罩区域越大。", value: Binding(
                    get: { 1 - glassDegree }, set: { glassDegree = 1 - $0 }
                ), range: 0.2...0.8, step: 0.01, display: "\(Int(((1 - glassDegree) * 100).rounded()))%",
                    lowerLabel: "遮罩更少", upperLabel: "遮罩更多", onEditingChanged: { isAdjustingSlider = $0 })
            }
            PanelSettingsTheme.divider
            IslandSettingsSliderRow(title: "展开宽度", detail: "刘海两侧保留安全空间。", value: widthBinding,
                      range: geometry.settingsRange, step: 1, display: "\(Int(widthBinding.wrappedValue)) pt",
                      lowerLabel: "更窄", upperLabel: "更宽", onEditingChanged: { isAdjustingSlider = $0 })
            if #unavailable(macOS 26.0) {
                Text("原生液态玻璃需要 macOS 26 或更新版本；当前系统使用半透明材质。")
                    .font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary).padding(.bottom, 14)
            }
        }
    }
    private var contentGroup: some View {
        PanelSettingsGroup(title: "显示内容", symbol: "rectangle.on.rectangle") {
            toggle("悬浮用量胶囊", detail: "显示剩余额度和重置倒计时。", value: $floatingUsageEnabled)
            PanelSettingsTheme.divider
            toggle("隐私模式", detail: "隐藏任务内容、模型与账户数据。", value: $privacyMode)
        }
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
            }.padding(.vertical, 16)
        }
    }
    private var automaticGroup: some View {
        PanelSettingsGroup(title: "自动展开", symbol: "arrow.up.left.and.arrow.down.right") {
            toggle("自动弹出", detail: "新任务、完成或待确认时展开。", value: $automaticPopup)
            PanelSettingsTheme.divider
            settingRow("停留时间", detail: "待确认或固定时保持展开。") {
                Picker("停留时间", selection: durationBinding) {
                    ForEach(1...10, id: \.self) { Text("\($0) 秒").tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(width: 100)
                    .modifier(MonitorMenuTrigger(minimumHeight: 30, horizontalPadding: 8))
                    .disabled(!automaticPopup)
            }
        }
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
    private func rowLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                rowLabel(title, detail: detail).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                control().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) { rowLabel(title, detail: detail); control() }
        }.padding(.vertical, 14).frame(minHeight: 62)
    }
    private func toggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        settingRow(title, detail: detail) {
            Toggle(title, isOn: value).labelsHidden()
                .toggleStyle(PanelSettingsToggleStyle(onTitle: "开启", offTitle: "关闭"))
                .accessibilityLabel(title)
        }
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
    var glassAppearance: ActivityIslandGlassAppearance = .dark
    private var sample: ActivitySessionSnapshot {
        ActivitySessionSnapshot(sessionID: "preview", turnID: "preview", projectID: "preview", projectName: "示例项目",
            title: "整理项目资料", phase: .usingTool, actionText: "汇总文档，准备更新说明", updatedAt: Date(),
            tokenUsage: .init(sessionID: "preview", turnID: "preview", total: 128000),
            modelName: "gpt-6.1-sol", reasoningEffort: "high", startedAt: Date().addingTimeInterval(-120), sessionTotalTokens: 128000)
    }
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 24, 510) * min(1, CGFloat(expandedWidth) / max(1, maximumExpandedWidth))
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
                        .modifier(IslandGlassChrome())
                        .font(.system(size: 12)).padding(.horizontal, 28).padding(.bottom, 12).frame(height: 36)
                }.frame(width: width).background {
                    if material == .classic { shape.fill(.black) }
                    else {
                        ZStack {
                            Color.clear.modifier(IslandNativeBackdropMaterial(shape: shape)).modifier(IslandGlassChrome())
                            LinearGradient(stops: ActivityIslandGlassDegree.gradientStops(degree), startPoint: .top, endPoint: .bottom).clipShape(shape)
                        }
                    }
                }
                if floatingUsageEnabled && !privacyMode {
                    IslandUsageCapsuleContent(windows: [
                        .init(usedPercent: 28, windowDurationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 12000)),
                        .init(usedPercent: 54, windowDurationMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 345600))
                    ], current: true, now: Date(timeIntervalSince1970: 0))
                    .modifier(IslandGlassChrome())
                    .padding(.top, 166)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }.environment(\.islandLiquidGlassEnabled, material == .liquidGlass)
            .modifier(IslandGlassAppearanceContext(appearance: glassAppearance, material: material))
            .allowsHitTesting(false).accessibilityElement(children: .ignore)
            .accessibilityLabel("灵动岛外观预览")
            .accessibilityValue("\(effect.title)，隐私模式\(privacyMode ? "已开启" : "已关闭")，展开宽度 \(Int(expandedWidth)) pt")
            .transaction { $0.animation = nil }
    }
    private func icon(_ name: String) -> some View {
        IslandChromeIcon(name: name)
    }
}
