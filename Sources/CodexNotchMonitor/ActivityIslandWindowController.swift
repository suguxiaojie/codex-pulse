import AppKit
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class ActivityIslandWindowController: NSObject {
    private let store: MonitorStore
    private let model = ActivityIslandViewModel()
    private var presenter: ActivityIslandPanelPresenter!
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var lifecycle = ActivityIslandLifecycle()
    private var preferences = ActivityIslandPreferences.load()
    private let collapseTimer = ActivityIslandCollapseTimer()
    private var hasObservedSessions = false
    private let startupAt = Date()
    private var terminalIdentity: String?
    private var compactReceiptClose: DispatchWorkItem?
    private var compactStatisticTick: DispatchWorkItem?
    var onOpenSettings: (() -> Void)?

    init(store: MonitorStore) {
        self.store = store
        super.init()
        presenter = ActivityIslandPanelPresenter(model: model)
        presenter.onHoverChanged = { [weak self] inside in
            guard let self else { return }
            self.handle(inside ? .pointerEntered : .pointerExited)
            self.rescheduleTransitions()
        }
        presenter.onDismissOutside = { [weak self] in
            guard let self, !self.model.isPinned, !self.model.resetConfirmationPresented, !self.model.resetBusy else { return }
            self.handle(.collapseRequested); self.rescheduleTransitions()
        }
        presenter.onNeedsRefresh = { [weak self] in self?.refresh(animated: false) }
        model.onExpand = { [weak self] in
            self?.handle(.expandRequested)
            self?.rescheduleTransitions()
        }
        model.onCollapse = { [weak self] in
            guard let self else { return }
            self.presenter.suppressHover()
            self.model.isPinned = false
            self.handle(.collapseRequested)
            self.rescheduleTransitions()
        }
        model.onInteraction = { [weak self] in self?.rescheduleTransitions() }
        model.onPin = { [weak self] in
            guard let self else { return }
            self.model.isPinned.toggle()
            if self.model.isPinned { self.handle(.pinRequested) }
            else { self.presenter.suppressHover(); self.handle(.collapseRequested) }
            self.rescheduleTransitions()
        }
        model.onSelect = { [weak self] id in
            guard let self, let row = self.model.sessions.first(where: { $0.id == id }) else { return }
            self.model.focusedSessionID = id
            self.model.snapshot = self.snapshot(for: row, rows: self.model.sessions)
        }
        model.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        model.onRefresh = { [weak self] in
            guard let self else { return }
            if self.model.showsUsagePage { self.store.refreshQuota(); self.store.refreshCost() }
            else { self.store.refreshSessionActivity() }
        }
        model.onOpenUsage = { [weak self] in
            guard let self else { return }
            self.model.showsUsagePage = true
            self.handle(.expandRequested); self.rescheduleTransitions()
        }
        model.onBackToTasks = { [weak self] in
            guard let self else { return }
            self.model.showsUsagePage = false
            self.handle(.expandRequested); self.rescheduleTransitions()
        }
        model.onConsumeReset = { [weak self] fingerprint, credits in
            guard let self else { return }
            guard self.store.observedAccount?.fingerprint == fingerprint,
                  self.store.quotaResetCredits == credits,
                  IslandResetActionPolicy.canRequest(credits: credits, quota: self.store.quotaState,
                      busy: self.store.isConsumingQuotaResetCredit, privacy: self.model.privacyMode, fingerprint: fingerprint) else {
                self.model.resetMessage = "账号或额度数据已变化，请刷新后重新确认。"
                return
            }
            self.store.consumeQuotaResetCredit(expectedAccountFingerprint: fingerprint)
        }
        store.$isConsumingQuotaResetCredit.sink { [weak self] in self?.model.resetBusy = $0 }.store(in: &cancellables)
        store.$quotaResetOperationMessage.sink { [weak self] in self?.model.resetMessage = $0 }.store(in: &cancellables)
        store.$observedAccount.sink { [weak self] in self?.model.resetAccountFingerprint = $0?.fingerprint }.store(in: &cancellables)
        model.$resetDetailVisible.dropFirst().removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(animated: true) }.store(in: &cancellables)
        model.$resetConfirmationPresented.combineLatest(model.$resetBusy).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rescheduleTransitions() }.store(in: &cancellables)
        model.onUsageHeightChange = { [weak self] height in
            guard let self, height.isFinite, abs(self.model.usagePageHeight - height) > 0.5 else { return }
            self.model.usagePageHeight = height
            if self.model.showsUsagePage { self.refresh(animated: true) }
        }
        store.$costSnapshot.sink { [weak self] in self?.model.usageCost = $0 }.store(in: &cancellables)
        store.$accountUsage.sink { [weak self] in self?.model.accountUsage = $0 }.store(in: &cancellables)
        store.$quotaResetCredits.sink { [weak self] in self?.model.resetCredits = $0 }.store(in: &cancellables)
        store.$activitySessions.removeDuplicates().sink { [weak self] in self?.consume($0) }
            .store(in: &cancellables)
        store.$quotaState.removeDuplicates().sink { [weak self] in self?.model.quotaState = $0 }
            .store(in: &cancellables)
        store.$turnTokenUsages.removeDuplicates().sink { [weak self] usages in
            guard let self else { return }
            if var snapshot = self.model.snapshot, let id = snapshot.sessionID,
               let usage = ActivitySessionSnapshot.matchingUsage(usages, sessionID: id, turnID: snapshot.turnID) {
                snapshot.turnTokenUsage = usage; self.model.snapshot = snapshot
            }
        }.store(in: &cancellables)
        for name in [NSApplication.didChangeScreenParametersNotification, .glancePresentationDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(animated: false) }
            })
        }
        Publishers.Merge(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification),
                         NotificationCenter.default.publisher(for: .activityIslandPreferencesDidChange))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.reloadPreferences() }
            .store(in: &cancellables)
        applyAppearance()
    }
    deinit {
        compactReceiptClose?.cancel(); compactStatisticTick?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
    private func applyAppearance() {
        model.material = preferences.material
        model.glassDegree = preferences.glassDegree
        model.progressEffect = preferences.progressEffect
        model.privacyMode = preferences.privacyMode
        model.floatingUsageEnabled = preferences.floatingUsageEnabled
        model.usageCapsuleTone = preferences.usageCapsuleTone
    }
    private func reloadPreferences() {
        let previous = preferences
        let updated = ActivityIslandPreferences.load()
        guard updated != previous else { return }
        preferences = updated; applyAppearance()
        if !updated.automaticPopup && previous.automaticPopup && lifecycle.expansion == .automatic {
            handle(.collapseRequested)
        }
        if updated.expandedHold != previous.expandedHold || updated.automaticPopup != previous.automaticPopup {
            rescheduleTransitions()
        }
        refresh(animated: true)
    }
    private func consume(_ sessions: [ActivitySessionSnapshot]) {
        let previous = model.sessions
        let baseline = !hasObservedSessions && !sessions.isEmpty
            && !sessions.contains { $0.startedAt.map { $0 >= startupAt } == true }
        if !sessions.isEmpty { hasObservedSessions = true }
        let newlyCompleted = sessions.filter({ row in row.phase == .completed && previous.contains {
            $0.id == row.id && $0.turnID == row.turnID && $0.phase.isActive
        } }).max(by: { $0.updatedAt < $1.updatedAt })
        if let completed = newlyCompleted {
            model.completionBurstSerial += 1
            compactReceiptClose?.cancel(); compactReceiptClose = nil
            compactStatisticTick?.cancel(); compactStatisticTick = nil
            model.compactReceipt = completed; model.showsCompletedStatistic = true
        }
        let live = sessions.filter { $0.phase.isActive }
        let previousAttention = lifecycle.requiresAttention
        let newAttention = live.first { row in row.phase == .waitingApproval && !previous.contains { $0.id == row.id && $0.turnID == row.turnID && $0.phase == .waitingApproval } }
        if let focus = newAttention ?? live.first(where: { $0.id == model.focusedSessionID }) ?? live.first(where: { $0.phase == .waitingApproval }) ?? live.first {
            model.sessions = sessions
            model.focusedSessionID = focus.id
            model.snapshot = snapshot(for: focus, rows: sessions)
            terminalIdentity = nil
            let newTurn = live.contains { row in !previous.contains { $0.id == row.id && $0.turnID == row.turnID && $0.phase.isActive } }
            let newApproval = live.contains { row in row.phase == .waitingApproval
                && !previous.contains { $0.id == row.id && $0.turnID == row.turnID && $0.phase == .waitingApproval } }
            let attention = live.contains { $0.phase == .waitingApproval }
            if baseline {
                handle(.baseline(requiresAttention: attention)); rescheduleTransitions()
            } else if newTurn || newApproval || newlyCompleted != nil || lifecycle.presentation == .hidden || lifecycle.isCompletion {
                handle(.activityChanged(requiresAttention: attention)); rescheduleTransitions()
            } else {
                handle(.contentUpdated(requiresAttention: attention))
                if previousAttention && !attention { rescheduleTransitions() }
            }
        } else if let ended = sessions.filter({ $0.endReason != nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
            model.sessions = sessions
            model.focusedSessionID = ended.id
            model.snapshot = snapshot(for: ended, rows: sessions)
            let identity = ended.sessionID + "/" + (ended.turnID ?? "")
            if terminalIdentity != identity {
                terminalIdentity = identity
                handle(.activityEnded); rescheduleTransitions()
            } else { refresh(animated: true) }
        } else if terminalIdentity != nil && (lifecycle.isInteracting || model.isPinned) {
            // Keep the final receipt until its own compact/hide deadline. The
            // data layer's per-row hold can expire while the pointer is inside.
            refresh(animated: true)
        } else {
            model.sessions = []; model.snapshot = nil
            model.focusedSessionID = nil; model.compactReceipt = nil
            model.showsCompletedStatistic = false; terminalIdentity = nil
            handle(.becameIdle); rescheduleTransitions()
        }
    }
    private func snapshot(for row: ActivitySessionSnapshot, rows: [ActivitySessionSnapshot]) -> ActivityIslandSnapshot {
        ActivityIslandSnapshot(projectID: row.projectID, projectName: row.title,
            phase: row.phase, actionText: row.actionText,
            sessionCount: rows.filter { $0.projectID == row.projectID }.count,
            projectCount: Set(rows.map(\.projectID)).count, updatedAt: row.updatedAt,
            sessionID: row.sessionID, turnID: row.turnID, turnTokenUsage: row.tokenUsage)
    }
    private func handle(_ event: ActivityIslandLifecycleEvent) {
        model.presentation = lifecycle.handle(event, automaticPopup: preferences.automaticPopup,
            now: Date(), popupDuration: preferences.expandedHold)
        if model.showsUsagePage, case .contentUpdated = event, model.presentation == .compact {
            model.presentation = lifecycle.handle(.expandRequested)
        }
        if model.presentation != .expanded { model.showsUsagePage = false }
        refresh(animated: true)
    }
    private func refresh(animated: Bool) {
        model.presentation = lifecycle.presentation
        model.reduceMotionOverride = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let screen = targetScreen() else { presenter.hide(animated: false); return }
        presenter.present(screen: screen, preferences: preferences, animated: animated)
        synchronizeCompactSignals()
    }
    // QuotaView compact signals use a three-second visible receipt and reserve
    // statistic width while alternating session/completion counts.
    private func synchronizeCompactSignals() {
        let rows = model.sessions
        let completed = rows.filter { $0.phase == .completed }.count
        if let receipt = model.compactReceipt,
           rows.contains(where: { $0.phase == .waitingApproval }) ||
           !rows.contains(where: { $0.id == receipt.id && $0.turnID == receipt.turnID && $0.phase == .completed }) ||
           !rows.contains(where: { $0.phase.isActive }) {
            model.compactReceipt = nil
            compactReceiptClose?.cancel(); compactReceiptClose = nil
        }
        guard model.presentation == .compact, model.playbackVisible else {
            compactReceiptClose?.cancel(); compactReceiptClose = nil
            compactStatisticTick?.cancel(); compactStatisticTick = nil
            return
        }
        if model.compactReceipt != nil && compactReceiptClose == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.compactReceiptClose = nil; self?.model.compactReceipt = nil
            }
            compactReceiptClose = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
        guard completed > 0 else {
            compactStatisticTick?.cancel(); compactStatisticTick = nil
            model.showsCompletedStatistic = false
            return
        }
        if compactStatisticTick == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.compactStatisticTick = nil
                guard self.model.presentation == .compact, self.model.playbackVisible else { return }
                self.model.showsCompletedStatistic.toggle(); self.synchronizeCompactSignals()
            }
            compactStatisticTick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }
    private func rescheduleTransitions() {
        collapseTimer.update(deadline: model.resetConfirmationPresented || model.resetBusy ? nil : lifecycle.collapseDeadline) { [weak self] in
            guard let self else { return }
            self.handle(.expandedHoldElapsed)
            self.consume(self.store.activitySessions)
            self.rescheduleTransitions()
        }
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
