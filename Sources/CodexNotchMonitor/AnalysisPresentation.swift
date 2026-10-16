import SwiftUI

/// Shared presentation for the two analysis pages; pricing and statistics stay in their services.
enum AnalysisMotion {
    static let control = Animation.spring(response: 0.30, dampingFraction: 0.9)
    static let data = Animation.easeInOut(duration: 0.32)
    static let swap = Animation.easeInOut(duration: 0.22)
}

struct AnalysisCard: ViewModifier {
    var primary = false
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(Color.white.opacity(primary ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(primary ? 0.10 : 0.065), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
    }
}

struct AnalysisPeriodPicker: View {
    let options: [String]
    @Binding var selection: String
    var accessibilityTitle = "统计周期"
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(reduceMotion ? nil : AnalysisMotion.control) { selection = option }
                } label: {
                    Text(option)
                        .font(MonitorDesktopTypography.control)
                        .foregroundStyle(selection == option ? MonitorDesktopTheme.primaryText : MonitorDesktopTheme.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(AnalysisPeriodButtonStyle())
                .accessibilityValue(selection == option ? "已选择" : "")
            }
        }
        .padding(3)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.075), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}

/// The segment already owns its whole slot; do not add row padding around its selection layer.
struct AnalysisPeriodButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AnalysisRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.075 : hovered ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(hovered ? 0.07 : 0), lineWidth: 0.5))
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.992 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// SwiftUI's default Shape animation data is empty. Carry coordinates explicitly
/// so equal-length series have actual intermediate paths during data updates.
struct AnalysisTrendVector: VectorArithmetic {
    var coordinates: [CGFloat]
    init(points: [CGPoint]) { coordinates = points.flatMap { [$0.x, $0.y] } }
    private init(_ coordinates: [CGFloat]) { self.coordinates = coordinates }
    var points: [CGPoint] {
        stride(from: 0, to: coordinates.count - coordinates.count % 2, by: 2).map { CGPoint(x: coordinates[$0], y: coordinates[$0 + 1]) }
    }
    static let zero = Self([])
    static func + (lhs: Self, rhs: Self) -> Self {
        Self((0..<max(lhs.coordinates.count, rhs.coordinates.count)).map { (lhs.coordinates.indices.contains($0) ? lhs.coordinates[$0] : 0) + (rhs.coordinates.indices.contains($0) ? rhs.coordinates[$0] : 0) })
    }
    static func - (lhs: Self, rhs: Self) -> Self {
        Self((0..<max(lhs.coordinates.count, rhs.coordinates.count)).map { (lhs.coordinates.indices.contains($0) ? lhs.coordinates[$0] : 0) - (rhs.coordinates.indices.contains($0) ? rhs.coordinates[$0] : 0) })
    }
    mutating func scale(by rhs: Double) { coordinates = coordinates.map { $0 * rhs } }
    var magnitudeSquared: Double { coordinates.reduce(0) { $0 + Double($1 * $1) } }
}

