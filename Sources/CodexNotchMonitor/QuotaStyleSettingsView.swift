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
    @AppStorage(ActivityIslandPreferenceKey.effectQuality) private var effectQuality = ActivityIslandEffectQuality.balanced.rawValue
    @AppStorage(ActivityIslandPreferenceKey.confettiIntensity) private var confettiIntensity = ActivityIslandConfettiIntensity.standard.rawValue
    @AppStorage(ActivityIslandPreferenceKey.completionSound) private var completionSound = true
    @AppStorage(ActivityIslandPreferenceKey.completionSoundName) private var completionSoundName = ActivityIslandCompletionSound.glass.rawValue
    @AppStorage(ActivityIslandPreferenceKey.clawdEnabled) private var clawdEnabled = true
    @AppStorage(ActivityIslandPreferenceKey.clawdSize) private var clawdSize = IslandClawdSize.medium.rawValue
    @AppStorage(ActivityIslandPreferenceKey.attentionSound) private var attentionSound = ActivityIslandCompletionSound.ping.rawValue
    @AppStorage(ActivityIslandPreferenceKey.expandTrigger) private var expandTrigger = ActivityIslandExpandTrigger.hover.rawValue
    @AppStorage(ActivityIslandPreferenceKey.displayTarget) private var displayTarget = ActivityIslandDisplayTarget.automatic.rawValue
    @State private var confirmingReset = false
    @State private var displays = IslandDisplayInfo.connected()
    @State private var previewVisible = true
    @State private var isAdjustingSlider = false
    @State private var showsLargePreview = false
    @State private var geometry = ActivityIslandWidthGeometry.current()


    private var widthBinding: Binding<Double> {
        Binding(get: { min(geometry.settingsRange.upperBound, max(geometry.settingsRange.lowerBound, expandedWidth)) },
                set: { expandedWidth = ActivityIslandPreferences.normalizedWidth($0) })
    }
    private static let soundOff = "off"
    /// One menu per sound: "关闭" first, then the tones.
    /// Names what is connected now, and says where the island is while a chosen display is away.
    private var displayDetail: String {
        let summary = displays.map { "\($0.name)（\($0.isBuiltIn ? "内建" : "外接")）" }.joined(separator: "、")
        if case .display(let id) = ActivityIslandDisplayTarget(rawValue: displayTarget), !displays.contains(where: { $0.id == id }) {
            return "所选显示器未连接，暂时按刘海屏优先显示。"
        }
        return displays.count > 1 ? "已连接 \(displays.count) 块：\(summary)。" : "当前只有 \(summary)；接外接显示器后可选择。"
    }
    private var completionSoundBinding: Binding<String> {
        Binding(get: { completionSound ? completionSoundName : Self.soundOff },
                set: { value in
                    if value == Self.soundOff { completionSound = false } else { completionSound = true; completionSoundName = value }
                })
    }
    private var capsuleStyleBinding: Binding<String> {
        Binding(get: { ActivityIslandCapsuleStyle.current(material: ActivityIslandMaterial(rawValue: material) ?? .liquidGlass,
                                                          appearance: ActivityIslandGlassAppearance(rawValue: glassAppearance) ?? .dark).rawValue },
                set: { value in
                    guard let style = ActivityIslandCapsuleStyle(rawValue: value) else { return }
                    material = style.material.rawValue
                    if let appearance = style.appearance { glassAppearance = appearance.rawValue }
                })
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
                        VStack(spacing: 26) { appearanceGroup; effectsGroup; feedbackGroup }
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 26) { contentGroup; clawdGroup; automaticGroup; resetRow }
                            .frame(maxWidth: .infinity)
                    }.frame(width: max(670, layout.size.width - 8)).frame(minWidth: 670)
                    VStack(spacing: 26) { appearanceGroup; contentGroup; clawdGroup; effectsGroup; feedbackGroup; automaticGroup; resetRow }
                }
            }
        }
        .font(MonitorDesktopTypography.body).foregroundStyle(PanelSettingsTheme.primary)
        .tint(PanelSettingsTheme.clay).accentColor(PanelSettingsTheme.clay)
        .onAppear { previewVisible = true; geometry = .current(); displays = IslandDisplayInfo.connected() }
        .onDisappear { previewVisible = false; isAdjustingSlider = false }
        .onChange(of: material) { _ in signal() }.onChange(of: glassDegree) { _ in signal() }
        .onChange(of: expandedWidth) { _ in signal() }.onChange(of: effect) { _ in signal() }
        .onChange(of: privacyMode) { _ in signal() }.onChange(of: automaticPopup) { _ in signal() }
        .onChange(of: confettiIntensity) { _ in signal() }
        .onChange(of: effectQuality) { _ in signal() }
        .onChange(of: completionSound) { _ in signal() }
        .onChange(of: completionSoundName) { value in
            signal()
            ActivityIslandCompletionAudio.play(ActivityIslandCompletionSound(rawValue: value) ?? .glass)
        }
        .onChange(of: expandedHold) { _ in signal() }
        .onChange(of: floatingUsageEnabled) { _ in signal() }.onChange(of: glassAppearance) { _ in signal() }
        .onChange(of: clawdEnabled) { _ in signal() }
        .onChange(of: clawdSize) { _ in signal() }
        .onChange(of: attentionSound) { value in
            signal()
            if let tone = ActivityIslandCompletionSound(rawValue: value) { ActivityIslandCompletionAudio.play(tone) }
        }
        .onChange(of: expandTrigger) { _ in signal() }.onChange(of: displayTarget) { _ in signal() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            geometry = .current(); displays = IslandDisplayInfo.connected()
        }
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
            IslandSettingsSliderRow(title: "边缘光强度", detail: "岛体为纯黑；边缘光颜色跟随任务状态", value: Binding(
                get: { IslandHardwareBlack.sliderValue(glassDegree) }, set: { glassDegree = IslandHardwareBlack.sliderValue($0) }
            ), range: 0.2...0.8, step: 0.01, display: "\(Int((IslandHardwareBlack.sliderValue(glassDegree) * 100).rounded()))%",
                lowerLabel: "更暗", upperLabel: "更亮", onEditingChanged: { isAdjustingSlider = $0 }, symbol: "circle.dotted")
            SettingsRowDivider()
            IslandSettingsSliderRow(title: "展开宽度", detail: "刘海两侧保留安全空间。", value: widthBinding,
                      range: geometry.settingsRange, step: 1, display: "\(Int(widthBinding.wrappedValue)) pt",
                      lowerLabel: "更窄", upperLabel: "更宽", onEditingChanged: { isAdjustingSlider = $0 }, symbol: "arrow.left.and.right")
            SettingsRowDivider()
            SettingsRow(symbol: "display.2", title: "显示屏幕", detail: displayDetail) {
                Picker("显示屏幕", selection: $displayTarget) {
                    Text("自动（刘海屏优先）").tag(ActivityIslandDisplayTarget.automatic.rawValue)
                    Text("主显示器").tag(ActivityIslandDisplayTarget.main.rawValue)
                    Divider()
                    ForEach(displays) { display in
                        Text("\(display.name)（\(display.kindTitle)）").tag(ActivityIslandDisplayTarget.display(display.id).rawValue)
                    }
                    if case .display(let id) = ActivityIslandDisplayTarget(rawValue: displayTarget), !displays.contains(where: { $0.id == id }) {
                        Text("已选显示器（未连接）").tag(displayTarget)
                    }
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 230)
                    .modifier(MonitorMenuTrigger(minimumHeight: 30, horizontalPadding: 8))
            }
        }.modifier(MonitorDesktopReveal(delay: 0.04))
    }
    private var contentGroup: some View {
        PanelSettingsGroup(title: "显示内容", symbol: "rectangle.on.rectangle") {
            toggle("悬浮用量胶囊", symbol: "capsule.portrait", detail: "显示剩余额度和重置倒计时。", value: $floatingUsageEnabled)
            SettingsRow(symbol: "square.stack.3d.up", title: "胶囊样式", detail: "只影响悬浮用量胶囊；岛体始终为纯黑。") {
                Picker("胶囊样式", selection: capsuleStyleBinding) {
                    ForEach(ActivityIslandCapsuleStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().pickerStyle(.menu).frame(width: 110)
                    .modifier(MonitorMenuTrigger(minimumHeight: 30, horizontalPadding: 8))
            }.disabled(!floatingUsageEnabled)
            if #unavailable(macOS 26.0), floatingUsageEnabled, material == ActivityIslandMaterial.liquidGlass.rawValue {
                Label("液态玻璃需要 macOS 26 或更新版本；当前系统使用半透明材质。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(MonitorDesktopTheme.caution).padding(.leading, 40).padding(.bottom, 14)
            }
            SettingsRowDivider()
            toggle("隐私模式", symbol: "eye.slash", detail: "隐藏任务内容、模型与账户数据。", value: $privacyMode)
        }.modifier(MonitorDesktopReveal(delay: 0.08))
    }
    private var clawdGroup: some View {
        PanelSettingsGroup(title: "桌宠", symbol: "pawprint") {
            toggle("显示桌宠", symbol: "figure.climbing", detail: "Codex 任务显示终端仔，Claude Code 任务显示 Clawd，随任务状态做动作。", value: $clawdEnabled)
            SettingsRowDivider()
            SettingsRow(symbol: "arrow.up.left.and.arrow.down.right", title: "桌宠大小", detail: "按紧凑灵动岛高度限制大小，保持完整可见。") {
                Picker("桌宠大小", selection: $clawdSize) {
                    ForEach(IslandClawdSize.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 150)
            }.disabled(!clawdEnabled)
        }.modifier(MonitorDesktopReveal(delay: 0.1))
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
            SettingsRowDivider()
            SettingsRow(symbol: "dial.medium", title: "特效画质", detail: "流畅最细腻；均衡兼顾顺滑与耗电；省电降低帧率和分辨率。") {
                Picker("特效画质", selection: $effectQuality) {
                    ForEach(ActivityIslandEffectQuality.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().pickerStyle(.segmented)
            }
        }.modifier(MonitorDesktopReveal(delay: 0.12))
    }
    private var feedbackGroup: some View {
        PanelSettingsGroup(title: "完成与提醒", symbol: "bell.badge") {
            SettingsRow(symbol: "party.popper", title: "礼花", detail: "任务完成时播放；减弱动态效果开启时不播放。") {
                Picker("礼花", selection: $confettiIntensity) {
                    ForEach(ActivityIslandConfettiIntensity.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().pickerStyle(.segmented)
            }
            SettingsRowDivider()
            soundRow(title: "完成提示音", symbol: "speaker.wave.2", detail: "任务完成时播放，跟随系统音量。", selection: completionSoundBinding)
            SettingsRowDivider()
            soundRow(title: "待处理提示音", symbol: "hand.raised", detail: "出现待批准或待回复时播放。", selection: $attentionSound)
        }.modifier(MonitorDesktopReveal(delay: 0.14))
    }
    private func soundRow(title: String, symbol: String, detail: String, selection: Binding<String>) -> some View {
        SettingsRow(symbol: symbol, title: title, detail: detail) {
            Picker(title, selection: selection) {
                Text("关闭").tag(Self.soundOff)
                Divider()
                ForEach(ActivityIslandCompletionSound.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }.labelsHidden().pickerStyle(.menu).frame(width: 110)
                .modifier(MonitorMenuTrigger(minimumHeight: 30, horizontalPadding: 8))
        }
    }
    private var automaticGroup: some View {
        PanelSettingsGroup(title: "展开与弹出", symbol: "arrow.up.left.and.arrow.down.right") {
            SettingsRow(symbol: "cursorarrow.rays", title: "展开方式", detail: "悬停：鼠标移上去就展开；点击：点一下才展开，避免误触。") {
                Picker("展开方式", selection: $expandTrigger) {
                    ForEach(ActivityIslandExpandTrigger.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 120)
            }
            SettingsRowDivider()
            toggle("自动弹出", symbol: "bolt", detail: "新任务、完成或待确认时展开。", value: $automaticPopup)
            SettingsRowDivider()
            SettingsRow(symbol: "timer", title: "停留时间", detail: "自动弹出后保持展开的时长。") {
                Picker("停留时间", selection: durationBinding) {
                    ForEach(1...10, id: \.self) { Text("\($0) 秒").tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(width: 100)
                    .modifier(MonitorMenuTrigger(minimumHeight: 30, horizontalPadding: 8))
                    .disabled(!automaticPopup)
            }
        }.modifier(MonitorDesktopReveal(delay: 0.12))
    }
    /// Two-step reset: the first click arms, the second removes every island key.
    private var resetRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if confirmingReset {
                Text("所有灵动岛设置将恢复默认").font(MonitorDesktopTypography.rowDetail).foregroundStyle(PanelSettingsTheme.secondary)
                Button("取消") { confirmingReset = false }.buttonStyle(PanelSettingsActionStyle())
            }
            Button(confirmingReset ? "确认恢复" : "恢复默认") {
                if confirmingReset {
                    ActivityIslandPreferenceKey.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
                    confirmingReset = false
                    signal()
                } else {
                    confirmingReset = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { confirmingReset = false }
                }
            }.buttonStyle(PanelSettingsActionStyle())
                .foregroundStyle(confirmingReset ? MonitorDesktopTheme.caution : PanelSettingsTheme.primary)
        }.padding(.horizontal, 4)
    }
    private func islandPreview(animated: Bool) -> some View {
        ActivityIslandDesktopPreview(material: ActivityIslandMaterial(rawValue: material) ?? .liquidGlass,
            degree: glassDegree, effect: ActivityIslandProgressEffect(rawValue: effect) ?? .dropField,
            expandedWidth: geometry.expandedWidth(preferred: expandedWidth),
            maximumExpandedWidth: geometry.maximumExpandedWidth,
            animated: animated, reduceMotion: systemReduceMotion, privacyMode: privacyMode,
            floatingUsageEnabled: floatingUsageEnabled,
            glassAppearance: ActivityIslandGlassAppearance(rawValue: glassAppearance) ?? .dark,
            clawdEnabled: clawdEnabled, clawdSize: IslandClawdSize(rawValue: clawdSize) ?? .medium)
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
