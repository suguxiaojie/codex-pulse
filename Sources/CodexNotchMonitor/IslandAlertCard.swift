import SwiftUI

extension IslandAlert {
    var mood: IslandMascotMood { kind == .tiboSignal ? .tool : .done }
    var tint: Color {
        kind == .tiboSignal ? Color(red: 98/255, green: 208/255, blue: 1)
            : Color(red: 76/255, green: 212/255, blue: 122/255)
    }
}

struct IslandAlertCard: View {
    @ObservedObject var model: ActivityIslandViewModel
    let alert: IslandAlert
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IslandMascotView(mood: alert.mood, size: 30,
                    animated: model.playbackVisible, reduceMotion: reduceMotion)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                    HStack(spacing: 6) {
                        if !alert.subtitle.isEmpty {
                            Text(alert.subtitle).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        if alert.isPendingSource {
                            Text("确认中").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(red: 1, green: 179/255, blue: 64/255))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.13), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { model.onDismissAlert?() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45)).frame(width: 22, height: 22)
                }.buttonStyle(.plain).accessibilityLabel("关闭提醒")
            }
            Text(alert.body).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(Array(alert.actions.enumerated()), id: \.offset) { index, action in
                    let primary = index == alert.actions.count - 1
                    Button { model.onAlertAction?(action.route, alert) } label: {
                        Text(action.title).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(primary ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(primary ? alert.tint : .white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            GeometryReader { proxy in
                Rectangle().fill(alert.tint)
                    .frame(width: proxy.size.width * max(0, min(1, model.alertRemaining / 8)))
            }.frame(height: 2).accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
        .padding(.top, model.metrics.hardwareGap > 0 ? model.metrics.compactRect.height : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001).onTapGesture { model.onAlertAction?(.openCenter, alert) })
        .accessibilityElement(children: .contain)
    }
}

/// Wrap the protected backdrop rather than changing its implementation.
struct IslandAlertBackdrop: View {
    @ObservedObject var model: ActivityIslandViewModel
    @ObservedObject var geometry: IslandGlassGeometry
    var body: some View {
        if let alert = model.alert {
            let value = geometry.value
            ZStack(alignment: .topLeading) {
                Color.clear
                IslandHardwareBackdrop(radius: value.radius, compact: value.compact, degree: geometry.degree,
                    mood: alert.mood, reduceMotion: model.reduceMotionOverride)
                    .frame(width: value.rect.width, height: value.rect.height)
                    .position(x: value.rect.midX, y: value.rect.midY)
            }.id(geometry.generation).allowsHitTesting(false).accessibilityHidden(true)
        } else { IslandExpandedGlassBackdrop(model: model, geometry: geometry) }
    }
}
