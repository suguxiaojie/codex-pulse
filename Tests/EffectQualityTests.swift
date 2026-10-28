import AppKit

@MainActor enum EffectQualityTests {
    static func run() {
        var checks = 0
        func expect(_ value: Bool, _ title: String) { precondition(value, title); checks += 1 }
        let original = ActivityStateSmokeQuality.current
        defer { ActivityStateSmokeQuality.current = original }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let view = ActivityStateSmokeMetalView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(view)
        guard view.isRendererAvailable else { print("Effect quality: SKIP, Metal unavailable"); return }
        let scale = window.backingScaleFactor
        for quality in ActivityIslandEffectQuality.allCases {
            ActivityStateSmokeQuality.current = quality
            expect(view.preferredFramesPerSecond == quality.framesPerSecond, "live card follows the quality frame rate")
            expect(view.drawableSize == CGSize(width: ceil(200 * scale * quality.resolutionScale),
                                               height: ceil(100 * scale * quality.resolutionScale)),
                   "live card follows the quality resolution")
            view.setFullSurfacePresentation(true)
            expect(view.preferredFramesPerSecond == quality.fullSurfaceFramesPerSecond, "full-surface card uses the lower rate")
            view.setFullSurfacePresentation(false)
        }
        let preview = CodexActivityStateSmokePreviewHostView(frame: CGRect(x: 0, y: 0, width: 120, height: 60), effect: .stateSmoke)
        ActivityStateSmokeQuality.current = .smooth
        let previewSmoke = preview.subviews.compactMap { $0 as? ActivityStateSmokeMetalView }.first
        expect(previewSmoke?.preferredFramesPerSecond == 24 && previewSmoke?.managesDrawableSize == false,
               "settings preview keeps its own frame rate and drawable")
        print("Effect quality: \(checks)/\(checks) passed")
    }
}
