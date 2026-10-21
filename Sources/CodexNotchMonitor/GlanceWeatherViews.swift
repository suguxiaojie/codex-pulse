import SwiftUI

extension GlanceTone {
    var color: Color {
        switch self {
        case .calm: return Color(red: 63 / 255, green: 181 / 255, blue: 201 / 255)
        case .tight: return .orange
        case .critical: return .red
        }
    }
}

private struct GlanceTextShadowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var glanceTextShadow: Bool {
        get { self[GlanceTextShadowKey.self] }
        set { self[GlanceTextShadowKey.self] = newValue }
    }
}
private struct GlanceReadableText: ViewModifier {
    @Environment(\.glanceTextShadow) private var enabled
    func body(content: Content) -> some View {
        content.shadow(color: enabled ? .black.opacity(0.35) : .clear, radius: 1.5)
    }
}
extension View {
    func glanceReadableText() -> some View { modifier(GlanceReadableText()) }
    func weatherModule() -> some View {
        padding(10)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 0.5).padding(.horizontal, 16)
                    .accessibilityHidden(true)
            }
    }
}

struct GlanceWeatherStrip: View {
    @AppStorage(CountStyle.preferenceKey) private var countStyle = CountStyle.chinese.rawValue
    let buckets: [GlanceDayStrip.Bucket]
    let isCost: Bool
    let isReady: Bool
    let showsSelector: Bool
    @Binding var metric: String
    let color: Color
    let unknownModels: [String]
    var loadingText = "用量明细尚未就绪"
    var tokenSourceLabel = "当前账号本地用量"
    var unpricedDates: Set<Date> = []
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered: Date?
    @State private var hoverClearWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                GlanceMetricTabs(selection: Binding(
                    get: { selectedMetric }, set: { metric = $0.rawValue }
                ), showsSelector: showsSelector)
                Spacer(minLength: 0)
                Text(isReady ? totalText : "—")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
            Text(selectedMetric.subtitle(tokenSourceLabel: tokenSourceLabel))
                .font(.system(size: 9)).foregroundStyle(FloatingSurfaceTheme.secondary(colorScheme))
            if isReady {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(buckets) { bucket in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                if isCost && unpricedDates.contains(bucket.date) {
                                    HStack(spacing: 2) {
                                        Capsule().strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                            .frame(width: 10)
                                        Text("金额\n未知").font(.system(size: 8))
                                            .foregroundStyle(FloatingSurfaceTheme.detail(colorScheme))
                                            .fixedSize()
                                    }
                                } else {
                                    Capsule().fill(color.opacity(0.08)).frame(width: 10)
                                    Capsule().fill(color.opacity(bucket.value > 0 && bucket.value == maximumValue ? 1 : 0.38))
                                        .frame(width: 10, height: bucket.value > 0 ? max(2, 44 * bucket.value / max(1, maximumValue)) : 0)
                                }
                            }.frame(height: 44)
                            Text(bucket.label)
                                .font(.system(size: 9.5, weight: bucket.label == "今" ? .semibold : .regular))
                                .foregroundStyle(bucket.label == "今" ? FloatingSurfaceTheme.primary(colorScheme) : FloatingSurfaceTheme.secondary(colorScheme))
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                        .onHover { hovering in updateHover(bucket.date, hovering: hovering) }
                        .help(detail(bucket))
                        .accessibilityElement(children: .ignore).accessibilityLabel(detail(bucket))
                    }
                }
                Text(buckets.first(where: { $0.date == hovered }).map(detail) ?? summary)
                    .font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(FloatingSurfaceTheme.detail(colorScheme))
            } else {
                Text(loadingText).font(.system(size: 10)).frame(height: 65)
            }
            if isCost && (!unknownModels.isEmpty || !unpricedDates.isEmpty) {
                Text("部分模型未计价").font(.system(size: 9)).foregroundStyle(.orange)
                    .help(unpricedDates.isEmpty
                          ? "当前账号日志包含未计价模型：" + unknownModels.joined(separator: "、") + "。该提示不限定于最近 7 天。"
                          : "Claude 用量包含未计价日期；现有快照未提供这些日期的已知部分金额。")
            }
        }.weatherModule()
            .onDisappear { hoverClearWorkItem?.cancel() }
    }

    private var maximumValue: Double {
        buckets.filter { !isCost || !unpricedDates.contains($0.date) }.map(\.value).max() ?? 0
    }

    private var selectedMetric: GlanceStripMetric { isCost ? .cost : .token }

    private var totalText: String {
        isCost ? GlanceDayStrip.costTotalText(buckets, unpricedDates: unpricedDates)
            : CountFormatter.chart(buckets.reduce(0) { $0 + $1.value }, style: CountStyle(rawValue: countStyle) ?? .chinese)
    }

    private func updateHover(_ date: Date, hovering: Bool) {
        hoverClearWorkItem?.cancel()
        if hovering { hovered = date; return }
        let work = DispatchWorkItem { if hovered == date { hovered = nil } }
        hoverClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private var summary: String {
        isCost ? GlanceDayStrip.costSummaryText(buckets, unpricedDates: unpricedDates)
            : GlanceDayStrip.summaryText(buckets, formatValue: GlanceDayStrip.tokenText)
    }

    private func detail(_ bucket: GlanceDayStrip.Bucket) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let value = isCost ? GlanceDayStrip.costDetailValue(bucket, unpricedDates: unpricedDates) : CountFormatter.chart(bucket.value) + " Token"
        return "\(formatter.string(from: bucket.date)) · \(value)"
    }
}

