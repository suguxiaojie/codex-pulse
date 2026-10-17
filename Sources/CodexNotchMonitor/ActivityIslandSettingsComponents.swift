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
            let travel = max(1, geometry.size.width - 16)
            ZStack(alignment: .leading) {
                Capsule().fill(PanelSettingsTheme.track).frame(height: 4)
                Capsule().fill(PanelSettingsTheme.clay)
                    .frame(width: 8 + travel * progress, height: 4)
                Circle().fill(PanelSettingsTheme.sliderThumb)
                    .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .scaleEffect(enabled && !reduceMotion ? (dragging ? 1.06 : hovered ? 1.03 : 1) : 1)
                    .animation(reduceMotion ? nil : PanelSettingsTheme.pressMotion, value: dragging)
                    .animation(reduceMotion ? nil : PanelSettingsTheme.hoverMotion, value: hovered)
                    .offset(x: travel * progress)
            }
            .frame(height: 32).contentShape(Rectangle())
            .animation(reduceMotion || dragging ? nil : PanelSettingsTheme.selectionMotion, value: progress)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    guard enabled else { return }
                    if dragOrigin == nil {
                        let center = 8 + travel * progress
                        dragOrigin = abs(gesture.startLocation.x - center) <= 16 ? progress : min(1, max(0, (gesture.startLocation.x - 8) / travel))
                        focused = true
                    }
                    if !dragging { onEditingChanged(true) }
                    dragging = true
                    let next = (dragOrigin ?? progress) + gesture.translation.width / travel
                    dragProgress = min(1, max(0, next))
                }
                .onEnded { _ in finishDrag() })
        }
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PanelSettingsTheme.clay.opacity(enabled && focused ? 0.7 : 0), lineWidth: 1.5).padding(-3))
        .opacity(enabled ? 1 : 0.45)
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

struct IslandSettingsSliderRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String
    let lowerLabel: String
    let upperLabel: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelSettingsTheme.primary)
                Spacer(minLength: 4)
                Text(display).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(PanelSettingsTheme.clay)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(PanelSettingsTheme.clay.opacity(0.10), in: Capsule())
                    .fixedSize().accessibilityHidden(true)
            }
            Text(detail).font(.system(size: 11))
                .foregroundStyle(PanelSettingsTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            IslandSettingsSlider(value: $value, range: range, step: step, title: title,
                                 onEditingChanged: onEditingChanged)
                .accessibilityValue(display)
                .accessibilityHint(detail)
            HStack {
                Text(lowerLabel)
                Spacer()
                Text(upperLabel)
            }
            .font(.system(size: 11)).foregroundStyle(PanelSettingsTheme.secondary)
            .accessibilityHidden(true)
        }.padding(.vertical, 14)
    }
}

enum IslandSettingsEffectPreviewMetrics {
    static let previewCornerRadius: CGFloat = 8
    static let height: CGFloat = 36
}

struct IslandSettingsEffectOptionStyle: ButtonStyle {
    let effect: ActivityIslandProgressEffect
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
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
                .opacity(selected || hovered ? 1 : 0.65)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PanelSettingsTheme.clay)
                            .background(PanelSettingsTheme.surface, in: Circle()).padding(4)
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            configuration.label.font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? PanelSettingsTheme.clay : PanelSettingsTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity).contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? PanelSettingsTheme.clay : .clear, lineWidth: 1.5).padding(-3))
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : PanelSettingsTheme.hoverMotion, value: hovered)
        .animation(reduceMotion ? nil : PanelSettingsTheme.pressMotion, value: configuration.isPressed)
        .onHover { hovered = $0 }.onDisappear { hovered = false }
    }
}
