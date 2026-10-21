import SwiftUI

struct MonitorCardHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MonitorDesktopTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(MonitorDesktopTypography.rowDetail)
                        .foregroundStyle(MonitorDesktopTheme.tertiaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct MonitorChipSurface: ViewModifier {
    var tint: Color = MonitorDesktopTheme.primaryText
    func body(content: Content) -> some View {
        content.padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.05), in: Capsule())
    }
}

struct MonitorMetaChip: View {
    let text: String
    var tint: Color = MonitorDesktopTheme.secondaryText
    init(_ text: String, tint: Color = MonitorDesktopTheme.secondaryText) {
        self.text = text
        self.tint = tint
    }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit()
            .foregroundStyle(tint).modifier(MonitorChipSurface())
    }
}

struct MonitorStageHighlight: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                RadialGradient(colors: [MonitorDesktopTheme.stageHighlight, .clear],
                               center: .top, startRadius: 0, endRadius: geometry.size.width * 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

struct MonitorCenterCard: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        content.padding(16)
            .background {
                if prominent { Color.clear.modifier(MonitorStageHighlight()) }
            }
            .modifier(MonitorDesktopCardSurface(prominent: prominent, cornerRadius: 14))
    }
}

struct MonitorChartInset: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(10)
            .background(MonitorDesktopTheme.subtleCardFill, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MonitorHeroMetric: View {
    let label: String
    let value: String
    var unit: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(MonitorDesktopTypography.rowDetail).foregroundStyle(MonitorDesktopTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 34, weight: .semibold)).tracking(-0.6)
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(MonitorDesktopTheme.primaryText)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 13, weight: .medium)).foregroundStyle(MonitorDesktopTheme.secondaryText)
                }
            }
        }.accessibilityElement(children: .combine)
    }
}

struct MonitorStatPair: View {
    let value: String
    let label: String
    var unit: String? = nil
    var alignment: HorizontalAlignment = .trailing
    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText()).foregroundStyle(MonitorDesktopTheme.primaryText)
                if let unit {
                    Text(unit).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MonitorDesktopTheme.secondaryText)
                }
            }
            Text(label).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.tertiaryText)
        }.accessibilityElement(children: .combine)
    }
}

struct MonitorBreakdownChips: View {
    let input: String
    let output: String
    let cache: String
    private func chip(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(label).font(MonitorDesktopTypography.metadata).foregroundStyle(MonitorDesktopTheme.tertiaryText)
            Text(value).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(MonitorDesktopTheme.primaryText.opacity(0.04), in: Capsule())
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chip("非缓存输入", input, MonitorDesktopTheme.usageData)
                chip("输出", output, MonitorDesktopTheme.accent)
                chip("缓存", cache, MonitorDesktopTheme.costSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                chip("非缓存输入", input, MonitorDesktopTheme.usageData)
                HStack(spacing: 8) {
                    chip("输出", output, MonitorDesktopTheme.accent)
                    chip("缓存", cache, MonitorDesktopTheme.costSecondary)
                }
            }
        }
    }
}

struct MonitorProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(MonitorDesktopTheme.track)
                .overlay(alignment: .leading) {
                    Capsule().fill(MonitorDesktopTheme.accent)
                        .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
                }
        }
        .frame(height: 5)
        .accessibilityRepresentation {
            ProgressView(value: configuration.fractionCompleted).progressViewStyle(.linear)
        }
    }
}