struct GlanceProviderSwitch: View {
    @Binding var selection: GlanceProvider
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GlanceProvider.allCases, id: \.self) { provider in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = provider }
                } label: {
                    Text(provider == .codex ? "Codex" : "Claude")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .foregroundStyle(selection == provider ? FloatingSurfaceTheme.primary(colorScheme) : FloatingSurfaceTheme.secondary(colorScheme))
                        .background {
                            if selection == provider {
                                Capsule().fill(FloatingSurfaceTheme.accent(colorScheme).opacity(0.20))
                                    .matchedGeometryEffect(id: "glance-provider", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(FloatingSurfaceButtonStyle())
                    .accessibilityLabel(provider == .codex ? "Codex" : "Claude Code")
                    .accessibilityValue(selection == provider ? "已选择" : "未选择")
                    .accessibilityAddTraits(selection == provider ? .isSelected : [])
            }
        }.frame(width: 126, height: 26)
            .islandGlass(Capsule(), tint: FloatingSurfaceTheme.chipFill(colorScheme), solidTint: FloatingSurfaceTheme.surface(colorScheme))
            .accessibilityElement(children: .contain).accessibilityLabel("用量来源")
    }
}

private struct GlanceMetricTabs: View {
    @Binding var selection: GlanceStripMetric
    let showsSelector: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var underline
    @FocusState private var focusedMetric: GlanceStripMetric?

    var body: some View {
        if showsSelector {
            HStack(spacing: 10) {
                ForEach(GlanceStripMetric.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = item }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: selection == item ? .semibold : .regular))
                            .foregroundStyle(selection == item ? FloatingSurfaceTheme.primary(colorScheme) : FloatingSurfaceTheme.secondary(colorScheme))
                            .padding(.horizontal, 3).frame(minHeight: 32)
                            .overlay(alignment: .bottom) {
                                if selection == item {
                                    if reduceMotion {
                                        indicator
                                    } else {
                                        indicator.matchedGeometryEffect(id: "metric-underline", in: underline)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedMetric, equals: item)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(focusedMetric == item ? FloatingSurfaceTheme.accent(colorScheme) : .clear, lineWidth: 1)
                    }
                    .accessibilityLabel(item.title)
                    .accessibilityValue(selection == item ? "已选择" : "未选择")
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }
            // Native segmented semantics for VoiceOver; the visible controls remain text buttons.
            .accessibilityRepresentation {
                Picker("七日条带指标，分段选择", selection: $selection) {
                    ForEach(GlanceStripMetric.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }.pickerStyle(.segmented)
                    .accessibilityValue(selection.title + "，已选择")
            }
        } else {
            Text(selection.title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FloatingSurfaceTheme.primary(colorScheme)).frame(minHeight: 32)
        }
    }

    private var indicator: some View {
        Capsule().fill(FloatingSurfaceTheme.primary(colorScheme)).frame(width: 14, height: 2)
    }
}
