import AppKit
import SwiftUI

@MainActor enum IslandDesktopPreviewTests {
    static func run() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
        let now = Date(timeIntervalSince1970: 1000)
        let rows = ActivityIslandDesktopPreview.sampleRows(now: now, privacy: false)
        expect(rows.count == 2 && rows[0].title == "整理项目资料", "neutral synthetic focus and rail")
        expect(rows[0].recentSteps.map(\.state) == [.done, .done, .running], "focus displays step history")
        expect(rows[0].tokenUsage?.total == 12800 && rows[0].sessionTotalTokens == 128000, "turn tokens distinct from session total")
        expect(rows[0].startedAt == now.addingTimeInterval(-120), "stable sample timing")
        for effect in ActivityIslandProgressEffect.allCases {
            for privacy in [false, true] {
                let preview = ActivityIslandDesktopPreview(material: .liquidGlass, degree: 0.8, effect: effect,
                    expandedWidth: 680, animated: false, reduceMotion: true, privacyMode: privacy)
                let stage = preview.stage(width: 510)
                expect(stage.effect == effect && stage.reduceMotion && !stage.animated, "live settings reach production stage")
                expect(stage.focusedID == stage.rows.first?.id && stage.rows.count == 2, "single focus with session rail")
                expect(preview.showsUsage == !privacy, "privacy hides external quota")
                expect(stage.rows.allSatisfy { $0.isPrivate == privacy }, "privacy applies to every session")
                if privacy {
                    expect(stage.rows.allSatisfy { $0.recentSteps.isEmpty && $0.tokenUsage == nil && $0.modelName == nil }, "privacy removes sample details")
                    expect(stage.quotaTitle == "额度已隐藏", "privacy hides header quota")
                }
                expect(preview.stageHeight + IslandHardwareBlack.shadowBottomInset <= 340, "preview reserves room for shadow")
                let host = NSHostingView(rootView: preview.frame(width: 620, height: 340))
                host.frame = CGRect(x: 0, y: 0, width: 620, height: 340)
                host.layoutSubtreeIfNeeded()
                expect(host.fittingSize == CGSize(width: 620, height: 340), "normal and enlarged preview fit shared canvas")
            }
        }
        var preview = ActivityIslandDesktopPreview(material: .classic, degree: 0.2, effect: .stateSmoke,
            expandedWidth: 600, animated: true, reduceMotion: false, floatingUsageEnabled: false)
        expect(!preview.showsUsage && preview.stage(width: 450).animated, "visibility and capsule settings reach preview")
        preview.privacyMode = true
        expect(preview.stage(width: 450).rows.allSatisfy(\.isPrivate), "settings update without rebuilding fixture state")
        print("Island desktop preview: \(checks)/\(checks) passed")
    }
}
