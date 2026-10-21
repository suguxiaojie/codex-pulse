import AppKit
import SwiftUI

@MainActor enum IslandHardwareBlackTests {
    static func run() {
        var checks = 0
        func expect(_ condition: Bool, _ title: String) { precondition(condition, title); checks += 1 }
        let palette: [(IslandMascotMood, UInt32)] = [(.think, 0x9AA8FF), (.tool, 0x62D0FF), (.approve, 0xFFB340),
            (.reply, 0xFFB340), (.done, 0x4CD47A), (.fail, 0xFF5A4E), (.idle, 0xA2A8B6)]
        for (mood, rgb) in palette {
            let color = NSColor(mood.middleColor).usingColorSpace(.sRGB)!
            expect(abs(color.redComponent - Double((rgb >> 16) & 255) / 255) < 0.001
                && abs(color.greenComponent - Double((rgb >> 8) & 255) / 255) < 0.001
                && abs(color.blueComponent - Double(rgb & 255) / 255) < 0.001, "edge uses mascot middle color")
        }
        expect(IslandHardwareBlack.mood(rows: [], focusedID: nil, compact: false, showsCompactQuota: false, receipt: nil) == .idle,
            "empty expanded island uses idle edge")
        var row = ActivitySessionSnapshot(sessionID: "edge", turnID: "turn", projectID: "p", projectName: "P", title: "T",
            phase: .working, actionText: "", updatedAt: Date(), tokenUsage: nil)
        for (phase, mood): (TaskPhase, IslandMascotMood) in [(.working, .think), (.usingTool, .tool), (.waitingApproval, .approve),
            (.completed, .done), (.failed, .fail), (.ended, .idle)] {
            row.phase = phase
            expect(IslandHardwareBlack.mood(rows: [row], focusedID: row.id, compact: false, showsCompactQuota: false, receipt: nil) == mood,
                "expanded edge follows focus")
        }
        row.phase = .waitingApproval; row.waitReason = .userInput
        expect(IslandHardwareBlack.mood(rows: [row], focusedID: row.id, compact: false, showsCompactQuota: false, receipt: nil) == .reply,
            "reply edge follows reply mood")
        expect(IslandHardwareBlack.mood(rows: [row], focusedID: row.id, compact: true, showsCompactQuota: true, receipt: nil) == .idle,
            "quota branch always uses static idle edge")
        for (degree, expected) in [(0.2, 0.25), (0.45, 0.5625), (0.8, 1.0)] {
            expect(abs(IslandHardwareBlack.coreOpacity(degree: degree, compact: false, idle: false) - expected) < 0.00001, "expanded intensity")
            expect(abs(IslandHardwareBlack.coreOpacity(degree: degree, compact: true, idle: false) - expected * 0.6) < 0.00001, "compact intensity coefficient")
            expect(abs(IslandHardwareBlack.coreOpacity(degree: degree, compact: false, idle: true) - expected * 0.5) < 0.00001, "idle intensity halved")
            expect(abs(IslandHardwareBlack.coreOpacity(degree: degree, compact: true, idle: true) - expected * 0.3) < 0.00001, "compact idle intensity")
            expect(IslandHardwareBlack.sliderValue(degree) == degree, "slider is direct rather than inverted")
        }
        let suite = "island-hardware-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.45, forKey: ActivityIslandPreferenceKey.glassDegree)
        let stored = ActivityIslandPreferences.load(from: defaults).glassDegree
        expect(Int((IslandHardwareBlack.sliderValue(stored) * 100).rounded()) == 45, "saved 0.45 displays 45 percent")
        expect(abs(IslandHardwareBlack.coreOpacity(degree: stored, compact: false, idle: false) - 0.5625) < 0.00001, "saved default edge intensity is about 0.56")
        expect(defaults.double(forKey: ActivityIslandPreferenceKey.glassDegree) == 0.45, "loading does not rewrite saved value")
        let model = ActivityIslandViewModel(); model.presentation = .expanded
        let baseMetrics = ActivityIslandPanelMetrics(rowCount: 1, availableSize: CGSize(width: 1200, height: 800))
        let metrics = ActivityIslandPanelMetrics(shadowing: baseMetrics)
        model.metrics = metrics
        let surface = ActivityIslandSurface(model: model)
        surface.frame = CGRect(origin: .zero, size: metrics.hostSize)
        expect(surface.frame.height == baseMetrics.hostSize.height + 72, "drawing canvas reserves shadow below existing canvas")
        expect(metrics.hostSize.width == baseMetrics.hostSize.width + 128, "drawing canvas reserves both sides for shadow")
        expect(metrics.expandedRect.size == baseMetrics.expandedRect.size && metrics.compactRect.size == baseMetrics.compactRect.size,
            "drawing margins do not enlarge either interactive surface")
        for material in ActivityIslandMaterial.allCases {
            surface.update(metrics: metrics, compact: false, animated: false, material: material, degree: 0.45)
            expect(surface.targetRect == metrics.expandedRect, "shadow margin does not change island geometry")
            expect(surface.containsSurfacePoint(CGPoint(x: metrics.expandedRect.midX, y: metrics.expandedRect.midY)), "original body remains interactive")
            expect(!surface.containsSurfacePoint(CGPoint(x: metrics.expandedRect.midX, y: metrics.expandedRect.maxY + 20)), "shadow is not interactive")
            expect(!surface.containsSurfacePoint(CGPoint(x: metrics.expandedRect.midX, y: surface.bounds.height - 1)), "extra bottom margin passes pointer through")
            expect(!surface.containsSurfacePoint(CGPoint(x: 20, y: metrics.expandedRect.midY))
                && !surface.containsSurfacePoint(CGPoint(x: surface.bounds.width - 20, y: metrics.expandedRect.midY)),
                "both extra side margins pass pointer through")
            let shell = surface.layer!.sublayers!.compactMap { $0 as? CAShapeLayer }.first!
            let color = NSColor(cgColor: shell.fillColor!)!.usingColorSpace(.sRGB)!
            expect(color.alphaComponent == 1 && color.redComponent == 0 && color.greenComponent == 0 && color.blueComponent == 0,
                "both legacy material settings retain an opaque pure-black shell")
        }
        surface.update(metrics: metrics, compact: true, animated: false, material: .liquidGlass)
        expect(!surface.containsSurfacePoint(CGPoint(x: metrics.compactRect.midX, y: metrics.compactRect.maxY + 20)), "compact shadow margin also passes through")
        print("Island hardware black: \(checks)/\(checks) passed")
    }
}
