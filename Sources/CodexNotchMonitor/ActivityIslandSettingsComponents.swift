// Reused from QuotaView d16307f (MIT), Copyright (c) 2026 Duoasa.
// Full notice: Resources/ThirdPartyNotices.txt.
import SwiftUI
import AppKit

// Keep pointer tracking continuous and local. Persist/refresh the native preview
// at a bounded rate, then flush the exact stepped value when the gesture ends.
struct IslandSettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let title: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @State private var dragging = false
    @State private var hovered = false
    @State private var dragOrigin: Double?
    @State private var dragProgress: Double?

    private var progress: Double {
        if let dragProgress { return dragProgress }
        guard range.upperBound > range.lowerBound, value.isFinite else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
    private func update(_ candidate: Double) {
        guard enabled, candidate.isFinite, step > 0 else { return }
        let next = min(range.upperBound, max(range.lowerBound,
            range.lowerBound + ((candidate - range.lowerBound) / step).rounded() * step))
        if next != value { value = next }
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 22)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.25)).frame(height: 6)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                Capsule().fill(LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 11 + travel * progress, height: 6)
                Circle().fill(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                    .overlay(Circle().fill(Color.accentColor.opacity(dragging ? 0.8 : 0.35)).frame(width: 5, height: 5))
                    .shadow(color: .black.opacity(0.4), radius: dragging ? 5 : 3, y: 2)
                    .frame(width: 22, height: 22)
                    .scaleEffect(dragging ? 1.12 : hovered ? 1.04 : 1)
                    .offset(x: travel * progress)
            }
            .frame(height: 30).contentShape(Rectangle())
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.08), value: progress)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.78), value: dragging)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    guard enabled else { return }
                    if dragOrigin == nil {
                        let center = 11 + travel * progress
                        dragOrigin = abs(gesture.startLocation.x - center) <= 16 ? progress : min(1, max(0, (gesture.startLocation.x - 11) / travel))
                        focused = true
                    }
                    if !dragging { onEditingChanged(true) }
                    dragging = true
                    let next = (dragOrigin ?? progress) + gesture.translation.width / travel
                    dragProgress = min(1, max(0, next))
                }
                .onEnded { _ in finishDrag() })
        }
        .frame(height: 30)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(focused ? 0.6 : 0), lineWidth: 1).padding(-3))
        .opacity(enabled ? 1 : 0.4)
        .focusable(enabled).focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: update(value - step)
            case .right, .up: update(value + step)
            default: break
            }
        }
        .onHover { hovered = $0 }
        .task(id: dragging) {
            guard dragging else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { return }
                guard dragging, let dragProgress else { return }
                update(range.lowerBound + dragProgress * (range.upperBound - range.lowerBound))
            }
        }
        .onDisappear { finishDrag() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: update(value + step)
            case .decrement: update(value - step)
            @unknown default: break
            }
        }
    }

    private func finishDrag() {
        if let dragProgress {
            update(range.lowerBound + dragProgress * (range.upperBound - range.lowerBound))
        }
        if dragging { onEditingChanged(false) }
        dragging = false
        dragOrigin = nil
        dragProgress = nil
    }
}

struct IslandSettingsTonePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - 8) / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11).fill(.black.opacity(0.22))
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.09)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .frame(width: width, height: 28)
                    .offset(x: 4 + (selection == ActivityIslandUsageCapsuleTone.light.rawValue ? width : 0))
                HStack(spacing: 0) {
                    option("深色", symbol: "moon.fill", value: .dark)
                    option("浅色", symbol: "sun.max.fill", value: .light)
                }.padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        }
        .frame(height: 36).opacity(enabled ? 1 : 0.4)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: selection)
        .accessibilityElement(children: .contain).accessibilityLabel("胶囊配色")
    }

    private func option(_ title: String, symbol: String, value: ActivityIslandUsageCapsuleTone) -> some View {
        Button { selection = value.rawValue } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(MonitorDesktopTypography.control)
            }
            .foregroundStyle(.white.opacity(selection == value.rawValue ? 1 : 0.45))
            .frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityValue(selection == value.rawValue ? "已选择" : "未选择")
    }
}

enum IslandSettingsEffectPreviewMetrics {
    static let previewCornerRadius: CGFloat = 8
    static let inset: CGFloat = 6
    static let outerCornerRadius: CGFloat = 12
    static let height: CGFloat = 44
}

struct IslandSettingsEffectOptionStyle: ButtonStyle {
    let effect: ActivityIslandProgressEffect
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 8) {
            // The grid owns the viewport width; an aspect-fill image must not
            // enlarge that width when the preview height changes.
            GeometryReader { geometry in
                Image(nsImage: ActivityIslandPreviewAssets.image(effect.asset) ?? NSImage())
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(red: 0.065, green: 0.052, blue: 0.080))
                    .clipped()
            }
                .frame(height: IslandSettingsEffectPreviewMetrics.height)
                .clipShape(RoundedRectangle(cornerRadius: IslandSettingsEffectPreviewMetrics.previewCornerRadius, style: .continuous))
                .padding(IslandSettingsEffectPreviewMetrics.inset)
                .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0.025),
                            in: RoundedRectangle(cornerRadius: IslandSettingsEffectPreviewMetrics.outerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IslandSettingsEffectPreviewMetrics.outerCornerRadius, style: .continuous)
                        .strokeBorder(selected ? MonitorDesktopTheme.selection : MonitorDesktopTheme.hairline, lineWidth: selected ? 1.5 : 0.5)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            configuration.label.font(MonitorDesktopTypography.control).foregroundStyle(MonitorDesktopTheme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity).contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }.onDisappear { hovered = false }
    }
}
