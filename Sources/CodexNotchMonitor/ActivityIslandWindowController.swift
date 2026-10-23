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
    private let focusHandoffTimer = ActivityIslandCollapseTimer()
    private var alertQueue = IslandAlertQueue()
    private var lastCompletionSoundAt: Date?
    private var hasObservedSessions = false
    private let startupAt = Date()
    private var terminalIdentity: String?
    private var manualFocusID: String?
    private var compactReceiptClose: DispatchWorkItem?
    private var compactStatisticTick: DispatchWorkItem?
    var onOpenSettings: (() -> Void)?

    init(store: MonitorStore) {
        self.store = store
        super.init()
        presenter = ActivityIslandPanelPresenter(model: model)
        presenter.onHoverChanged = { [weak self] inside in
            guard let self else { return }
            if self.model.alert != nil {
                self.updateAlerts()
                return
            }
            self.handle(inside ? .pointerEntered : .pointerExited)
            self.rescheduleTransitions()
        }
        presenter.onDismissOutside = { [weak self] in
            guard let self, !self.model.isPinned, !self.model.resetConfirmationPresented, !self.model.resetBusy,
                  !self.model.isAnswerInteracting else { return }
            if self.model.alert != nil { self.dismissAlert(); return }
            self.handle(.collapseRequested); self.rescheduleTransitions()
        }
        presenter.onNeedsRefresh = { [weak self] in self?.refresh(animated: false) }
        // @Published emits before assignment; defer until the visible flag is committed.
        model.$playbackVisible.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.updateMascotVisibility()
                if visible { self?.synchronizeCompactSignals() }
            }.store(in: &cancellables)
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
        model.approvalContent = { [weak self] row in
            guard let self else { return nil }
            var content = self.store.islandApproval(for: row)
            if content.provider == "Codex", !content.questions.isEmpty {
                let draft = self.model.answerDrafts[content.id] ?? IslandAnswerDraft()
                draft.onInteraction = { [weak self] in self?.rescheduleTransitions() }
                self.model.answerDrafts[content.id] = draft
                content.draft = draft
            }
            return content
        }
        store.$approvalRevision.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.model.discardAnswerDrafts(except: self.store.islandAnswerRequestIDs)
            if !self.model.answerDrafts.values.contains(where: { $0.focusedQuestion != nil }) {
                self.presenter.panel.makeFirstResponder(nil); self.presenter.panel.resignKey()
            }
            self.model.objectWillChange.send()
            self.rescheduleTransitions()
        }.store(in: &cancellables)
        store.claude.$requests.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.model.objectWillChange.send()
        }.store(in: &cancellables)
        model.onSelect = { [weak self] id in
            guard let self, let row = self.model.sessions.first(where: { $0.id == id }) else { return }
            self.focusHandoffTimer.update(deadline: nil, onExpire: {})
            self.manualFocusID = self.lifecycle.presentation == .expanded ? id : nil
            self.model.focusedSessionID = id
            self.model.snapshot = self.snapshot(for: row, rows: self.model.sessions)
            self.refresh(animated: true)
        }
        model.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        model.onRefresh = { [weak self] in
            guard let self else { return }
            if self.model.showsUsagePage {
                if self.model.usageProvider == .claude { self.store.claude.refreshUsage() }
                else { self.store.refreshQuota(); self.store.refreshCost() }
            }
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
            guard self.model.usageProvider == .codex, self.store.observedAccount?.fingerprint == fingerprint,
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
        store.claude.$enabled.removeDuplicates().sink { [weak self] in self?.model.updateClaudeEnabled($0) }.store(in: &cancellables)
        store.claude.$statusLineEnabled.removeDuplicates().sink { [weak self] in self?.model.claudeStatusLineEnabled = $0 }.store(in: &cancellables)
        store.claude.$usage.removeDuplicates { lhs, rhs in
            lhs?.days == rhs?.days && lhs?.lifetimeTokens == rhs?.lifetimeTokens &&
                lhs?.complete == rhs?.complete && lhs?.fileCount == rhs?.fileCount
        }.sink { [weak self] in self?.model.claudeUsage = $0 }.store(in: &cancellables)
        store.claude.$limits.removeDuplicates().sink { [weak self] in self?.model.claudeLimits = $0 }.store(in: &cancellables)
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
        NotificationCenter.default.publisher(for: CountStyle.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.model.objectWillChange.send() }
            .store(in: &cancellables)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(animated: false) }
            })
        model.onDismissAlert = { [weak self] in self?.dismissAlert() }
        model.onAlertAction = { [weak self] action, alert in
            guard let self else { return }
            self.dismissAlert()
            self.store.performIslandAlertAction(action, alert: alert)
        }
        store.islandAlerts.sink { [weak self] alert in
            guard let self else { return }
            self.alertQueue.receive(alert,
                enabled: alert.isEnabled(signals: self.store.notifyTiboSignals, recovery: self.store.notifyQuotaRecovery),
                available: self.alertsAvailable)
            self.refresh(animated: true)
        }.store(in: &cancellables)
        Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, self.model.alert != nil || !self.alertQueue.pending.isEmpty else { return }
            self.updateAlerts()
        }.store(in: &cancellables)
        applyAppearance()
    }
    deinit {
        compactReceiptClose?.cancel(); compactStatisticTick?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    private func applyAppearance() {
        model.material = preferences.material
        model.glassDegree = preferences.glassDegree
        model.progressEffect = preferences.progressEffect
        model.privacyMode = preferences.privacyMode
        model.floatingUsageEnabled = preferences.floatingUsageEnabled
        model.glassAppearance = preferences.glassAppearance
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
        focusHandoffTimer.update(deadline: nil, onExpire: {})
        model.finishReplyCues(for: sessions)
        let previous = model.sessions
        let baseline = !hasObservedSessions && !sessions.isEmpty
            && !sessions.contains { $0.startedAt.map { $0 >= startupAt } == true }
        if !sessions.isEmpty { hasObservedSessions = true }
        let newlyCompleted = ActivitySessionSnapshot.newlyCompleted(in: sessions, previous: previous)
        if let completed = newlyCompleted {
            model.completionBurstSerial += 1
            let now = Date()
            if ActivityIslandCompletionSound.shouldPlay(now: now, lastPlayedAt: lastCompletionSoundAt,
                baseline: baseline, enabled: preferences.completionSound,
                islandVisible: lifecycle.presentation != .hidden && presenter.alertsAvailable) {
                lastCompletionSoundAt = now
                ActivityIslandCompletionAudio.play(preferences.completionSoundName)
            }
            model.mascotContext.noteCompletion(completed, serial: model.completionBurstSerial,
                playable: model.playbackVisible && !model.showsUsagePage
                    && (model.presentation == .compact || model.focusedSessionID == completed.id)
                    && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            clearCompactReceipt()
            compactStatisticTick?.cancel(); compactStatisticTick = nil
            model.compactReceipt = completed; model.showsCompletedStatistic = true
        }
        let live = sessions.filter { $0.phase.isActive }
        let newTurn = live.contains { row in !previous.contains { $0.id == row.id && $0.turnID == row.turnID && $0.phase.isActive } }
        if newTurn || live.contains(where: { $0.phase == .waitingApproval }) {
            clearCompactReceipt()
        }
        let previousAttention = lifecycle.requiresAttention
        let newAttention = ActivitySessionSnapshot.newAttention(in: live, previous: previous)
        // A new request supersedes the old manual choice instead of bouncing back on refresh.
        if (newAttention != nil && !model.isAnswerInteracting) || !sessions.contains(where: { $0.id == manualFocusID }) {
            manualFocusID = nil
        }
        let editingFocus = model.isAnswerInteracting ? sessions.first {
            $0.id == model.focusedSessionID && $0.phase == .waitingApproval
        } : nil
        if let focus = editingFocus ?? ActivitySessionSnapshot.autoFocus(rows: sessions, previous: previous,
            currentFocusID: model.focusedSessionID, manualFocusID: manualFocusID) {
            model.sessions = sessions
            model.focusedSessionID = focus.id
            model.snapshot = snapshot(for: focus, rows: sessions)
            terminalIdentity = nil
            let newApproval = newAttention != nil
            let attention = live.contains { $0.phase == .waitingApproval }
            if baseline {
                handle(.baseline(requiresAttention: attention)); rescheduleTransitions()
            } else if newTurn || newApproval || newlyCompleted != nil || lifecycle.presentation == .hidden || lifecycle.isCompletion {
                handle(.activityChanged(requiresAttention: attention)); rescheduleTransitions()
            } else {
                handle(.contentUpdated(requiresAttention: attention))
                if previousAttention && !attention { rescheduleTransitions() }
            }
        } else if let ended = sessions.filter({ $0.isFreshReceipt }).max(by: { $0.updatedAt < $1.updatedAt }) {
            if ended.phase != .completed { clearCompactReceipt() }
            model.sessions = sessions
            let focus = newlyCompleted ?? sessions.first { $0.id == model.focusedSessionID } ?? ended
            model.focusedSessionID = focus.id
            model.snapshot = snapshot(for: focus, rows: sessions)
            let identity = ended.sessionID + "/" + (ended.turnID ?? "")
            if terminalIdentity != identity {
                terminalIdentity = identity
                handle(.activityEnded); rescheduleTransitions()
            } else { refresh(animated: true) }
        } else if !sessions.isEmpty {
            model.sessions = sessions
            let focus = sessions.first { $0.id == model.focusedSessionID } ?? sessions.first!
            model.focusedSessionID = focus.id
            model.snapshot = snapshot(for: focus, rows: sessions)
            clearCompactReceipt()
            model.showsCompletedStatistic = false
            // Expired receipts may be browsed, but never start a new lifecycle hold.
            refresh(animated: true)
        } else {
            model.sessions = []; model.snapshot = nil
            model.focusedSessionID = nil; clearCompactReceipt()
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
        let wasExpanded = model.presentation == .expanded
        model.presentation = lifecycle.handle(event, automaticPopup: preferences.automaticPopup,
            now: Date(), popupDuration: preferences.expandedHold)
        // Explicit collapse is allowed; background lifecycle updates cannot interrupt typing.
        if case .collapseRequested = event {} else if wasExpanded && model.isAnswerInteracting && model.presentation == .compact {
            model.presentation = lifecycle.handle(.expandRequested)
        }
        if model.showsUsagePage, case .contentUpdated = event, model.presentation == .compact {
            model.presentation = lifecycle.handle(.expandRequested)
        }
        if model.presentation != .expanded { model.showsUsagePage = false }
        refresh(animated: true)
    }
    private func refresh(animated: Bool) {
        synchronizeAlerts()
        model.presentation = model.alert == nil ? lifecycle.presentation : .expanded
        if model.presentation != .expanded || model.showsUsagePage || model.privacyMode {
            presenter.panel.makeFirstResponder(nil); presenter.panel.resignKey()
        }
        if model.presentation != .expanded, manualFocusID != nil {
            manualFocusID = nil
            if let focus = ActivitySessionSnapshot.autoFocus(rows: model.sessions, previous: model.sessions,
                currentFocusID: model.focusedSessionID, manualFocusID: nil) {
                model.focusedSessionID = focus.id
                model.snapshot = snapshot(for: focus, rows: model.sessions)
            }
        }
        model.reduceMotionOverride = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        scheduleFocusHandoff()
        guard let screen = targetScreen() else { presenter.hide(animated: false); return }
        presenter.present(screen: screen, preferences: preferences, animated: animated)
        updateMascotVisibility()
        synchronizeCompactSignals()
    }
    private var alertsAvailable: Bool {
        lifecycle.presentation != .hidden && presenter.alertsAvailable
    }
    private func synchronizeAlerts() {
        let now = Date()
        let celebrating = IslandAlertCompletionGate.blocks(lifecycle: lifecycle,
            confettiActive: presenter.surface.completionConfetti.isActive,
            pendingBurst: model.completionBurstSerial != presenter.surface.completionConfetti.lastSerial, now: now)
        alertQueue.advance(now: now,
            blocked: celebrating || lifecycle.requiresAttention || model.sessions.contains { $0.phase == .waitingApproval }
                || model.approvalRow != nil || model.isAnswerInteracting || model.resetConfirmationPresented || model.resetBusy,
            hovered: presenter.alertPointerInside, available: alertsAvailable,
            signals: store.notifyTiboSignals, recovery: store.notifyQuotaRecovery)
        if celebrating, model.alert != nil, alertQueue.current == nil, !lifecycle.requiresAttention,
           !model.sessions.contains(where: { $0.phase == .waitingApproval }),
           let completed = model.compactReceipt, model.showsCompletedStatistic {
            model.showsUsagePage = false
            model.focusedSessionID = completed.id
            model.snapshot = snapshot(for: completed, rows: model.sessions)
        }
        model.alert = alertQueue.current?.alert
        model.alertRemaining = alertQueue.current?.remaining ?? 0
    }
    private func updateAlerts() {
        let previous = model.alert
        synchronizeAlerts()
        if model.alert != previous {
            refresh(animated: true)
        }
    }
    private func dismissAlert() {
        alertQueue.dismiss()
        presenter.suppressHover()
        refresh(animated: true)
    }

    private func updateMascotVisibility() {
        let rect = model.presentation == .expanded ? model.metrics.expandedRect : model.metrics.compactRect
        let frame = presenter.panel.frame
        let globalRect = CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY,
            width: rect.width, height: rect.height)
        model.mascotContext.update(visible: model.playbackVisible && model.presentation != .hidden,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.reduceMotionOverride,
            islandRect: globalRect)
    }

    private func scheduleFocusHandoff() {
        guard manualFocusID == nil, model.sessions.contains(where: { $0.phase.isActive }),
              let completed = model.sessions.first(where: { $0.id == model.focusedSessionID }),
              completed.phase == .completed else {
            focusHandoffTimer.update(deadline: nil, onExpire: {}); return
        }
        let deadline = completed.updatedAt.addingTimeInterval(ActivityIslandFocusHandoff.duration)
        // New data replaces the pending work but retains the absolute completion deadline.
        focusHandoffTimer.update(deadline: deadline) { [weak self] in
            guard let self, self.manualFocusID == nil,
                  self.model.focusedSessionID == completed.id,
                  self.model.sessions.contains(where: { $0.id == completed.id && $0.turnID == completed.turnID
                      && $0.phase == .completed && $0.updatedAt == completed.updatedAt }),
                  let focus = self.model.handoffFocus(now: Date()) else { return }
            self.model.snapshot = self.snapshot(for: focus, rows: self.model.sessions)
            self.refresh(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }
    private func clearCompactReceipt() {
        compactReceiptClose?.cancel(); compactReceiptClose = nil
        model.compactReceipt = nil
    }
    // A receipt starts its one-shot deadline on first compact visibility.
    // Refreshes and later expansion/occlusion never extend that deadline.
    private func synchronizeCompactSignals() {
        let rows = model.sessions
        let completed = rows.filter { $0.phase == .completed }.count
        if let receipt = model.compactReceipt,
           rows.contains(where: { $0.phase == .waitingApproval }) ||
           !rows.contains(where: { $0.id == receipt.id && $0.turnID == receipt.turnID && $0.phase == .completed && !$0.isRetainedReceipt }) {
            clearCompactReceipt()
        }
        guard model.presentation == .compact, model.playbackVisible else {
            compactStatisticTick?.cancel(); compactStatisticTick = nil
            return
        }
        if let receipt = model.compactReceipt, compactReceiptClose == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self, let current = self.model.compactReceipt,
                      current.id == receipt.id, current.turnID == receipt.turnID else { return }
                self.clearCompactReceipt()
                if self.model.presentation == .compact && self.model.playbackVisible {
                    self.refresh(animated: true)
                }
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
        collapseTimer.update(deadline: model.resetConfirmationPresented || model.resetBusy || model.isAnswerInteracting ? nil : lifecycle.collapseDeadline) { [weak self] in
            guard let self, !self.model.isAnswerInteracting else { return }
            self.handle(.expandedHoldElapsed)
            self.consume(self.store.activitySessions)
            self.rescheduleTransitions()
        }
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
