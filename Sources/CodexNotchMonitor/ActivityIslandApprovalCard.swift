import SwiftUI

struct IslandApprovalContent {
    struct Action: Identifiable { let id: String; let title: String; var destructive = false }
    struct Question: Identifiable {
        let id: String
        let title: String
        let options: [String]
        var allowsText = false
        var multiSelect = false
        var descriptions: [String: String] = [:]
        func validatedAnswer(_ value: String) -> String? {
            if options.contains(value) { return value }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return allowsText && !text.isEmpty && text.count <= 4_000 && text.utf8.count <= 65_536 ? text : nil
        }
    }
    let id: String
    let provider: String
    let title: String
    var summary: String
    var command = false
    var actions: [Action] = []
    var questions: [Question] = []
    var deadline: Date?
    var message: String?
    var fallbackTitle = "在 Codex 中处理"
    var submit: ((String, [String: String]) async -> String)?
    var fallback: (() -> Void)?
    var details: (() -> Void)?
    var draft: IslandAnswerDraft?
    var hasInlineControls: Bool { submit != nil && (!actions.isEmpty || !questions.isEmpty) }
    var guardIdentity: String {
        id + summary + actions.map(\.id).joined(separator: "|")
            + questions.map { question in
                question.id + question.title + String(question.allowsText) + String(question.multiSelect)
                    + question.options.map { $0 + (question.descriptions[$0] ?? "") }.joined(separator: "|")
            }.joined(separator: "|")
    }
    func presentation(privacy: Bool) -> Self {
        guard privacy else { return self }
        var copy = self
        copy.summary = "有待处理请求"; copy.actions = []; copy.questions = []
        copy.submit = nil; copy.details = nil
        return copy
    }
}

// Owned by the island model, keyed by the request nonce; never persisted.
final class IslandAnswerDraft: ObservableObject {
    @Published private(set) var options: [String: String] = [:]
    @Published private(set) var texts: [String: String] = [:]
    @Published private(set) var selections: [String: [String]] = [:]
    @Published var focusedQuestion: String? { didSet { onInteraction?() } }
    var onInteraction: (() -> Void)?
    var isInteracting: Bool {
        focusedQuestion != nil || texts.values.contains { !$0.isEmpty } || selections.values.contains { !$0.isEmpty }
    }
    var answers: [String: String] {
        options.merging(selections.mapValues { $0.joined(separator: ", ") }) { _, multiple in multiple }
            .merging(texts.filter { !$0.value.isEmpty }) { _, text in text }
    }
    func toggle(_ option: String, for id: String, orderedOptions: [String]) {
        texts[id] = nil; options[id] = nil
        var selected = Set(selections[id] ?? [])
        if !selected.insert(option).inserted { selected.remove(option) }
        selections[id] = orderedOptions.filter { selected.contains($0) }
        onInteraction?()
    }
    func isSelected(_ option: String, for id: String) -> Bool {
        options[id] == option || selections[id]?.contains(option) == true
    }
    func select(_ option: String, for id: String) {
        selections[id] = nil; texts[id] = nil; options[id] = option; onInteraction?()
    }
    func type(_ text: String, for id: String) {
        selections[id] = nil; options[id] = nil; texts[id] = text; onInteraction?()
    }
}

struct IslandApprovalInteraction {
    var appearedAt = Date()
    var submitted = false
    func disabled(now: Date, deadline: Date?, message: String?) -> Bool {
        submitted || message != nil || now.timeIntervalSince(appearedAt) < 0.6 || deadline.map { now >= $0 } == true
    }
}

enum IslandApprovalActionKind: Equatable {
    case primary, secondary, danger, fallback
    static func classify(_ id: String) -> Self {
        switch id {
        case "accept", "once", "turn", "answers": return .primary
        case "acceptForSession", "session": return .secondary
        case "decline", "deny": return .danger
        default: return .fallback
        }
    }
    var foreground: Color {
        switch self {
        case .primary: return FloatingSurfaceTheme.darkSurface
        case .secondary: return FloatingSurfaceTheme.primary()
        case .danger: return FloatingSurfaceTheme.danger
        case .fallback: return FloatingSurfaceTheme.secondary()
        }
    }
    var background: Color {
        switch self {
        case .primary: return FloatingSurfaceTheme.accent()
        case .secondary: return FloatingSurfaceTheme.chipFill()
        case .danger: return FloatingSurfaceTheme.danger.opacity(0.15)
        case .fallback: return .clear
        }
    }
}

