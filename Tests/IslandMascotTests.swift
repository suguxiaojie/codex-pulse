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
        let blink = IslandMascotBlink()
        blink.update(active: false)
        expect(!blink.isRunning && !blink.closed, "static presentation starts no blink task")
        blink.update(active: true)
        expect(blink.isRunning, "visible animated expression starts blink task")
        blink.update(active: false)
        expect(!blink.isRunning && !blink.closed, "hide or reduced motion cancels blink task")
        func orbs(_ view: NSView) -> [RippleGlowHostView] {
            (view as? RippleGlowHostView).map { [$0] } ?? view.subviews.flatMap(orbs)
        }
        for mood: IslandMascotMood in [.think, .tool, .approve, .reply, .done, .fail, .idle] {
            let host = NSHostingView(rootView: IslandMascotView(mood: mood, size: 26, animated: false, reduceMotion: true))
            host.frame = CGRect(x: 0, y: 0, width: 26, height: 26); host.layoutSubtreeIfNeeded()
            expect(orbs(host).isEmpty, "all moods use mascot gradient bodies without a RippleGlow host")
        }
        func motion(_ mood: IslandMascotMood, _ time: Double, animated: Bool = true, reduced: Bool = false) -> IslandMascotMotionFrame {
            .frame(mood: mood, time: time, animated: animated, reduceMotion: reduced)
        }
        expect(abs(motion(.think, 0.6).orbitDegrees - 90) < 0.0001, "think dot advances a quarter orbit in 0.6 seconds")
        expect(abs(motion(.think, 1.2).orbitDegrees - 180) < 0.0001, "think dot has constant angular speed")
        expect(abs(motion(.think, 2.4).orbitDegrees) < 0.0001, "think orbit repeats at 2.4 seconds")
        expect(abs(motion(.tool, 0.275).toolDegrees - 90) < 0.0001, "tool arc advances a quarter turn in 0.275 seconds")
        expect(abs(motion(.tool, 1.1).toolDegrees) < 0.0001, "tool arc repeats at 1.1 seconds")
        for mood: IslandMascotMood in [.think, .tool] {
            expect(abs(motion(mood, 0.8).breathingScale - 1.035) < 0.0001, "running breath peaks at 3.5 percent")
            expect(abs(motion(mood, 2.4).breathingScale - 0.965) < 0.0001, "running breath contracts at 3.5 percent")
            expect(abs(motion(mood, 3.2).breathingScale - 1) < 0.0001, "running breath repeats at 3.2 seconds")
            expect(motion(mood, 0.6, animated: false) == motion(mood, 9, animated: false), "hidden motion frame is time-independent")
            expect(motion(mood, 0.6, reduced: true) == motion(mood, 9, reduced: true), "Reduce Motion frame is time-independent")
        }
        expect(abs(motion(.think, 0.9).lookX - 2.7) < 0.0001 && abs(motion(.think, 2.7).lookX - 0.1) < 0.0001,
            "thinking eyes scan around the upper-right offset every 3.6 seconds")
        let look = CGSize(width: 2, height: -1)
        expect(IslandMascotMotionFrame.gaze(look, mood: .tool, animated: true, reduceMotion: false) == look, "tool squint follows gaze")
        expect(IslandMascotMotionFrame.gaze(look, mood: .tool, animated: true, reduceMotion: true) == .zero, "reduced-motion tool ignores gaze")
        expect(IslandMascotMotionFrame.gaze(look, mood: .tool, animated: false, reduceMotion: false) == .zero, "hidden tool ignores gaze")
        expect(abs(IslandMascotMotionFrame.eyeScale(mood: .tool, closed: false, animated: true, reduceMotion: false) - 0.45) < 0.0001,
            "tool eyes rest at 45 percent height")
        expect(abs(IslandMascotMotionFrame.eyeScale(mood: .tool, closed: true, animated: true, reduceMotion: false) - 0.054) < 0.0001,
            "tool blink amplitude is scaled by the squint")
        expect(IslandMascotMotionFrame.eyeScale(mood: .tool, closed: true, animated: true, reduceMotion: true) == 0.45,
            "Reduce Motion preserves a static squint")
        let mascotSource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexNotchMonitor/ActivityIslandMascot.swift")
        let source = try! String(contentsOf: mascotSource, encoding: .utf8)
        expect(!source.contains("RippleGlowOrb("), "mascot implementation does not reference the old orb")
        expect(source.contains("paused: !moving"), "hidden and reduced-motion timelines are paused")
        print("Island mascot: \(checks)/\(checks) passed")
    }
}
