import Foundation

enum ActivityIslandPresentation: Equatable { case hidden, expanded, compact }
enum ActivityIslandExpansion: Equatable { case none, automatic, manual, attention, pinned }
enum ActivityIslandLifecycleEvent: Equatable {
    case baseline(requiresAttention: Bool)
    case activityChanged(requiresAttention: Bool)
    case activityEnded
    case expandedHoldElapsed
    case contentUpdated(requiresAttention: Bool)
    case pointerEntered
    case pointerExited
    case collapseRequested
    case expandRequested
    case pinRequested
    case becameIdle
}

/// QuotaView's automatic preview deadline is independent of pointer tracking
/// and ordinary display updates. Manual hover and pinned previews have separate
/// close rules; a cold-start snapshot is a compact baseline, not a new event.
struct ActivityIslandLifecycle: Equatable {
    private(set) var presentation: ActivityIslandPresentation = .compact
    private(set) var expansion: ActivityIslandExpansion = .none
    private(set) var requiresAttention = false
    private(set) var isCompletion = false
    private(set) var isInteracting = false
    private(set) var collapseDeadline: Date?

    mutating func handle(_ event: ActivityIslandLifecycleEvent, automaticPopup: Bool = true,
                         now: Date = Date(), popupDuration: TimeInterval = 3) -> ActivityIslandPresentation {
        switch event {
        case .becameIdle:
            requiresAttention = false; isCompletion = false
            if expansion != .manual && expansion != .pinned {
                presentation = .compact; expansion = .none; collapseDeadline = nil
            }
        case let .baseline(attention):
            requiresAttention = attention
            guard expansion != .manual && expansion != .pinned else { break }
            presentation = attention && automaticPopup ? .expanded : .compact
            expansion = attention && automaticPopup ? .attention : .none
            collapseDeadline = nil
        case let .activityChanged(attention):
            isCompletion = false
            requiresAttention = attention
            if attention {
                collapseDeadline = nil
                if automaticPopup && expansion != .pinned { presentation = .expanded; expansion = .attention }
                else if presentation == .hidden { presentation = .compact }
            } else { beginAutomatic(enabled: automaticPopup, now: now, duration: popupDuration) }
        case .activityEnded:
            requiresAttention = false; isCompletion = true
            beginAutomatic(enabled: automaticPopup, now: now, duration: popupDuration)
        case .expandedHoldElapsed:
            if !requiresAttention, let deadline = collapseDeadline, now >= deadline,
               expansion == .automatic || (expansion == .manual && !isInteracting) { collapse() }
        case let .contentUpdated(attention):
            let previouslyWaiting = requiresAttention
            requiresAttention = attention
            if attention {
                collapseDeadline = nil
                if !previouslyWaiting && automaticPopup && expansion != .pinned {
                    presentation = .expanded; expansion = .attention
                }
            } else if previouslyWaiting && expansion != .pinned { collapse() }
        case .pointerEntered:
            isInteracting = true
            if presentation == .compact { presentation = .expanded; expansion = .manual; collapseDeadline = nil }
            else if expansion == .manual { collapseDeadline = nil }
            // Entering an already automatic preview does not claim it manually.
        case .pointerExited:
            isInteracting = false
            if presentation == .expanded && expansion == .manual && !requiresAttention {
                collapseDeadline = now.addingTimeInterval(0.45)
            }
        case .collapseRequested:
            isInteracting = false; collapse()
        case .expandRequested:
            if presentation != .hidden && expansion != .pinned {
                presentation = .expanded; expansion = .manual; collapseDeadline = nil
            }
        case .pinRequested:
            if presentation != .hidden { presentation = .expanded; expansion = .pinned; collapseDeadline = nil }
        }
        return presentation
    }
    private mutating func beginAutomatic(enabled: Bool, now: Date, duration: TimeInterval) {
        guard expansion != .manual && expansion != .pinned else { return }
        if enabled {
            presentation = .expanded; expansion = .automatic
            collapseDeadline = now.addingTimeInterval((duration.isFinite ? min(10, max(1, duration.rounded())) : 3))
        } else if presentation == .hidden { presentation = .compact; expansion = .none; collapseDeadline = nil }
    }
    private mutating func collapse() {
        if presentation != .hidden { presentation = .compact }
        expansion = .none; collapseDeadline = nil
    }
}

/// One production timer, keyed by the absolute deadline. Repeated state/Token
/// publications cannot move the deadline forward or create duplicate timers.
@MainActor
final class ActivityIslandCollapseTimer {
    private var work: DispatchWorkItem?
    private var action: (@MainActor () -> Void)?
    private(set) var deadline: Date?
    func update(deadline next: Date?, onExpire: @escaping @MainActor () -> Void) {
        action = onExpire
        guard next != deadline else { return }
        work?.cancel(); work = nil; deadline = next
        guard let next else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.deadline == next else { return }
                self.deadline = nil; self.work = nil
                self.action?()
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, next.timeIntervalSinceNow), execute: item)
    }
    deinit { work?.cancel() }
}