// Intrinsic button sizes, with wrapping and a trailing detail link on the final line.
struct IslandApprovalActionFlow: Layout {
    var trailingLast = false
    static let spacing: CGFloat = 8
    static func arrangement(sizes: [CGSize], width: CGFloat, trailingLast: Bool = false) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        if trailingLast, let last = frames.last { frames[frames.count - 1].origin.x = max(last.minX, width - last.width) }
        return (frames, frames.isEmpty ? 0 : y + rowHeight)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? sizes.reduce(0) { $0 + $1.width + Self.spacing }
        return CGSize(width: width, height: Self.arrangement(sizes: sizes, width: width).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = Self.arrangement(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, width: bounds.width, trailingLast: trailingLast)
        for (view, frame) in zip(subviews, result.frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(frame.size))
        }
    }
}

private struct IslandApprovalCardHeightKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.height > 0 { value = next }
    }
}
private struct IslandApprovalQuestionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

enum IslandApprovalQuestionViewport {
    static let maximumHeight: CGFloat = 200
    static func height(for contentHeight: CGFloat) -> CGFloat { min(maximumHeight, max(0, contentHeight)) }
}

struct ActivityIslandApprovalCard: View {
    let content: IslandApprovalContent
    var privacy = false
    var onHeightChange: ((CGFloat) -> Void)?
    @State private var interaction = IslandApprovalInteraction()
    @StateObject private var draft: IslandAnswerDraft
    @State private var result: String?
    @State private var questionHeight: CGFloat = IslandApprovalQuestionViewport.maximumHeight
    @FocusState private var optionFocus: String?
    init(content: IslandApprovalContent, privacy: Bool = false, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.content = content; self.privacy = privacy; self.onHeightChange = onHeightChange
        self._draft = StateObject(wrappedValue: content.draft ?? IslandAnswerDraft())
    }
    private var allAnswered: Bool {
        content.questions.allSatisfy { $0.validatedAnswer(draft.answers[$0.id] ?? "") != nil }
    }
    private var display: IslandApprovalContent { content.presentation(privacy: privacy) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { clock in
            let disabled = interaction.disabled(now: clock.date, deadline: content.deadline, message: content.message ?? result)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    if interaction.submitted && result == nil { ProgressView().controlSize(.small) }
                    if content.provider == "Claude Code" {
                        ClaudeMarkShape().fill(Color(red: 0.851, green: 0.467, blue: 0.341)).frame(width: 15, height: 15)
                    } else if let icon = ActivityIslandPreviewAssets.codexIcon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 15, height: 15)
                    }
                    Text(content.title).font(FloatingSurfaceTypography.control)
                    Spacer()
                    if let deadline = content.deadline {
                        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(clock.date))))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                            .foregroundStyle(seconds <= 30 ? Color.orange : FloatingSurfaceTheme.secondary())
                            .accessibilityLabel("剩余 \(seconds) 秒")
                    }
                }
                if privacy {
                    Text("有待处理请求").font(FloatingSurfaceTypography.body)
                    pill(content.fallbackTitle, kind: .fallback) { handoff() }
                        .disabled(disabled || content.fallback == nil)
                } else {
                    if !content.summary.isEmpty {
                        Text(content.summary).font(content.command ? .system(size: 11, design: .monospaced) : FloatingSurfaceTypography.body)
                            .lineLimit(content.command ? 3 : nil).help(content.summary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !content.questions.isEmpty {
                        ScrollViewReader { scroll in
                        ScrollView {
                            questionList(disabled: disabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(key: IslandApprovalQuestionHeightKey.self, value: proxy.size.height)
                                })
                        }
                        .frame(height: IslandApprovalQuestionViewport.height(for: questionHeight)).clipped()
                        .onPreferenceChange(IslandApprovalQuestionHeightKey.self) { height in
                            if height.isFinite, height > 0, abs(questionHeight - height) > 0.5 { questionHeight = height }
                        }
                        .onChange(of: draft.focusedQuestion) { id in
                            if let id { scroll.scrollTo(id, anchor: .top) }
                        }
                        .onChange(of: optionFocus) { id in
                            if let question = content.questions.first(where: { q in q.options.contains { q.id + "/" + $0 == id } }) {
                                scroll.scrollTo(question.id, anchor: .top)
                            }
                        }
                        }
                    }
                    if let message = content.message ?? result {
                        Text(message).font(FloatingSurfaceTypography.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    IslandApprovalActionFlow(trailingLast: content.details != nil) {
                        ForEach(display.actions) { action in
                            pill(action.title, kind: .classify(action.id)) { send(action.id) }
                                .disabled(disabled).accessibilityLabel(action.title + content.title)
                        }
                        if !content.questions.isEmpty {
                            pill("提交回答", kind: .primary) { send("answers") }
                                .disabled(disabled || !allAnswered)
                                .accessibilityLabel("提交所有问题的回答")
                        }
                        if content.provider == "Claude Code" || (content.actions.isEmpty && content.questions.isEmpty) {
                            pill(content.fallbackTitle, kind: .fallback) { handoff() }
                                .disabled(disabled || content.fallback == nil)
                        }
                        if let details = content.details {
                            Button(action: details) {
                                HStack(spacing: 4) { Text(content.provider == "Codex" && (result != nil || content.message != nil) ? "在 Codex 中查看" : "查看详情"); Image(systemName: "chevron.right").font(.system(size: 9)) }
                                    .frame(height: 28).fixedSize()
                            }
                            .foregroundStyle(FloatingSurfaceTheme.secondary())
                            .disabled(clock.date.timeIntervalSince(interaction.appearedAt) < 0.6 || (interaction.submitted && result == nil))
                            .accessibilityLabel("查看" + content.provider + "请求详情")
                        }
                    }.font(FloatingSurfaceTypography.captionMedium)
                }
            }
            .buttonStyle(FloatingSurfaceButtonStyle())
            .padding(12).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(FloatingSurfaceTheme.primary())
            .islandGlass(RoundedRectangle(cornerRadius: 14), tint: .black.opacity(0.42), solidTint: Color(white: 0.055))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(privacy ? "有待处理请求" : content.provider + "，" + content.title + "，" + content.summary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in Color.clear.preference(key: IslandApprovalCardHeightKey.self, value: proxy.size) })
        .onPreferenceChange(IslandApprovalCardHeightKey.self) { size in
            guard size.height.isFinite, size.height > 0 else { return }
            onHeightChange?(ceil(size.height))
        }
        .onAppear { interaction.appearedAt = Date() }
        .onDisappear { draft.focusedQuestion = nil }
    }
    private func pill(_ title: String, kind: IslandApprovalActionKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(FloatingSurfaceTypography.captionMedium)
                .padding(.horizontal, 12).frame(height: 28).fixedSize()
                .foregroundStyle(kind.foreground)
                .background(kind.background, in: Capsule())
                .overlay(Capsule().strokeBorder(kind == .fallback ? FloatingSurfaceTheme.outline() : .clear, lineWidth: 0.5))
                .contentShape(Capsule())
        }
    }
    private func questionList(disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(content.questions) { question in
                Text(question.title).font(FloatingSurfaceTypography.body).fixedSize(horizontal: false, vertical: true).id(question.id)
                if question.multiSelect { Text("可多选").font(FloatingSurfaceTypography.captionMedium).foregroundStyle(FloatingSurfaceTheme.secondary()) }
                ForEach(question.options, id: \.self) { option in
                    let selected = draft.isSelected(option, for: question.id)
                    Button {
                        if question.multiSelect { draft.toggle(option, for: question.id, orderedOptions: question.options) }
                        else { draft.select(option, for: question.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: question.multiSelect ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option)
                                if let detail = question.descriptions[option], !detail.isEmpty {
                                    Text(detail).font(FloatingSurfaceTypography.captionMedium).foregroundStyle(FloatingSurfaceTheme.secondary())
                                }
                            }.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(FloatingSurfaceTypography.body).frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(selected ? FloatingSurfaceTheme.accent().opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? FloatingSurfaceTheme.accent() : FloatingSurfaceTheme.outline(), lineWidth: 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }.disabled(disabled).accessibilityLabel(question.title + "，" + option)
                        .accessibilityValue(selected ? "已选择" : "未选择")
                        .focused($optionFocus, equals: question.id + "/" + option)
                }
                if question.allowsText {
                    IslandAnswerTextField(text: Binding(get: { draft.texts[question.id] ?? "" },
                        set: { draft.type($0, for: question.id) }),
                        placeholder: question.options.isEmpty ? "输入回答…" : "其他…",
                        enabled: !disabled, focused: draft.focusedQuestion == question.id,
                        onFocus: { focused in
                            if focused { draft.focusedQuestion = question.id }
                            else if draft.focusedQuestion == question.id { draft.focusedQuestion = nil }
                        }, onReturn: {
                            if allAnswered { send("answers") }
                            else if let next = content.questions.first(where: {
                                $0.validatedAnswer(draft.answers[$0.id] ?? "") == nil
                            }) {
                                draft.focusedQuestion = next.allowsText ? next.id : nil
                                if !next.allowsText, let option = next.options.first { optionFocus = next.id + "/" + option }
                            }
                        })
                        .accessibilityLabel(question.title)
                }
            }
        }
    }
    private func handoff() {
        guard !interaction.disabled(now: Date(), deadline: content.deadline, message: content.message ?? result) else { return }
        interaction.submitted = true; content.fallback?()
    }
    private func send(_ action: String) {
        guard !privacy, !interaction.disabled(now: Date(), deadline: content.deadline, message: content.message ?? result), let submit = display.submit else { return }
        interaction.submitted = true
        Task { result = await submit(action, draft.answers) }
    }
}

