import AppKit
import SwiftUI

@MainActor enum IslandMascotTests {
    static func run() {
        var checks = 0
        func expect(_ value: Bool, _ title: String) { precondition(value, title); checks += 1 }
        var row = ActivitySessionSnapshot(sessionID: "mascot", turnID: "turn", projectID: "p", projectName: "P",
            title: "private title", phase: .starting, actionText: "", updatedAt: Date(), tokenUsage: nil)
        for (phase, mood): (TaskPhase, IslandMascotMood) in [(.starting, .think), (.working, .think), (.usingTool, .tool),
            (.waitingApproval, .approve), (.completed, .done), (.failed, .fail), (.ended, .idle)] {
            row.phase = phase
            expect(IslandMascotMood.mood(for: row) == mood, "phase maps to mascot mood")
            expect(IslandMascotMood.mood(for: row.hidingDetails()) == mood, "privacy preserves mood")
        }
        row.phase = .waitingApproval; row.waitReason = .userInput
        expect(IslandMascotMood.mood(for: row) == .reply, "user input is reply")
        row.endReason = .cancelled
        expect(IslandMascotMood.mood(for: row) == .idle, "cancellation takes priority")
        expect(IslandMascotMood.mood(for: nil) == .idle, "no session is idle")
        let rect = CGRect(x: 10, y: 20, width: 100, height: 40)
        func gaze(_ point: CGPoint) -> CGSize { IslandMascotGeometry.gazeOffset(pointer: point, islandRect: rect) }
        expect(gaze(CGPoint(x: 60, y: 40)) == .zero, "center has zero gaze")
        expect(gaze(CGPoint(x: 80, y: 40)).width > 0, "inside point tracks")
        let edge = gaze(CGPoint(x: 350, y: 40))
        expect(abs(edge.width - 3.15) < 0.001 && edge.height == 0, "240 pt boundary is included and clamped")
        expect(gaze(CGPoint(x: 350.01, y: 40)) == .zero, "outside 240 pt resets gaze")
        let diagonal = gaze(CGPoint(x: 200, y: 200))
        expect(hypot(diagonal.width, diagonal.height) <= 3.15001 && diagonal.height < 0, "vector clamped and screen Y inverted")
        expect(IslandMascotGeometry.gazeOffset(pointer: .zero, islandRect: .zero) == .zero, "invalid geometry resets gaze")
        let model = ActivityIslandViewModel()
        let context = model.mascotContext
        row.phase = .completed; row.endReason = .completed; row.waitReason = nil
        context.noteCompletion(row, serial: 1, playable: true)
        expect(context.claimCompletion(row, serial: 1), "completion serial triggers once")
        let rebuilt = NSHostingView(rootView: IslandSessionMascot(row: row, size: 20, animated: true, reduceMotion: false)
            .environment(\.islandMascotContext, context).environment(\.islandMascotSerial, 1))
        _ = rebuilt.fittingSize
        expect(!context.claimCompletion(row, serial: 1), "view reconstruction cannot replay completion")
        context.noteCompletion(row, serial: 2, playable: false)
        expect(!context.claimCompletion(row, serial: 2), "hidden or reduced-motion completion consumed without playback")
        row.isRetainedReceipt = true
        context.noteCompletion(row, serial: 3, playable: true)
        expect(!context.claimCompletion(row, serial: 3), "retained receipt never bounces")
        row.isRetainedReceipt = false; row.phase = .waitingApproval; row.endReason = nil; row.waitReason = .userInput
        row.replyRequestIDs = ["question"]
        expect(model.claimReplyCue(for: row) && context.claimReply(row), "mascot uses original request cue")
        expect(!model.claimReplyCue(for: row) && !context.claimReply(row), "same reply request never replays")
        row.replyRequestIDs = ["next-question"]
        expect(model.claimReplyCue(for: row) && context.claimReply(row), "new request can animate")
        expect(context.claimFailure(row) && !context.claimFailure(row), "failure shakes only once per turn")
        context.update(visible: true, reduceMotion: true, islandRect: rect)
        expect(!context.enabled && context.monitorCount == 0, "Reduce Motion installs no mouse monitors")
        context.update(visible: false, reduceMotion: false, islandRect: rect)
        expect(context.monitorCount == 0, "hidden island installs no monitors")
        context.update(visible: true, reduceMotion: false, islandRect: rect)
        expect(context.enabled && context.monitorCount > 0, "visible island installs local mouse tracking")
        context.update(visible: false, reduceMotion: false, islandRect: rect)
        expect(!context.enabled && context.monitorCount == 0 && context.gaze == .zero, "hide removes all monitors and clears gaze")
        func orbs(_ view: NSView) -> [RippleGlowHostView] {
            (view as? RippleGlowHostView).map { [$0] } ?? view.subviews.flatMap(orbs)
        }
        let moods: [IslandMascotMood] = [.think, .tool, .approve, .reply, .done, .fail, .idle]
        for mood in moods {
            let host = NSHostingView(rootView: IslandMascotView(mood: mood, size: 26, animated: false, reduceMotion: true))
            host.frame = CGRect(x: 0, y: 0, width: 26, height: 26); host.layoutSubtreeIfNeeded()
            expect(orbs(host).isEmpty, "card Clawd draws pixels without a RippleGlow host")
        }

        // Sprite: feet stay anchored at y = 0 for every pose and squash.
        for mood in moods {
            for arms: IslandClawdPose.Arms in [.side, .up, .down, .hang, .oneLeft, .oneRight, .oneWave] {
                for squash: CGFloat in [0.6, 0.97, 1] {
                    var pose = IslandClawdPose(mood: mood, arms: arms); pose.squashY = squash
                    let pixels = IslandClawdSprite.pixels(pose)
                    expect(pixels.allSatisfy { $0.rect.maxY <= 0.0001 }, "sprite never extends below the feet")
                    expect(pose.legsTucked || abs((pixels.map(\.rect.maxY).max() ?? 1)) < 0.0001, "legs reach the feet line")
                    expect(pixels.allSatisfy { $0.rect.minX >= -5.6 && $0.rect.maxX <= 5.6 }, "sprite stays 11 pixels wide")
                }
            }
        }
        expect(IslandClawdPose(mood: .idle).legsTucked && IslandClawdPose(mood: .idle).eyes == .closed, "idle sleeps with tucked legs")
        expect(IslandClawdPose(mood: .fail).eyes == .cross && IslandClawdPose(mood: .done).eyes == .happy, "terminal eyes")
        expect(!IslandClawdSprite.pixels(IslandClawdPose(mood: .approve)).contains { $0.ink == .glint }, "pixel-art eyes carry no glint")

        for height: CGFloat in [32, 37, 40] {
            model.metrics = ActivityIslandPanelMetrics(rowCount: 1, availableSize: CGSize(width: 1200, height: 800), safeAreaTop: height)
            for size in IslandClawdSize.allCases {
                model.clawdSize = size
                expect(model.compactClawdPixel <= size.pixel, "compact pixel never exceeds preference")
                expect(model.compactClawdPixel * 12 <= height - 4, "entire badge grid fits with two-point margins")
                expect(model.floatingUsageCompactOffset == 24, "badge requires no hanging clearance")
            }
        }
        for state: IslandClawdBadgeState in [.idle, .start, .think, .tool, .approve, .reply, .done, .fail] {
            let images = IslandClawdBadgeRenderer.images(state, pixel: 2.2, scale: 2, gaze: 0)
            expect(!images.isEmpty, "every clip renders")
            expect(images.count == IslandClawdBadgeClips.clip(state).frames.count, "every frame is retained")
            expect(IslandClawdBadgeRenderer.stillImage(state, pixel: 2.2, scale: 2) != nil, "static expression renders")
        }
        // Codex pet: same states, same frame contract, its own art; the provider decides which pet appears.
        for state: IslandClawdBadgeState in [.idle, .start, .think, .tool, .approve, .reply, .done, .fail] {
            let codex = IslandClawdBadgeRenderer.images(state, pixel: 2.2, scale: 2, gaze: 0, species: .codex)
            expect(codex.count == IslandCodexClips.clip(state).frames.count, "every Codex frame renders")
            expect(IslandClawdBadgeRenderer.stillImage(state, pixel: 2.2, scale: 2, species: .codex) != nil, "Codex expression renders")
            expect(IslandCodexClips.clip(state).duration > 0, "Codex clip has a duration")
            let clawdFirst = IslandClawdBadgeRenderer.images(state, pixel: 2.2, scale: 2, gaze: 0).first
            expect(clawdFirst?.dataProvider?.data as Data? != codex.first?.dataProvider?.data as Data?, "Codex art differs from Clawd")
        }
        expect(IslandClawdBadgeRenderer.timing(.start, species: .codex).duration == IslandClawdBadgeRenderer.timing(.start, species: .clawd).duration,
               "both pets hand off from start to work at the same moment")
        expect(IslandPetSpecies(provider: "Codex") == .codex && IslandPetSpecies(provider: "Claude Code") == .clawd,
               "provider picks the pet")
        let petModel = ActivityIslandViewModel()
        expect(petModel.idlePetSpecies == .codex, "idle defaults to the Codex pet before Claude Code is seen")
        var claudeRow = ActivitySessionSnapshot(sessionID: "pet-claude", turnID: "t", projectID: "p", projectName: "P",
            title: "Claude", phase: .working, actionText: "", updatedAt: Date(), tokenUsage: nil)
        claudeRow.provider = "Claude Code"
        let codexRow = ActivitySessionSnapshot(sessionID: "pet-codex", turnID: "t", projectID: "p", projectName: "P",
            title: "Codex", phase: .working, actionText: "", updatedAt: Date().addingTimeInterval(-60), tokenUsage: nil)
        petModel.sessions = [codexRow, claudeRow]
        expect(petModel.idlePetSpecies == .clawd, "idle follows the most recently active client")
        petModel.sessions = []
        expect(petModel.idlePetSpecies == .clawd, "idle keeps the last active pet once sessions clear")
        let codexBadge = IslandClawdBadgeView(frame: .zero)
        codexBadge.apply(mood: .tool, pixel: 2.2, gaze: 0, reduceMotion: true, playing: true, species: .codex)
        expect(codexBadge.shown == .tool && codexBadge.species == .codex, "badge shows the Codex pet")
        let badge = IslandClawdBadgeView(frame: .zero)
        badge.apply(mood: .think, pixel: 2.2, gaze: 0, reduceMotion: true, playing: true)
        expect(badge.shown == .think, "reduced motion skips start reaction")
        badge.apply(mood: .reply, pixel: 2.2, gaze: 0, reduceMotion: false, playing: false)
        expect(badge.shown == .reply, "hidden badge keeps current expression")

        let mascotSource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexNotchMonitor/ActivityIslandMascot.swift")
        let source = try! String(contentsOf: mascotSource, encoding: .utf8)
        expect(!source.contains("RippleGlowOrb("), "mascot implementation does not reference the old orb")
        expect(!source.contains("TimelineView("), "card expressions have no frame clock")
        print("Island mascot: \(checks)/\(checks) passed")
    }
}
