import Foundation

@main
@MainActor
struct ActivityIslandLifecycleTests {
    private static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ title: String) {
        checks += 1
        if !condition() { fatalError(title) }
    }
    static func main() {
        var idle = ActivityIslandLifecycle()
        expect(idle.presentation == .compact, "empty startup retains primary compact banner")
        expect(idle.handle(.becameIdle) == .compact && !idle.isCompletion, "idle clears completion without hiding")
        _ = idle.handle(.pointerEntered)
        expect(idle.handle(.becameIdle) == .expanded, "empty refresh does not close manual idle preview")
        _ = idle.handle(.collapseRequested)
        _ = idle.handle(.activityEnded, now: Date(timeIntervalSince1970: 0), popupDuration: 3)
        expect(idle.handle(.expandedHoldElapsed, now: Date(timeIntervalSince1970: 3)) == .compact,
            "completion feedback transitions into a resident compact banner")
        expect(idle.handle(.becameIdle) == .compact && idle.collapseDeadline == nil, "expired receipt leaves stable idle state")
        var reading = ActivityIslandLifecycle()
        _ = reading.handle(.expandRequested)
        expect(reading.handle(.baseline(requiresAttention: false)) == .expanded && reading.expansion == .manual,
            "first native baseline cannot dismiss a manually opened usage page")
        _ = reading.handle(.pinRequested)
        expect(reading.handle(.baseline(requiresAttention: false)) == .expanded && reading.expansion == .pinned,
            "first native baseline preserves pinned usage page")
        let start = Date(timeIntervalSince1970: 1_000)
        var state = ActivityIslandLifecycle()
        expect(state.handle(.baseline(requiresAttention: false), now: start) == .compact, "cold start is compact baseline")
        expect(state.collapseDeadline == nil, "baseline does not replay historical automatic popup")
        _ = state.handle(.activityChanged(requiresAttention: false), now: start, popupDuration: 5)
        let deadline = start.addingTimeInterval(5)
        expect(state.presentation == .expanded && state.expansion == .automatic && state.collapseDeadline == deadline, "new task opens with fixed absolute deadline")
        for index in 1...40 {
            _ = state.handle(.contentUpdated(requiresAttention: false), now: start.addingTimeInterval(Double(index) / 10))
        }
        expect(state.collapseDeadline == deadline, "continuous tool/token/text updates do not postpone collapse")
        _ = state.handle(.pointerEntered, now: start.addingTimeInterval(1))
        expect(state.expansion == .automatic && state.collapseDeadline == deadline, "mouse entering automatic preview cannot claim it manually")
        expect(state.handle(.expandedHoldElapsed, now: start.addingTimeInterval(4)) == .expanded, "early callback cannot collapse before deadline")
        expect(state.handle(.expandedHoldElapsed, now: deadline) == .compact, "automatic preview collapses at deadline even with pointer inside")
        expect(state.handle(.contentUpdated(requiresAttention: false), now: deadline) == .compact, "routine update cannot reopen compact state")
        _ = state.handle(.pointerExited, now: deadline)
        expect(state.handle(.pointerEntered, now: deadline) == .expanded && state.expansion == .manual, "real hover on compact opens manual preview")
        expect(state.collapseDeadline == nil, "manual hover has no automatic timer")
        _ = state.handle(.pointerExited, now: deadline)
        expect(state.collapseDeadline == deadline.addingTimeInterval(0.45), "manual preview closes 450 ms after exit")
        _ = state.handle(.pointerEntered, now: deadline.addingTimeInterval(0.2))
        expect(state.collapseDeadline == nil, "reentering cancels manual close")
        _ = state.handle(.pointerExited, now: deadline)
        expect(state.handle(.expandedHoldElapsed, now: deadline.addingTimeInterval(0.5)) == .compact, "manual leave deadline collapses")
        _ = state.handle(.expandRequested, now: start)
        expect(state.expansion == .manual && state.collapseDeadline == nil, "explicit click claims manual preview")
        _ = state.handle(.pinRequested, now: start)
        _ = state.handle(.activityChanged(requiresAttention: false), now: start)
        _ = state.handle(.pointerExited, now: start)
        expect(state.expansion == .pinned && state.collapseDeadline == nil, "pin survives events and pointer exits")
        expect(state.handle(.collapseRequested, now: start) == .compact, "unpin or explicit collapse returns compact immediately")
        _ = state.handle(.contentUpdated(requiresAttention: true), now: start)
        expect(state.expansion == .attention && state.collapseDeadline == nil, "new approval opens without timeout")
        expect(state.handle(.expandedHoldElapsed, now: start.addingTimeInterval(100)) == .expanded, "approval ignores stale timer")
        _ = state.handle(.collapseRequested, now: start)
        expect(state.handle(.contentUpdated(requiresAttention: true), now: start) == .compact, "unchanged approval respects explicit collapse")
        _ = state.handle(.pointerEntered, now: start)
        expect(state.handle(.contentUpdated(requiresAttention: false), now: start) == .compact, "resolved approval closes manual preview as upstream does")
        _ = state.handle(.activityEnded, now: start)
        expect(state.isCompletion && state.expansion == .automatic, "completion opens automatic receipt")
        expect(state.handle(.expandedHoldElapsed, now: start.addingTimeInterval(3)) == .compact, "completion receipt also compacts at deadline")
        _ = state.handle(.activityChanged(requiresAttention: false), now: start, popupDuration: 5)
        _ = state.handle(.activityChanged(requiresAttention: false), now: start.addingTimeInterval(2), popupDuration: 5)
        expect(state.collapseDeadline == start.addingTimeInterval(7), "a genuinely new task event can extend automatic popup")
        var off = ActivityIslandLifecycle()
        expect(off.handle(.activityChanged(requiresAttention: false), automaticPopup: false, now: start) == .compact, "disabled automatic popup keeps new task compact")
        expect(off.handle(.contentUpdated(requiresAttention: true), automaticPopup: false, now: start) == .compact, "disabled popup does not force approval open")
        expect(off.handle(.pointerEntered, automaticPopup: false, now: start) == .expanded, "disabled automatic popup still permits manual hover")

        // Exercise the same timer used by the production controller, under a
        // stream of refreshes. This catches cancellation/rearm starvation.
        let timer = ActivityIslandCollapseTimer()
        var fired = 0
        let due = Date().addingTimeInterval(0.2)
        let wait = Date().addingTimeInterval(0.6)
        while Date() < wait && fired == 0 {
            timer.update(deadline: due) { fired += 1 }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        expect(fired == 1, "production collapse timer fires despite frequent updates with same deadline")
        timer.update(deadline: Date().addingTimeInterval(0.02)) { fired += 1 }
        timer.update(deadline: nil) { fired += 1 }
        let cancelWait = Date().addingTimeInterval(0.06)
        while Date() < cancelWait { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        expect(fired == 1, "cancelling a pinned or manual timer prevents stale callback")
        print("Activity Island tests passed: \(checks)")
    }
}
