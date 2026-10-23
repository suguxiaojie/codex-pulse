import Foundation

@main struct IslandAlertTests {
    static func main() {
        let start = Date(timeIntervalSince1970: 100)
        func alert(_ id: String, title: String = "原文") -> IslandAlert {
            .init(id: id, kind: .quotaRecovery, title: title, subtitle: "", body: "测试",
                  isPendingSource: true, actions: [], sourceURL: nil)
        }
        var queue = IslandAlertQueue()
        queue.receive(alert("a"), enabled: true, available: true)
        queue.advance(now: start, blocked: true, hovered: false, available: true)
        precondition(queue.current == nil && queue.pending.count == 1)
        queue.receive(alert("a", title: "排队更新"), enabled: true, available: true)
        queue.advance(now: start, blocked: false, hovered: false, available: true)
        precondition(queue.current?.alert.title == "排队更新")
        queue.advance(now: start.addingTimeInterval(3), blocked: false, hovered: true, available: true)
        precondition(queue.current?.remaining == 5)
        queue.receive(alert("a", title: "显示更新"), enabled: true, available: true)
        precondition(queue.current?.remaining == 5 && queue.current?.alert.title == "显示更新")
        queue.advance(now: start.addingTimeInterval(100), blocked: false, hovered: false, available: true)
        precondition(queue.current?.remaining == 5)
        queue.advance(now: start.addingTimeInterval(102), blocked: true, hovered: false, available: true)
        precondition(queue.current == nil && queue.pending.first?.remaining == 3)
        queue.advance(now: start.addingTimeInterval(200), blocked: false, hovered: false, available: true)
        precondition(queue.current?.remaining == 3)
        queue.advance(now: start.addingTimeInterval(203), blocked: false, hovered: false, available: true)
        precondition(queue.current == nil)
        queue.receive(alert("a", title: "不再弹出"), enabled: true, available: true)
        precondition(queue.pending.isEmpty)
        for id in ["b", "c", "d", "e"] { queue.receive(alert(id), enabled: true, available: true) }
        precondition(queue.pending.map { $0.alert.id } == ["c", "d", "e"])
        queue.receive(alert("off"), enabled: false, available: true)
        queue.receive(alert("hidden"), enabled: true, available: false)
        precondition(queue.pending.count == 3)
        queue.advance(now: start, blocked: false, hovered: false, available: false)
        precondition(queue.current == nil && queue.pending.isEmpty)
        queue.receive(alert("new"), enabled: true, available: true)
        queue.advance(now: start, blocked: false, hovered: false, available: true, recovery: false)
        precondition(queue.current == nil && queue.pending.isEmpty)
        queue.receive(alert("close"), enabled: true, available: true)
        queue.advance(now: start, blocked: false, hovered: false, available: true)
        queue.dismiss()
        queue.receive(alert("close", title: "关闭后的确认"), enabled: true, available: true)
        precondition(queue.current == nil && queue.pending.isEmpty)
        queue.receive(alert("switch"), enabled: true, available: true)
        queue.advance(now: start, blocked: false, hovered: false, available: true)
        queue.advance(now: start.addingTimeInterval(1), blocked: false, hovered: false, available: true, recovery: false)
        precondition(queue.current == nil)
        // Alert display is an overlay: it never sends synthetic lifecycle events.
        let lifecycle = ActivityIslandLifecycle()
        let before = lifecycle
        queue.receive(alert("idle"), enabled: true, available: true)
        queue.advance(now: start, blocked: false, hovered: false, available: true)
        queue.advance(now: start.addingTimeInterval(8), blocked: false, hovered: false, available: true)
        precondition(queue.current == nil && lifecycle == before)
        precondition(lifecycle.presentation == .compact && lifecycle.expansion == .none)
        var celebration = ActivityIslandLifecycle()
        _ = celebration.handle(.activityEnded, now: start)
        func blocked(_ now: Date, active: Bool = false, pending: Bool = false) -> Bool {
            IslandAlertCompletionGate.blocks(lifecycle: celebration, confettiActive: active, pendingBurst: pending, now: now)
        }
        var celebratingQueue = IslandAlertQueue()
        celebratingQueue.receive(alert("completion"), enabled: true, available: true)
        celebratingQueue.advance(now: start, blocked: blocked(start), hovered: false, available: true)
        precondition(celebratingQueue.current == nil)
        _ = celebration.handle(.expandedHoldElapsed, now: start.addingTimeInterval(3))
        precondition(blocked(start.addingTimeInterval(3), active: true))
        precondition(blocked(start.addingTimeInterval(3), pending: true))
        celebratingQueue.advance(now: start.addingTimeInterval(4), blocked: blocked(start.addingTimeInterval(4)), hovered: false, available: true)
        precondition(celebratingQueue.current?.remaining == 8)
        celebratingQueue.advance(now: start.addingTimeInterval(6), blocked: false, hovered: false, available: true)
        let remaining = celebratingQueue.current?.remaining
        for id in ["waiting-1", "waiting-2", "waiting-3"] {
            celebratingQueue.receive(alert(id), enabled: true, available: true)
        }
        _ = celebration.handle(.activityEnded, now: start.addingTimeInterval(6))
        celebratingQueue.advance(now: start.addingTimeInterval(6), blocked: blocked(start.addingTimeInterval(6)), hovered: false, available: true)
        precondition(celebratingQueue.current == nil && celebratingQueue.pending.first?.remaining == remaining)
        precondition(celebratingQueue.pending.map { $0.alert.id } == ["completion", "waiting-2", "waiting-3"])
        _ = celebration.handle(.expandedHoldElapsed, now: start.addingTimeInterval(9))
        celebratingQueue.advance(now: start.addingTimeInterval(10), blocked: blocked(start.addingTimeInterval(10)), hovered: false, available: true)
        precondition(celebratingQueue.current?.remaining == remaining)
        print("IslandAlertTests passed: queue, updates, capacity, suspension, hover, switches, hidden, idle")
    }
}
