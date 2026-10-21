import SwiftUI

struct IslandApprovalContent {
    struct Action: Identifiable { let id: String; let title: String; var destructive = false }
    struct Question: Identifiable { let id: String; let title: String; let options: [String] }
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
    var hasInlineControls: Bool { submit != nil && (!actions.isEmpty || !questions.isEmpty) }
    var guardIdentity: String {
        id + summary + actions.map(\.id).joined(separator: "|")
            + questions.map { $0.id + $0.title + $0.options.joined(separator: "|") }.joined(separator: "|")
    }
    func presentation(privacy: Bool) -> Self {
        guard privacy else { return self }
        var copy = self
        copy.summary = "有待处理请求"; copy.actions = []; copy.questions = []
        copy.submit = nil; copy.details = nil
        return copy
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
    @State private var answers: [String: String] = [:]
    @State private var result: String?
    @State private var questionHeight: CGFloat = IslandApprovalQuestionViewport.maximumHeight
    private var display: IslandApprovalContent { content.presentation(privacy: privacy) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { clock in
            let disabled = interaction.disabled(now: clock.date, deadline: content.deadline, message: content.message ?? result)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
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
                                .disabled(disabled || !content.questions.allSatisfy { answers[$0.id] != nil })
                                .accessibilityLabel("提交所有问题的回答")
                        }
                        if content.provider == "Claude Code" || (content.actions.isEmpty && content.questions.isEmpty) {
                            pill(content.fallbackTitle, kind: .fallback) { handoff() }
                                .disabled(disabled || content.fallback == nil)
                        }
                        if let details = content.details {
                            Button(action: details) {
                                HStack(spacing: 4) { Text("查看详情"); Image(systemName: "chevron.right").font(.system(size: 9)) }
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
                Text(question.title).font(FloatingSurfaceTypography.body).fixedSize(horizontal: false, vertical: true)
                ForEach(question.options, id: \.self) { option in
                    let selected = answers[question.id] == option
                    Button { answers[question.id] = option } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            Text(option).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(FloatingSurfaceTypography.body).frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(selected ? FloatingSurfaceTheme.accent().opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? FloatingSurfaceTheme.accent() : FloatingSurfaceTheme.outline(), lineWidth: 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }.disabled(disabled).accessibilityLabel(question.title + "，" + option)
                        .accessibilityValue(selected ? "已选择" : "未选择")
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
        Task { result = await submit(action, answers) }
    }
}
