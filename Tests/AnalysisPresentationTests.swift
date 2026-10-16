import SwiftUI

@main enum AnalysisPresentationTests {
    static func main() {
        let start = [CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 0)]
        let end = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)]
        let a = AnalysisTrendVector(points: start)
        let b = AnalysisTrendVector(points: end)
        var delta = b - a
        delta.scale(by: 0.5)
        let middle = a + delta
        let expected = [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)]
        expect(middle.points == expected, "midpoint contains real intermediate coordinates")
        var line = UsageTrendLine(points: start)
        line.animatableData = middle
        expect(line.points == expected, "line Shape consumes its animatable coordinates")
        var area = UsageTrendArea(points: start)
        area.animatableData = middle
        expect(area.points == expected, "area follows the same intermediate path as the line")
        expect(line.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect.midY == 50, "rendered line is intermediate rather than snapping to the final data")
        expect((a + .zero).points == start, "empty zero does not truncate the series")
        expect((a - a).magnitudeSquared == 0, "equal data has no geometric movement")
        expect(UsageTrendLine(points: []).path(in: .zero).isEmpty, "empty series renders safely")
        var stationary = b - a
        stationary.scale(by: 0)
        expect((a + stationary).points == start, "zero animation progress retains the old line")
        var completed = b - a
        completed.scale(by: 1)
        expect((a + completed).points == end, "completed progress reaches the exact final points")
        let samples = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 10), CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 5), CGPoint(x: 4, y: 5), CGPoint(x: 5, y: 0)]
        let segments = AnalysisSmoothCurve.segments(samples)
        expect(segments.count == samples.count - 1, "every pair of actual data anchors has one curve segment")
        for (index, segment) in segments.enumerated() {
            expect(segment.point(at: 0) == samples[index] && segment.point(at: 1) == samples[index+1], "curve passes through every real sample")
            let lower = min(samples[index].y, samples[index+1].y), upper = max(samples[index].y, samples[index+1].y)
            for step in 0...100 {
                let point = segment.point(at: CGFloat(step) / 100)
                expect(point.y >= lower - 0.000001 && point.y <= upper + 0.000001, "smoothing must not invent a peak, trough or negative overshoot")
            }
        }
        expect(segments[0].control2.y == 10 && segments[1].control1.y == 10, "peak has a shared horizontal tangent instead of a sharp corner")
        expect(segments[3].control1.y == 5 && segments[3].control2.y == 5, "flat samples remain flat")
        expect(AnalysisSmoothCurve.segments([CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 2)]).isEmpty, "duplicate x coordinates do not divide by zero")
        expect(AnalysisSmoothCurve.segments([CGPoint(x: 0, y: CGFloat.nan), CGPoint(x: 1, y: 2)]).isEmpty, "invalid coordinates are rejected")
        var hasCurve = false
        UsageTrendLine(points: samples).path(in: .zero).cgPath.applyWithBlock { element in
            if element.pointee.type == .addCurveToPoint { hasCurve = true }
        }
        expect(hasCurve, "the actual rendered Shape uses Bezier segments")
        expect(AnalysisBarLayout.width(slotWidth: 150, count: 7, hourly: false) == 24, "weekly columns keep their slender width on wide windows")
        expect(AnalysisBarLayout.width(slotWidth: 20, count: 7, hourly: false) <= 20, "weekly columns stay inside narrow slots")
        expect(AnalysisBarLayout.width(slotWidth: 40, count: 30, hourly: false) == 14, "monthly columns use the denser width")
        print("Analysis presentation: interpolation, monotone curve and bar layout checks passed")
    }
    private static func expect(_ value: Bool, _ message: String) {
        guard value else { fatalError(message) }
    }
}