/// Monotone cubic Hermite interpolation. Shared tangents round extrema while
/// bounded Bezier controls keep every segment within the adjacent sample range.
enum AnalysisSmoothCurve {
    struct Segment {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
        func point(at t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*u*start.x + 3*u*u*t*control1.x + 3*u*t*t*control2.x + t*t*t*end.x,
                           y: u*u*u*start.y + 3*u*u*t*control1.y + 3*u*t*t*control2.y + t*t*t*end.y)
        }
    }

    static func segments(_ points: [CGPoint]) -> [Segment] {
        guard points.count > 1, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        let widths = (0..<points.count-1).map { points[$0+1].x - points[$0].x }
        guard widths.allSatisfy({ $0 > 0 }) else { return [] }
        let slopes = widths.indices.map { (points[$0+1].y - points[$0].y) / widths[$0] }
        var tangents = Array(repeating: CGFloat.zero, count: points.count)
        tangents[0] = slopes[0]
        tangents[points.count-1] = slopes[slopes.count-1]
        if points.count > 2 {
            for index in 1..<points.count-1 {
                let left = slopes[index-1], right = slopes[index]
                if left * right > 0 {
                    let a = 2 * widths[index] + widths[index-1]
                    let b = widths[index] + 2 * widths[index-1]
                    tangents[index] = (a+b) / (a/left + b/right)
                }
            }
        }
        for index in slopes.indices {
            if slopes[index] == 0 {
                tangents[index] = 0; tangents[index+1] = 0
            } else {
                let a = tangents[index] / slopes[index], b = tangents[index+1] / slopes[index]
                let norm = a*a + b*b
                if norm > 9 {
                    let scale = 3 / sqrt(norm)
                    tangents[index] = scale * a * slopes[index]
                    tangents[index+1] = scale * b * slopes[index]
                }
            }
        }
        return slopes.indices.map { index in
            let start = points[index], end = points[index+1], h = widths[index] / 3
            let lower = min(start.y, end.y), upper = max(start.y, end.y)
            return Segment(start: start,
                           control1: CGPoint(x: start.x+h, y: min(upper, max(lower, start.y+tangents[index]*h))),
                           control2: CGPoint(x: end.x-h, y: min(upper, max(lower, end.y-tangents[index+1]*h))), end: end)
        }
    }
}

enum AnalysisBarLayout {
    static func width(slotWidth: CGFloat, count: Int, hourly: Bool) -> CGFloat {
        let target: CGFloat = count == 7 && !hourly ? 24 : 14
        return max(0, min(target, slotWidth * 0.65))
    }
}

struct UsageTrendLine: Shape {
    var points: [CGPoint]
    var animatableData: AnalysisTrendVector {
        get { AnalysisTrendVector(points: points) }
        set { points = newValue.points }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, first.x.isFinite, first.y.isFinite else { return path }
        path.move(to: first)
        for segment in AnalysisSmoothCurve.segments(points) {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
        return path
    }
}

struct UsageTrendArea: Shape {
    var points: [CGPoint]
    var animatableData: AnalysisTrendVector {
        get { AnalysisTrendVector(points: points) }
        set { points = newValue.points }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last,
              first.x.isFinite, first.y.isFinite, last.x.isFinite, last.y.isFinite else { return path }
        path.move(to: CGPoint(x: first.x, y: rect.maxY))
        path.addLine(to: first)
        for segment in AnalysisSmoothCurve.segments(points) {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Compact toolbar actions share hit area, hover and disabled contrast.
struct AnalysisToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MonitorDesktopTypography.control)
            .padding(.horizontal, 10).frame(height: 34)
            .background(.white.opacity(configuration.isPressed ? 0.10 : hovered && enabled ? 0.065 : 0.025), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(hovered && enabled ? 0.13 : 0.065), lineWidth: 0.5))
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet page-header action; progress follows the actual service state.
struct MonitorRefreshButton: View {
    let title: String
    let loadingTitle: String
    let isRefreshing: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRefreshing || reduceMotion)) { context in
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .rotationEffect(.degrees(isRefreshing && !reduceMotion
                            ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360 : 0))
                }
                .frame(width: 15, height: 15)
                ZStack {
                    Text(title).hidden()
                    Text(loadingTitle).hidden()
                    Text(isRefreshing ? loadingTitle : title)
                }
            }
        }
        .buttonStyle(MonitorQuietActionStyle())
        .disabled(isRefreshing)
        .accessibilityLabel(isRefreshing ? loadingTitle : title)
        .help(isRefreshing ? loadingTitle : title)
    }
}

private struct MonitorQuietActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MonitorDesktopTypography.control)
            .foregroundStyle(enabled ? MonitorDesktopTheme.secondaryText : MonitorDesktopTheme.tertiaryText)
            .padding(.horizontal, 11).frame(height: 34)
            .background(.white.opacity(enabled ? (configuration.isPressed ? 0.08 : hovered ? 0.045 : 0) : 0),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