// NSTextView supplies marked-text handling and explicit Return/Shift-Return semantics on macOS 13.
// The SwiftUI wrapper retains the card's typography and a one-to-four-line viewport.
private struct IslandAnswerTextField: View {
    @Binding var text: String
    let placeholder: String
    let enabled: Bool
    let focused: Bool
    let onFocus: (Bool) -> Void
    let onReturn: () -> Void
    @State private var height: CGFloat = 24
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty { Text(placeholder).font(FloatingSurfaceTypography.body)
                .foregroundStyle(FloatingSurfaceTheme.secondary()).padding(.horizontal, 6).padding(.top, 4)
                .allowsHitTesting(false) }
            IslandAnswerEditor(text: $text, height: $height, enabled: enabled, focused: focused,
                onFocus: onFocus, onReturn: onReturn)
        }
        .frame(height: height).padding(4)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
            focused ? FloatingSurfaceTheme.accent() : FloatingSurfaceTheme.outline(), lineWidth: focused ? 1.5 : 0.5))
    }
}

struct IslandAnswerEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let enabled: Bool
    let focused: Bool
    let onFocus: (Bool) -> Void
    let onReturn: () -> Void
    static func canSynchronize(markedText: Bool) -> Bool { !markedText }
    static func shouldActivate(userClick: Bool, enabled: Bool) -> Bool { userClick && enabled }
    static func shouldRestore(hasFocus: Bool, appIsActive: Bool, previousAppRunning: Bool) -> Bool {
        !hasFocus && appIsActive && previousAppRunning
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = Editor()
        editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 12)
        editor.textColor = NSColor(FloatingSurfaceTheme.primary())
        editor.insertionPointColor = NSColor(FloatingSurfaceTheme.accent())
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 1, height: 4)
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        context.coordinator.parent = self
        editor.onFocus = onFocus; editor.onReturn = onReturn
        editor.isEditable = enabled; editor.isSelectable = enabled
        if Self.canSynchronize(markedText: editor.hasMarkedText()) {
            if editor.string != text { editor.string = text }
            context.coordinator.measure(editor)
        }
        // Only a user click or explicit Return navigation may request keyboard focus.
        if focused && enabled && editor.window?.firstResponder !== editor { editor.window?.makeFirstResponder(editor) }
        if !enabled && editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? Editor else { return }
        if editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) }
        editor.restorePreviousAppWhenUnfocused()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IslandAnswerEditor
        init(_ parent: IslandAnswerEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? Editor, !editor.hasMarkedText() else { return }
            parent.text = editor.string; measure(editor)
        }
        func measure(_ editor: NSTextView) {
            guard !editor.hasMarkedText(), let container = editor.textContainer, let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            let lineHeight = layout.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: 12))
            let height = ceil(min(lineHeight * 4 + 8, max(lineHeight + 8, layout.usedRect(for: container).height + 8)))
            if parent.height != height { DispatchQueue.main.async { [weak self, weak editor] in
                guard let editor, !editor.hasMarkedText() else { return }
                self?.parent.height = height
            } }
        }
    }
    final class Editor: NSTextView {
        var onFocus: ((Bool) -> Void)?
        var onReturn: (() -> Void)?
        private static var previousApp: NSRunningApplication?
        private var resignObserver: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
            if let window {
                resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                    object: window, queue: .main) { [weak self] _ in
                        self?.onFocus?(false)
                        self?.restorePreviousAppWhenUnfocused()
                    }
            }
        }
        deinit { if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) } }
        func restorePreviousAppWhenUnfocused() {
            // Defer so Return navigation between editors keeps the same activation lease.
            DispatchQueue.main.async {
                let hasFocus = NSApp.keyWindow?.firstResponder is Editor
                guard !hasFocus else { return }
                let previous = Self.previousApp
                Self.previousApp = nil
                if IslandAnswerEditor.shouldRestore(hasFocus: hasFocus, appIsActive: NSApp.isActive,
                    previousAppRunning: previous.map { !$0.isTerminated } ?? false) {
                    previous?.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        static func submitsReturn(keyCode: UInt16, shift: Bool, markedText: Bool) -> Bool {
            (keyCode == 36 || keyCode == 76) && !shift && !markedText
        }
        override func mouseDown(with event: NSEvent) {
            if IslandAnswerEditor.shouldActivate(userClick: true, enabled: isEditable) {
                if let front = NSWorkspace.shared.frontmostApplication,
                   front.processIdentifier != ProcessInfo.processInfo.processIdentifier { Self.previousApp = front }
                NSApp.activate(ignoringOtherApps: true)
                window?.makeKey(); window?.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
        }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocus?(true) }; return accepted
        }
        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted { onFocus?(false); restorePreviousAppWhenUnfocused() }; return accepted
        }
        override func keyDown(with event: NSEvent) {
            if Self.submitsReturn(keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift), markedText: hasMarkedText()) {
                onReturn?(); return
            }
            super.keyDown(with: event)
        }
    }
}
