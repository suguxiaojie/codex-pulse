import CryptoKit
import Foundation

enum SessionExportFormat: String, CaseIterable {
    case markdown
    case html
    case portableBundle
    case projectBundle

    var title: String {
        switch self {
        case .markdown: return "可读 Markdown（脱敏）"
        case .html: return "可读 HTML（脱敏）"
        case .portableBundle: return "可恢复备份（原始记录）"
        case .projectBundle: return "完整项目迁移包（P1）"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        case .portableBundle: return "codexmonitorbundle"
        case .projectBundle: return "codexprojectbundle"
        }
    }
}

struct SessionExportResult: Equatable {
    let outputURL: URL
    let sessionCount: Int
    let format: SessionExportFormat
}

enum SessionExportStage: String, Equatable {
    case preparing = "准备导出"
    case reading = "读取会话"
    case processing = "清理与脱敏"
    case rendering = "生成文档"
    case writing = "写入文件"
    case compressing = "生成压缩包"
    case completed = "导出完成"
}

struct SessionExportProgress: Equatable {
    let completed: Int
    let total: Int
    let currentItem: String
    let stage: SessionExportStage
    let processedBytes: Int64?
    let totalBytes: Int64?
    let fraction: Double

    init(
        completed: Int,
        total: Int,
        currentItem: String,
        stage: SessionExportStage = .preparing,
        processedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        fraction: Double? = nil
    ) {
        self.completed = completed
        self.total = total
        self.currentItem = currentItem
        self.stage = stage
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
        self.fraction = min(1, max(
            0,
            fraction ?? (total > 0 ? Double(completed) / Double(total) : 0)
        ))
    }
}

struct SessionPortableManifest: Codable, Equatable {
    static let supportedFormat = "codex-notch-session/v1"

    let format: String
    let createdAt: String
    let source: Source
    let project: Project
    let sessions: [Session]

    struct Source: Codable, Equatable {
        let application: String
        let version: String
        let platform: String
    }

    struct Project: Codable, Equatable {
        let displayName: String
        let originalPath: String
    }

    struct Session: Codable, Equatable {
        let threadID: String
        let title: String
        let archived: Bool
        let updatedAt: String
        let originalCwd: String
        let gitBranch: String?
        let ownershipAlias: String?
        let ownershipConfidence: String
        let rolloutPath: String
        let sha256: String

        enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case title
            case archived
            case updatedAt
            case originalCwd
            case gitBranch
            case ownershipAlias
            case ownershipConfidence
            case rolloutPath
            case sha256
        }
    }
}

struct SessionPortableChecksums: Codable, Equatable {
    let algorithm: String
    let files: [String: String]
}

final class SessionExportService {
    struct ExportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct ReadableEntry {
        let role: CodexTranscriptRole
        let text: String
        var phase: String?
        var images: [String]
    }

    private struct ReadableTurn {
        let question: String
        var responses: [String]
        var phases: [String?] = []
        var images: [String] = []

        var finalResponse: String? {
            if let index = phases.lastIndex(where: { $0 == "final_answer" }) { return responses[index] }
            // Legacy logs have no phase; explicit progress must never become a final reply.
            return phases.contains(where: { $0 != nil }) ? nil : responses.last
        }

        var processUpdates: [String] {
            if let index = phases.lastIndex(where: { $0 == "final_answer" }) {
                return responses.enumerated().filter { $0.offset != index }.map(\.element)
            }
            return phases.contains(where: { $0 != nil }) ? responses : Array(responses.dropLast())
        }
    }

    private let fileManager: FileManager
    private let now: () -> Date

    init(fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    func export(
        threads: [LocalThreadRecord],
        projectName: String,
        format: SessionExportFormat,
        to outputURL: URL,
        projectTransferOptions: ProjectTransferExportOptions = .defaults,
        progress: ((SessionExportProgress) -> Void)? = nil
    ) throws -> SessionExportResult {
        let userThreads = threads.filter { $0.kind == .userConversation }
        guard !userThreads.isEmpty else {
            throw ExportError(message: "没有可导出的用户会话")
        }
        progress?(SessionExportProgress(
            completed: 0,
            total: userThreads.count,
            currentItem: userThreads.count == 1 ? userThreads[0].title : "准备导出",
            stage: .preparing,
            fraction: 0
        ))

        switch format {
        case .markdown:
            let images = SessionExportImages(outputURL: outputURL, embedded: false)
            let document = try markdown(
                for: userThreads,
                projectName: projectName,
                images: images,
                progress: progress
            )
            progress?(SessionExportProgress(
                completed: userThreads.count,
                total: userThreads.count,
                currentItem: outputURL.lastPathComponent,
                stage: .writing,
                fraction: 0.96
            ))
            try images.writeAssets()
            try document.write(
                to: outputURL,
                atomically: true,
                encoding: .utf8
            )
            images.commit()
        case .html:
            let images = SessionExportImages(outputURL: outputURL, embedded: true)
            let document = try html(
                for: userThreads,
                projectName: projectName,
                images: images,
                progress: progress
            )
            progress?(SessionExportProgress(
                completed: userThreads.count,
                total: userThreads.count,
                currentItem: outputURL.lastPathComponent,
                stage: .writing,
                fraction: 0.96
            ))
            try document.write(
                to: outputURL,
                atomically: true,
                encoding: .utf8
            )
        case .portableBundle:
            try writePortableBundle(
                threads: userThreads,
                projectName: projectName,
                to: outputURL,
                progress: progress
            )
        case .projectBundle:
            return try ProjectTransferService(
                fileManager: fileManager,
                now: now,
                sessionExportService: self
            ).export(
                threads: userThreads,
                projectName: projectName,
                to: outputURL,
                options: projectTransferOptions,
                progress: progress
            )
        }
        progress?(SessionExportProgress(
            completed: userThreads.count,
            total: userThreads.count,
            currentItem: outputURL.lastPathComponent,
            stage: .completed,
            fraction: 1
        ))

        return SessionExportResult(
            outputURL: outputURL,
            sessionCount: userThreads.count,
            format: format
        )
    }

    static func safeFilenameStem(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let components = value.components(separatedBy: invalid)
        let collapsed = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((collapsed.isEmpty ? "Codex-会话" : collapsed).prefix(80))
    }

    private func markdown(
        for threads: [LocalThreadRecord],
        projectName: String,
        images: SessionExportImages,
        progress: ((SessionExportProgress) -> Void)?
    ) throws -> String {
        var sections = [
            "# Codex 会话导出",
            "",
            "<details><summary>关于此导出 · 文字已脱敏</summary>",
            "",
            "平台注入配置、运行环境、插件清单、附件临时路径和内部引用元数据已隐藏；完整原始记录请使用 `.codexmonitorbundle`。引用图片未做像素级遮盖。",
            "",
            "</details>",
            "",
            "\(Self.markdownTableCell(projectName)) · \(threads.count) 条会话 · \(Self.iso8601(now()))",
            "",
        ]

        let orderedThreads = sorted(threads)
        for (index, thread) in orderedThreads.enumerated() {
            let entries = try transcriptEntries(
                at: thread.rolloutURL,
                progress: { processed, total in
                    let byteFraction = total > 0 ? Double(processed) / Double(total) : 1
                    let overall = 0.92 * (
                        Double(index) + min(1, max(0, byteFraction)) * 0.76
                    ) / Double(orderedThreads.count)
                    progress?(SessionExportProgress(
                        completed: index,
                        total: orderedThreads.count,
                        currentItem: thread.title,
                        stage: .reading,
                        processedBytes: processed,
                        totalBytes: total,
                        fraction: overall
                    ))
                }
            )
            progress?(SessionExportProgress(
                completed: index,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .processing,
                fraction: 0.92 * (Double(index) + 0.82) / Double(orderedThreads.count)
            ))
            let readableEntries = Self.readableTranscriptEntries(entries)
            let turns = Self.conversationTurns(readableEntries)
            progress?(SessionExportProgress(
                completed: index,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .rendering,
                fraction: 0.92 * (Double(index) + 0.90) / Double(orderedThreads.count)
            ))
            let sessionAnchor = "session-\(index + 1)"
            let directoryAnchor = "\(sessionAnchor)-question-index"
            sections.append(contentsOf: [
                index == 0 ? "<a id=\"\(sessionAnchor)\"></a>\n\n## \(thread.title)" : "---\n\n<a id=\"\(sessionAnchor)\"></a>\n\n## \(thread.title)",
                "",
                "<details><summary>会话信息</summary>",
                "",
                "| 项目 | 内容 |",
                "|---|---|",
                "| 会话 ID | `\(thread.id)` |",
                "| 状态 | \(thread.isArchived ? "已归档" : "活动") |",
                "| 更新时间 | \(Self.iso8601(thread.updatedAt)) |",
                "| 用户问题 | \(turns.count) |",
                "| 可读消息 | \(readableEntries.count) |",
                "",
                "</details>",
                "",
                "<a id=\"\(directoryAnchor)\"></a>",
                "",
                "<details><summary>用户问题目录（\(turns.count) 问）</summary>",
                "",
                "### 用户问题目录",
                "",
            ])
            if turns.isEmpty {
                sections.append("_此会话没有可读的用户问题。_")
                sections.append("")
            } else {
                for (turnIndex, turn) in turns.enumerated() {
                    let title = Self.questionNavigationTitle(
                        turn.question,
                        fallbackIndex: turnIndex + 1
                    ).short
                    sections.append(
                        "\(turnIndex + 1). [\(title)](#\(sessionAnchor)-question-\(turnIndex + 1))"
                    )
                }
                sections.append("")
            }
            sections.append("</details>")
            sections.append("")
            for (turnIndex, turn) in turns.enumerated() {
                let questionNumber = turnIndex + 1
                sections.append(contentsOf: [
                    "---",
                    "",
                    "<a id=\"\(sessionAnchor)-question-\(questionNumber)\"></a>",
                    "",
                    "### 问题 \(questionNumber)",
                    "",
                    images.markup(turn.images),
                    "",
                    Self.markdownQuote(turn.question),
                    "",
                ])

                if !turn.processUpdates.isEmpty {
                    sections.append("<details><summary>Codex 过程更新（\(turn.processUpdates.count) 条）</summary>")
                    sections.append("")
                    for response in turn.processUpdates {
                        sections.append(Self.markdownQuote(Self.escapeDetailsMarkup(response)))
                        sections.append("")
                    }
                    sections.append("</details>")
                    sections.append("")
                }
                if let response = turn.finalResponse {
                    sections.append("**Codex**")
                    sections.append("")
                    sections.append(response)
                    sections.append("")
                } else {
                    sections.append("_此问题暂无最终回复。_")
                    sections.append("")
                }
                sections.append("[返回问题目录](#\(directoryAnchor))")
                sections.append("")
            }
            progress?(SessionExportProgress(
                completed: index + 1,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .rendering,
                fraction: 0.92 * Double(index + 1) / Double(orderedThreads.count)
            ))
        }
        return sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func html(
        for threads: [LocalThreadRecord],
        projectName: String,
        images: SessionExportImages,
        progress: ((SessionExportProgress) -> Void)?
    ) throws -> String {
        let orderedThreads = sorted(threads)
        var conversations = ""
        var tocItems = ""
        for (sessionIndex, thread) in orderedThreads.enumerated() {
            let entries = try transcriptEntries(
                at: thread.rolloutURL,
                progress: { processed, total in
                    let byteFraction = total > 0 ? Double(processed) / Double(total) : 1
                    let overall = 0.92 * (
                        Double(sessionIndex) + min(1, max(0, byteFraction)) * 0.76
                    ) / Double(orderedThreads.count)
                    progress?(SessionExportProgress(
                        completed: sessionIndex,
                        total: orderedThreads.count,
                        currentItem: thread.title,
                        stage: .reading,
                        processedBytes: processed,
                        totalBytes: total,
                        fraction: overall
                    ))
                }
            )
            progress?(SessionExportProgress(
                completed: sessionIndex,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .processing,
                fraction: 0.92 * (Double(sessionIndex) + 0.82) / Double(orderedThreads.count)
            ))
            let readableEntries = Self.readableTranscriptEntries(entries)
            progress?(SessionExportProgress(
                completed: sessionIndex,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .rendering,
                fraction: 0.92 * (Double(sessionIndex) + 0.90) / Double(orderedThreads.count)
            ))
            let sessionID = "session-\(sessionIndex + 1)"
            let turns = Self.conversationTurns(readableEntries)
            var questionSections = ""
            var navigationGroups = ""
            for groupStart in stride(from: 0, to: turns.count, by: 20) {
                let groupEnd = min(groupStart + 20, turns.count)
                let links = (groupStart..<groupEnd).map { turnIndex in
                    let questionNumber = turnIndex + 1
                    let questionID = "\(sessionID)-question-\(questionNumber)"
                    let title = Self.questionNavigationTitle(
                        turns[turnIndex].question,
                        fallbackIndex: questionNumber
                    )
                    return """
                    <a class="question-link" href="#\(questionID)" data-target="\(questionID)" title="\(Self.escapeHTML(title.full))"><b>\(questionNumber)</b><span>\(Self.escapeHTML(title.short))</span></a>
                    """
                }.joined(separator: "\n")
                navigationGroups += """
                <details class="question-group" \(groupStart == 0 ? "open" : "")>
                  <summary>问题 \(groupStart + 1)–\(groupEnd)</summary>
                  <div class="question-list">\(links)</div>
                </details>
                """
            }

            for (turnIndex, turn) in turns.enumerated() {
                let questionNumber = turnIndex + 1
                let questionID = "\(sessionID)-question-\(questionNumber)"
                let title = Self.questionNavigationTitle(
                    turn.question,
                    fallbackIndex: questionNumber
                )
                let processUpdates = turn.processUpdates
                let finalResponse = turn.finalResponse
                let processHTML: String
                if processUpdates.isEmpty {
                    processHTML = ""
                } else {
                    let updates = processUpdates.enumerated().map { updateIndex, response in
                        """
                        <section class="process-update">
                          <h4>过程更新 \(updateIndex + 1)</h4>
                          <div class="message-body">\(Self.markdownHTML(response))</div>
                        </section>
                        """
                    }.joined(separator: "\n")
                    processHTML = """
                    <details class="process-group">
                      <summary><span>查看过程</span><small>\(processUpdates.count) 条更新</small><svg class="disclosure-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="m9 5 7 7-7 7"/></svg></summary>
                      <div class="process-list">\(updates)</div>
                    </details>
                    """
                }
                let finalHTML = finalResponse.map {
                    """
                    <section class="final-response">
                      <h4 class="sr-only">Codex 最终回复</h4>
                      <div class="message-body">\(Self.markdownHTML($0))</div>
                    </section>
                    """
                } ?? "<div class=\"empty\">此问题暂无最终回复。</div>"
                questionSections += """
                <article class="question-section" id="\(questionID)" data-question-number="\(questionNumber)" data-question-total="\(turns.count)">
                  <header class="question-header"><span>第 \(questionNumber) 问</span><h3 class="sr-only">\(Self.escapeHTML(title.short))</h3></header>
                  \(images.markup(turn.images))
                  <section class="user-prompt">
                    <h4 class="sr-only">用户问题</h4>
                    <div class="message-body">\(Self.markdownHTML(turn.question))</div>
                  </section>
                  \(processHTML)
                  \(finalHTML)
                </article>
                """
            }
            tocItems += """
            <section class="toc-session" data-session="\(sessionID)">
              <a class="session-link" href="#\(sessionID)"><span>\(Self.escapeHTML(thread.title))</span><small>\(thread.isArchived ? "已归档" : "活动")</small></a>
              <div class="question-groups">\(navigationGroups)</div>
            </section>
            """
            conversations += """
            <section class="session" id="\(sessionID)">
              <header class="session-header">
                <div>
                  <h2>\(Self.escapeHTML(thread.title))</h2>
                  <div class="meta">\(turns.count) 个问题 · \(Self.iso8601(thread.updatedAt).prefix(10))</div>
                  <details class="session-info"><summary>会话信息</summary><code>\(Self.escapeHTML(thread.id))</code></details>
                </div>
                <span class="status \(thread.isArchived ? "archived" : "active")">\(thread.isArchived ? "已归档" : "活动")</span>
              </header>
              \(questionSections.isEmpty ? "<div class=\"empty\">此会话没有可读的用户问题。</div>" : questionSections)
            </section>
            """
            progress?(SessionExportProgress(
                completed: sessionIndex + 1,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .rendering,
                fraction: 0.92 * Double(sessionIndex + 1) / Double(orderedThreads.count)
            ))
        }

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(Self.escapeHTML(projectName)) · Codex 会话导出</title>
          <style>
            /* finesse · register=product · scope=reader-refinement · feedback-only motion */
            :root { color-scheme:dark; --bg:#181818; --nav:#141414; --surface:#222222; --code:#202020; --text:#dfdfdf; --muted:#a6a7ac; --quiet:#898b91; --line:rgba(235,238,245,.10); --hover:rgba(235,238,245,.06); --selected:rgba(235,238,245,.11); --link:#9ac2ee; --focus:#a6c7ed; --hit:#f1cd76; font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC",sans-serif; }
            * { box-sizing:border-box; }
            html,body { overflow-x:clip; }
            html { scroll-behavior:smooth; }
            body { margin:0; background:var(--bg); color:var(--text); font-size:16px; line-height:1.625; -webkit-font-smoothing:antialiased; }
            a { color:var(--link); text-decoration-thickness:1px; text-underline-offset:3px; }
            button,input { font:inherit; }
            button,a,input,summary { -webkit-tap-highlight-color:transparent; }
            button { cursor:pointer; }
            button:disabled { opacity:.35; cursor:default; }
            :focus-visible { outline:2px solid var(--focus); outline-offset:3px; }
            .layout { display:grid; grid-template-columns:244px minmax(0,736px); justify-content:center; gap:64px; width:min(1100px,calc(100% - 64px)); margin:0 auto 96px; }
            .reader { min-width:0; padding-top:54px; }
            .toc { position:sticky; top:24px; align-self:start; display:flex; flex-direction:column; max-height:calc(100dvh - 48px); margin-top:24px; background:var(--nav); border:1px solid var(--line); border-radius:16px; overflow:hidden; }
            .toc-tools { padding:18px 16px 14px; flex:none; }
            .toc-title { font-size:13px; font-weight:600; margin-bottom:14px; }
            .search { width:100%; min-width:0; border:1px solid var(--line); border-radius:9px; padding:9px 11px; color:var(--text); background:var(--hover); font-size:13px; outline:none; }
            .search:focus { border-color:var(--focus); }
            .search::placeholder { color:var(--muted); }
            .search-status { color:var(--muted); font-size:11px; min-height:20px; padding-top:8px; }
            .search-actions,.reader-actions { display:flex; align-items:center; gap:6px; margin-top:8px; }
            .search-actions button,.reader-actions button,.reader-actions a { border:0; border-radius:6px; background:transparent; color:var(--muted); font-size:11px; padding:5px 7px; white-space:nowrap; text-decoration:none; }
            .search-actions button:hover:not(:disabled),.reader-actions button:hover:not(:disabled),.reader-actions a:hover { background:var(--hover); color:var(--text); }
            .current-position { margin-top:12px; color:var(--muted); font-size:11px; font-variant-numeric:tabular-nums; }
            .toc-scroll { min-height:0; overflow:auto; padding:4px 8px 12px; border-top:1px solid var(--line); scrollbar-width:thin; scrollbar-color:var(--selected) transparent; }
            .toc-session + .toc-session { margin-top:14px; }
            .session-link { display:flex; align-items:center; justify-content:space-between; gap:8px; padding:12px 9px 7px; color:var(--text); font-size:12px; font-weight:600; text-decoration:none; }
            .session-link span { min-width:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
            .session-link small { flex:none; color:var(--quiet); font-size:10px; font-weight:400; }
            .question-group { margin-top:3px; }
            .question-group > summary { list-style:none; padding:8px 9px; font-size:11px; color:var(--quiet); cursor:pointer; }
            summary::-webkit-details-marker { display:none; }
            .question-group > summary::before { content:'›'; display:inline-block; margin-right:7px; transition:transform .18s; }
            .question-group[open] > summary::before { transform:rotate(90deg); }
            .question-link { display:flex; gap:10px; align-items:baseline; padding:9px; border-radius:7px; min-width:0; color:var(--muted); text-decoration:none; font-size:12px; line-height:1.45; transition:background .15s,color .15s; }
            .question-link b { flex:none; width:17px; color:var(--quiet); font-size:10px; font-weight:400; font-variant-numeric:tabular-nums; text-align:right; }
            .question-link span { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
            .question-link:hover { background:var(--hover); color:var(--text); }
            .question-link.active { background:var(--selected); color:var(--text); }
            .question-link.active b { color:var(--text); }
            .summary { margin-bottom:40px; }
            .summary h1 { font-size:13px; line-height:1.5; font-weight:500; color:var(--muted); margin:0 0 9px; }
            .meta { color:var(--quiet); font-size:11px; overflow-wrap:anywhere; }
            .export-note { margin-top:10px; color:var(--muted); font-size:11px; }
            .export-note summary,.session-info summary { cursor:pointer; list-style:none; }
            .export-note p { margin:8px 0 0; }
            .session { scroll-margin-top:32px; }
            .session + .session { margin-top:76px; padding-top:40px; border-top:1px solid var(--line); }
            .session-header { display:flex; justify-content:space-between; gap:18px; align-items:flex-start; margin-bottom:36px; }
            .session-header h2 { font-size:24px; line-height:1.4; font-weight:600; letter-spacing:-.025em; margin:0 0 8px; overflow-wrap:anywhere; min-width:0; }
            .session-header > div { min-width:0; }
            .status { flex:none; color:var(--muted); font-size:10px; padding:4px 0; }
            .session-info { font-size:11px; color:var(--quiet); margin-top:6px; }
            .session-info code { display:block; margin-top:6px; }
            .question-section { scroll-margin-top:32px; margin:0 0 64px; min-width:0; }
            .question-header { margin-bottom:12px; font-size:10px; color:var(--quiet); }
            .question-section.flash .question-header { color:var(--text); }
            .user-prompt { width:fit-content; max-width:77%; margin-left:auto; padding:10px 13px; border-radius:16px; background:var(--surface); }
            .final-response { padding-top:24px; }
            .message-body { min-width:0; overflow-wrap:anywhere; }
            .message-body > :first-child { margin-top:0; }
            .message-body > :last-child { margin-bottom:0; }
            .message-body p { margin:0 0 16px; }
            .message-body strong { font-weight:600; }
            .message-body h1,.message-body h2,.message-body h3,.message-body h4,.message-body h5,.message-body h6 { font-weight:600; line-height:1.45; letter-spacing:-.015em; margin:28px 0 12px; color:var(--text); }
            .message-body h1 { font-size:24px; }.message-body h2 { font-size:22px; }.message-body h3 { font-size:19px; }.message-body h4,.message-body h5,.message-body h6 { font-size:16px; }
            .message-body ul,.message-body ol { padding-left:24px; margin:12px 0 18px; }
            .message-body li { margin:7px 0; padding-left:3px; }
            .message-body li > ul,.message-body li > ol { margin:5px 0; }
            .message-body li::marker { color:var(--muted); }
            .message-body blockquote { margin:18px 0; padding:2px 0 2px 18px; border-left:2px solid var(--line); color:var(--muted); }
            .message-body hr { border:0; border-top:1px solid var(--line); margin:28px 0; }
            .process-group { margin:14px 0 0; color:var(--muted); }
            .process-group > summary { display:flex; align-items:center; width:100%; gap:8px; min-height:36px; padding:7px 0; border-bottom:1px solid var(--line); list-style:none; cursor:pointer; font-size:12px; border-radius:6px; }
            .process-group > summary:hover { color:var(--text); }
            .process-group > summary small { font-size:11px; color:var(--quiet); }
            .disclosure-icon { transition:transform .18s ease; }
            .process-group[open] .disclosure-icon { transform:rotate(90deg); }
            .process-list { margin-top:12px; padding:0 0 0 18px; border-left:1px solid var(--line); animation:process-in .18s ease-out; }
            .process-update { padding:0 0 18px; font-size:14px; line-height:1.75; }
            .process-update:last-child { padding-bottom:4px; }
            .process-update h4 { margin:0 0 7px; font-size:10px; color:var(--quiet); font-weight:500; }
            @keyframes process-in { from{opacity:0;transform:translateY(-3px)} to{opacity:1;transform:translateY(0)} }
            code { font: .88em/1.65 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; padding:2px 5px; border:1px solid var(--line); border-radius:5px; background:var(--hover); color:inherit; }
            .code-block { border:1px solid var(--line); border-radius:12px; margin:20px 0; background:var(--code); overflow:hidden; }
            .code-label { display:flex; align-items:center; justify-content:space-between; gap:12px; min-height:42px; padding:8px 14px; background:var(--hover); color:var(--muted); font-size:11px; }
            .copy-code { display:flex; align-items:center; gap:6px; border:0; border-radius:5px; padding:4px 7px; color:var(--muted); background:transparent; font-size:11px; white-space:nowrap; transition:background .15s,color .15s; }
            .copy-code:hover { background:var(--hover); color:var(--text); }
            .code-block pre { margin:0; padding:18px; overflow-x:auto; white-space:pre; font:13px/1.75 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; tab-size:4; scrollbar-width:thin; scrollbar-color:var(--selected) transparent; }
            .code-block pre code { font:inherit; border:0; padding:0; background:transparent; }
            .table-scroll { width:100%; overflow-x:auto; margin:20px 0; border:1px solid var(--line); border-radius:10px; }
            .message-body table { width:100%; border-collapse:collapse; font-size:14px; line-height:1.6; }
            .message-body th,.message-body td { padding:12px 15px; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; }
            .message-body th { font-weight:600; background:var(--hover); }
            .message-body tr:last-child td { border-bottom:0; }
            mark.search-hit { background:var(--hit); color:var(--nav); border-radius:3px; }
            .empty { padding-top:24px; color:var(--muted); font-size:13px; }
            [hidden] { display:none!important; }
            .sr-only { position:absolute!important; width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0; }
            @media(max-width:940px) { .layout{width:min(760px,calc(100% - 40px));grid-template-columns:minmax(0,1fr);gap:0}.toc{position:relative;top:0;max-height:320px;margin-top:20px}.toc-tools{padding:14px}.reader{padding-top:36px}.toc-title{margin-bottom:10px}.search-status{min-height:18px}.current-position,.reader-actions{display:inline-flex;margin-right:8px}.toc-scroll{max-height:160px} }
            @media(max-width:500px) { body{font-size:15px;line-height:1.7}.layout{width:calc(100% - 32px)}.reader{padding-top:28px}.session-header h2{font-size:21px}.user-prompt{max-width:94%;padding:12px 16px;border-radius:18px}.toc-title{font-size:12px}.question-section{margin-bottom:48px}.search-actions button,.reader-actions button,.reader-actions a{min-height:36px}.copy-code{min-height:32px}.question-link{min-height:40px}.code-block pre{padding:14px;font-size:12px} }
            @media(prefers-reduced-motion:reduce) { html{scroll-behavior:auto}*,*::before,*::after{animation:none!important;transition:none!important} }
            @media print { .toc,.copy-code,.export-note{display:none}.layout{display:block;width:100%;margin:0}.reader{padding:0}.process-group:not([open]){display:none} }

            .user-images { display:flex; flex-wrap:wrap; justify-content:flex-end; gap:10px; margin:0 0 10px auto; max-width:77%; }
            .image-thumbnail { position:relative; width:112px; height:112px; padding:0; border:1px solid var(--line); border-radius:12px; overflow:hidden; background:var(--code); color:var(--text); }
            .image-thumbnail img { width:100%; height:100%; object-fit:cover; display:block; transition:transform .18s ease; }
            .image-thumbnail:hover img { transform:scale(1.04); }
            .image-thumbnail span { position:absolute; left:0; right:0; bottom:0; background:var(--nav); opacity:.9; font-size:9px; padding:3px; }
            .image-missing { color:var(--muted); border:1px dashed var(--line); border-radius:8px; padding:10px 12px; font-size:12px; }
            .image-viewer { width:min(1200px,94vw); max-width:94vw; padding:0; border:1px solid var(--line); border-radius:16px; background:var(--nav); color:var(--text); }
            .image-viewer::backdrop { background:rgba(0,0,0,.84); }
            .image-viewer-toolbar { display:flex; align-items:center; justify-content:space-between; gap:16px; padding:14px 18px; font-size:12px; color:var(--muted); }
            .image-viewer button { border:0; background:var(--hover); color:var(--text); border-radius:8px; padding:8px 12px; min-height:44px; }
            .image-viewer-stage { display:grid; grid-template-columns:44px minmax(0,1fr) 44px; gap:8px; align-items:center; padding:0 12px 16px; }
            .image-canvas { position:relative; width:100%; height:calc(85dvh - 100px); overflow:hidden; touch-action:none; user-select:none; outline-offset:-3px; }
            .image-canvas.zoomed { cursor:grab; }
            .image-canvas.dragging { cursor:grabbing; }
            #image-full { position:absolute; left:50%; top:50%; display:block; max-width:none; object-fit:contain; transform-origin:center; pointer-events:none; user-select:none; }
            .image-viewer-actions { display:flex; align-items:center; gap:6px; margin-left:auto; }
            #image-scale { min-width:44px; text-align:center; font-variant-numeric:tabular-nums; }
            .image-viewer-toolbar { flex-wrap:wrap; gap:8px; }
            #image-caption { flex:1 1 180px; min-width:0; }
            .image-help { padding:0 18px 12px; font-size:11px; color:var(--quiet); text-align:center; }
            @media(max-width:500px) { .user-images{max-width:94%}.image-thumbnail{width:88px;height:88px}.image-viewer-stage{grid-template-columns:32px minmax(0,1fr) 32px;padding:0 6px 10px;gap:2px}.image-viewer-stage button{padding:4px} }
          </style>
        </head>
        <body id="top">
          <main class="layout">
            <nav class="toc" aria-label="会话与问题目录">
              <div class="toc-tools">
                <div class="toc-title">会话目录</div>
                <label class="search-label sr-only" for="search">搜索导出内容</label>
                <input class="search" id="search" type="search" placeholder="搜索会话内容" autocomplete="off" aria-describedby="search-status">
                <div class="search-status" id="search-status" role="status" aria-live="polite">输入关键词搜索问题和回复</div>
                <div class="search-actions">
                  <button id="search-prev" type="button" aria-label="上一个搜索结果" disabled>上一条</button>
                  <button id="search-next" type="button" aria-label="下一个搜索结果" disabled>下一条</button>
                  <button id="search-clear" type="button" aria-label="清除搜索" disabled>清除</button>
                </div>
                <div class="current-position" id="current-position" aria-live="polite">尚未进入问题</div>
                <div class="reader-actions"><button id="question-prev" type="button">上一问</button><button id="question-next" type="button">下一问</button><a href="#top">顶部 ↑</a></div>
              </div>
              <div class="toc-scroll">\(tocItems)</div>
            </nav>
            <div class="reader">
              <section class="summary">
                <h1>Codex 会话导出</h1>
                <div class="meta">项目：\(Self.escapeHTML(projectName)) · \(threads.count) 条会话 · \(Self.iso8601(now())) · 文字已脱敏</div>
                <details class="export-note"><summary>文字已脱敏 · 关于此导出</summary><p>已隐藏平台注入配置、运行环境、插件清单、附件临时路径和内部引用元数据；完整原始记录请使用 .codexmonitorbundle。引用图片未做像素级遮盖。</p></details>
              </section>
              \(conversations)
            </div>
          </main>
          <dialog class="image-viewer" aria-label="查看引用图片">
            <div class="image-viewer-toolbar"><span id="image-caption"></span><div class="image-viewer-actions"><span id="image-scale" aria-label="缩放比例"></span><button type="button" id="image-reset" title="双击图片或按 0 还原">还原</button><button type="button" id="image-close" aria-label="关闭大图">关闭 ×</button></div></div>
            <div class="image-viewer-stage"><button type="button" id="image-prev" aria-label="上一张图片">‹</button><div class="image-canvas" tabindex="0" role="group" aria-label="图片查看区域" aria-describedby="image-help"><img id="image-full" alt="" draggable="false"></div><button type="button" id="image-next" aria-label="下一张图片">›</button></div>
            <div class="image-help" id="image-help">滚轮缩放 · 放大后拖动 · 双击或按 0 还原</div>
          </dialog>
          <script>
            const viewer = document.querySelector('.image-viewer');
            const fullImage = document.getElementById('image-full');
            const imageCanvas = document.querySelector('.image-canvas');
            let imageZoom = 1, imagePanX = 0, imagePanY = 0, imageFit = 1;
            let imageBaseWidth = 0, imageBaseHeight = 0, imageDrag = null, imageRevision = 0;
            function stopImageDrag() {
              const pointer = imageDrag?.id;
              imageDrag = null;
              imageCanvas.classList.remove('dragging');
              if (pointer != null && imageCanvas.hasPointerCapture(pointer)) imageCanvas.releasePointerCapture(pointer);
            }
            function drawImageView() {
              const limitX = imageZoom > 1 ? Math.abs(imageBaseWidth * imageZoom - imageCanvas.clientWidth) / 2 : 0;
              const limitY = imageZoom > 1 ? Math.abs(imageBaseHeight * imageZoom - imageCanvas.clientHeight) / 2 : 0;
              imagePanX = Math.max(-limitX, Math.min(limitX, imagePanX));
              imagePanY = Math.max(-limitY, Math.min(limitY, imagePanY));
              fullImage.style.width = `${imageBaseWidth}px`;
              fullImage.style.height = `${imageBaseHeight}px`;
              fullImage.style.transform = `translate(-50%, -50%) translate(${imagePanX}px, ${imagePanY}px) scale(${imageZoom})`;
              imageCanvas.classList.toggle('zoomed', imageZoom > 1);
              document.getElementById('image-scale').textContent = `${Math.round(imageFit * imageZoom * 100)}%`;
            }
            function measureImageView(reset = false) {
              if (!viewer.open || !fullImage.naturalWidth || !imageCanvas.clientWidth) return;
              if (reset) { stopImageDrag(); imageZoom = 1; imagePanX = 0; imagePanY = 0; }
              imageFit = Math.min(imageCanvas.clientWidth / fullImage.naturalWidth,
                imageCanvas.clientHeight / fullImage.naturalHeight, 1);
              imageBaseWidth = fullImage.naturalWidth * imageFit;
              imageBaseHeight = fullImage.naturalHeight * imageFit;
              drawImageView();
            }
            function resetImageView() { measureImageView(true); }
            function zoomImageAt(nextZoom, x = 0, y = 0) {
              if (!imageBaseWidth) return;
              stopImageDrag();
              nextZoom = Math.max(1, Math.min(8, nextZoom));
              const ratio = nextZoom / imageZoom;
              imagePanX = x - (x - imagePanX) * ratio;
              imagePanY = y - (y - imagePanY) * ratio;
              imageZoom = nextZoom;
              drawImageView();
            }
            imageCanvas.addEventListener('wheel', event => {
              event.preventDefault();
              const rect = imageCanvas.getBoundingClientRect();
              const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1;
              const delta = Math.max(-120, Math.min(120, event.deltaY * unit));
              zoomImageAt(imageZoom * Math.exp(-delta * .0025), event.clientX - rect.left - rect.width / 2,
                event.clientY - rect.top - rect.height / 2);
            }, { passive: false });
            imageCanvas.addEventListener('pointerdown', event => {
              if (event.button !== 0 || !imageCanvas.classList.contains('zoomed')) return;
              event.preventDefault();
              imageDrag = { id: event.pointerId, x: event.clientX, y: event.clientY, panX: imagePanX, panY: imagePanY };
              imageCanvas.setPointerCapture(event.pointerId);
              imageCanvas.classList.add('dragging');
            });
            imageCanvas.addEventListener('pointermove', event => {
              if (imageDrag?.id !== event.pointerId) return;
              imagePanX = imageDrag.panX + event.clientX - imageDrag.x;
              imagePanY = imageDrag.panY + event.clientY - imageDrag.y;
              drawImageView();
            });
            for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) imageCanvas.addEventListener(event, stopImageDrag);
            imageCanvas.addEventListener('dblclick', event => { event.preventDefault(); resetImageView(); });
            document.getElementById('image-reset').addEventListener('click', resetImageView);
            new ResizeObserver(() => measureImageView()).observe(imageCanvas);
            let gallery = [], galleryIndex = 0, imageTrigger = null;
            function showImage(index) {
              galleryIndex = index;
              const image = gallery[index].querySelector('img');
              const revision = ++imageRevision;
              stopImageDrag(); imageZoom = 1; imagePanX = 0; imagePanY = 0;
              imageBaseWidth = 0; imageBaseHeight = 0;
              fullImage.style.visibility = 'hidden';
              fullImage.src = image.src;
              fullImage.decode().then(() => {
                if (revision !== imageRevision || !viewer.open) return;
                resetImageView();
                fullImage.style.visibility = 'visible';
              }).catch(() => {
                if (revision === imageRevision && viewer.open) document.getElementById('image-scale').textContent = '加载失败';
              });
              fullImage.alt = image.alt;
              document.getElementById('image-caption').textContent = `${image.alt} · ${index + 1} / ${gallery.length}`;
              document.getElementById('image-prev').disabled = index === 0;
              document.getElementById('image-next').disabled = index === gallery.length - 1;
            }
            document.querySelectorAll('.image-thumbnail').forEach(button => button.addEventListener('click', () => {
              imageTrigger = button;
              gallery = [...document.querySelectorAll('.question-section:not([hidden]) .image-thumbnail')];
              showImage(gallery.indexOf(button));
              viewer.showModal();
            }));
            document.getElementById('image-close').addEventListener('click', () => viewer.close());
            document.getElementById('image-prev').addEventListener('click', () => { if (galleryIndex > 0) showImage(galleryIndex - 1); });
            document.getElementById('image-next').addEventListener('click', () => { if (galleryIndex < gallery.length - 1) showImage(galleryIndex + 1); });
            viewer.addEventListener('click', event => { if (event.target === viewer) viewer.close(); });
            viewer.addEventListener('keydown', event => {
              if (event.key === '0') { event.preventDefault(); resetImageView(); }
              if (event.key === '+' || event.key === '=') { event.preventDefault(); zoomImageAt(imageZoom * 1.25); }
              if (event.key === '-') { event.preventDefault(); zoomImageAt(imageZoom / 1.25); }
              if (event.key === 'ArrowLeft'  && galleryIndex > 0) { event.preventDefault(); showImage(galleryIndex - 1); }
              if (event.key === 'ArrowRight' && galleryIndex < gallery.length - 1) { event.preventDefault(); showImage(galleryIndex + 1); }
            });
            viewer.addEventListener('close', () => { ++imageRevision; stopImageDrag(); fullImage.removeAttribute('src'); imageTrigger?.focus({ preventScroll: true }); });
            const search = document.getElementById('search');
            const searchStatus = document.getElementById('search-status');
            const searchPrevious = document.getElementById('search-prev');
            const searchNext = document.getElementById('search-next');
            const searchClear = document.getElementById('search-clear');
            const currentPosition = document.getElementById('current-position');
            const questionLinks = [...document.querySelectorAll('.question-link')];
            const questionSections = [...document.querySelectorAll('.question-section')];
            let searchMatches = [];
            let searchMatchIndex = -1;
            let searchTimer;
            let activeQuestion = null;
            const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
            function moveQuestion(direction) {
              const visible = questionSections.filter(section => !section.hidden);
              const index = visible.indexOf(activeQuestion);
              const target = visible[index + direction];
              if (target) activateQuestion(target, { scroll: true, flash: true });
            }
            document.getElementById('question-prev').addEventListener('click', () => moveQuestion(-1));
            document.getElementById('question-next').addEventListener('click', () => moveQuestion(1));
            document.querySelectorAll('.copy-code').forEach(button => button.addEventListener('click', async () => {
              const text = button.closest('.code-block').querySelector('code').textContent;
              const previous = document.activeElement;
              try {
                try { await navigator.clipboard.writeText(text); }
                catch {
                  const input = document.createElement('textarea');
                  input.value = text;
                  input.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
                  document.body.append(input);
                  try {
                    input.select();
                    if (!document.execCommand('copy')) throw new Error('copy denied');
                  } finally { input.remove(); previous?.focus({ preventScroll: true }); }
                }
                button.textContent = '已复制';
              } catch { button.textContent = '复制失败，请手动选择'; }
              setTimeout(() => { button.textContent = '复制代码'; }, 1800);
            }));

            function activateQuestion(target, options = {}) {
              if (!target) return;
              activeQuestion = target;
              const visible = questionSections.filter(section => !section.hidden);
              const position = visible.indexOf(target);
              document.getElementById('question-prev').disabled = position <= 0;
              document.getElementById('question-next').disabled = position < 0 || position >= visible.length - 1;
              const link = questionLinks.find(candidate => candidate.dataset.target === target.id);
              questionLinks.forEach(candidate => {
                const active = candidate === link;
                candidate.classList.toggle('active', active);
                if (active) candidate.setAttribute('aria-current', 'location');
                else candidate.removeAttribute('aria-current');
              });
              if (link) {
                const group = link.closest('.question-group');
                if (group) group.open = true;
                const panel = link.closest('.toc-scroll');
                if (panel) {
                  const itemRect = link.getBoundingClientRect();
                  const panelRect = panel.getBoundingClientRect();
                  if (itemRect.top < panelRect.top) panel.scrollTop += itemRect.top - panelRect.top;
                  else if (itemRect.bottom > panelRect.bottom) panel.scrollTop += itemRect.bottom - panelRect.bottom;
                }
              }
              const number = target.dataset.questionNumber;
              const total = target.dataset.questionTotal;
              currentPosition.textContent = `问题 ${number} / ${total}`;
              if (options.scroll) target.scrollIntoView({ behavior: reduceMotion ? 'instant' : 'smooth', block: 'start' });
              if (options.flash) {
                target.classList.remove('flash');
                requestAnimationFrame(() => target.classList.add('flash'));
                setTimeout(() => target.classList.remove('flash'), 1200);
              }
            }

            questionLinks.forEach(link => link.addEventListener('click', event => {
              event.preventDefault();
              const target = document.getElementById(link.dataset.target);
              if (!target) return;
              history.replaceState(null, '', `#${target.id}`);
              activateQuestion(target, { scroll: true, flash: true });
            }));

            const observer = new IntersectionObserver(entries => {
              const visible = entries.filter(entry => entry.isIntersecting)
                .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
              if (!visible) return;
              activateQuestion(visible.target);
            }, { rootMargin: '-18% 0px -68% 0px', threshold: [0, .25, .6] });
            questionSections.forEach(section => observer.observe(section));

            function clearSearchMarks() {
              document.querySelectorAll('mark.search-hit').forEach(mark => {
                mark.replaceWith(document.createTextNode(mark.textContent || ''));
              });
              questionSections.forEach(section => section.normalize());
            }

            function highlightMatches(root, term) {
              const nodes = [];
              const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                  const parent = node.parentElement;
                  if (!parent || parent.closest('script, style, summary, mark')) return NodeFilter.FILTER_REJECT;
                  return node.nodeValue.toLocaleLowerCase().includes(term)
                    ? NodeFilter.FILTER_ACCEPT
                    : NodeFilter.FILTER_REJECT;
                }
              });
              while (walker.nextNode()) nodes.push(walker.currentNode);
              let count = 0;
              nodes.forEach(node => {
                const text = node.nodeValue;
                const lower = text.toLocaleLowerCase();
                const fragment = document.createDocumentFragment();
                let cursor = 0;
                let match;
                while ((match = lower.indexOf(term, cursor)) !== -1) {
                  fragment.append(document.createTextNode(text.slice(cursor, match)));
                  const mark = document.createElement('mark');
                  mark.className = 'search-hit';
                  mark.textContent = text.slice(match, match + term.length);
                  fragment.append(mark);
                  cursor = match + term.length;
                  count += 1;
                }
                fragment.append(document.createTextNode(text.slice(cursor)));
                node.replaceWith(fragment);
              });
              return count;
            }

            function syncNavigationVisibility(term) {
              questionLinks.forEach(link => {
                const target = document.getElementById(link.dataset.target);
                link.hidden = !!term && (!target || target.hidden);
              });
              document.querySelectorAll('.question-group').forEach(group => {
                const visibleLinks = [...group.querySelectorAll('.question-link')].filter(link => !link.hidden);
                group.hidden = !!term && visibleLinks.length === 0;
                if (term && visibleLinks.length > 0) group.open = true;
              });
              document.querySelectorAll('.toc-session').forEach(group => {
                const session = document.getElementById(group.dataset.session);
                group.hidden = !!term && (!session || session.hidden);
              });
            }

            function showSearchMatch(index) {
              if (searchMatches.length === 0) return;
              searchMatchIndex = (index + searchMatches.length) % searchMatches.length;
              const target = searchMatches[searchMatchIndex];
              const term = search.value.trim().toLocaleLowerCase();
              const process = target.querySelector('.process-group');
              if (process && process.textContent.toLocaleLowerCase().includes(term)) process.open = true;
              activateQuestion(target, { scroll: true, flash: true });
              const base = searchStatus.dataset.summary || '';
              searchStatus.textContent = `${base} · 当前 ${searchMatchIndex + 1} / ${searchMatches.length}`;
            }

            function runSearch() {
              clearSearchMarks();
              const term = search.value.trim().toLocaleLowerCase();
              searchClear.disabled = !term;
              if (!term) {
                questionSections.forEach(section => { section.hidden = false; });
                document.querySelectorAll('.session, .toc-session, .question-group, .question-link').forEach(element => { element.hidden = false; });
                searchMatches = [];
                searchMatchIndex = -1;
                searchPrevious.disabled = true;
                searchNext.disabled = true;
                searchStatus.textContent = '输入关键词搜索问题和回复';
                searchStatus.dataset.summary = '';
                return;
              }

              searchMatches = questionSections.filter(section =>
                section.textContent.toLocaleLowerCase().includes(term)
              );
              questionSections.forEach(section => {
                section.hidden = !searchMatches.includes(section);
              });
              document.querySelectorAll('.session').forEach(session => {
                session.hidden = ![...session.querySelectorAll('.question-section')].some(section => !section.hidden);
              });
              syncNavigationVisibility(term);
              const occurrences = searchMatches.reduce(
                (sum, section) => sum + highlightMatches(section, term),
                0
              );
              const summary = `${searchMatches.length} 个问题 · ${occurrences} 处匹配`;
              searchStatus.dataset.summary = summary;
              searchStatus.textContent = summary;
              searchPrevious.disabled = searchMatches.length === 0;
              searchNext.disabled = searchMatches.length === 0;
              if (searchMatches.length > 0) showSearchMatch(0);
            }

            search.addEventListener('input', () => {
              clearTimeout(searchTimer);
              searchTimer = setTimeout(runSearch, 140);
            });
            searchPrevious.addEventListener('click', () => showSearchMatch(searchMatchIndex - 1));
            searchNext.addEventListener('click', () => showSearchMatch(searchMatchIndex + 1));
            searchClear.addEventListener('click', () => {
              search.value = '';
              runSearch();
              search.focus();
            });

            const initialTarget = document.getElementById(location.hash.slice(1))
              || questionSections[0];
            if (initialTarget?.classList.contains('question-section')) activateQuestion(initialTarget);
          </script>
        </body>
        </html>
        """
    }

    private static func markdownHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [String] = []
        var paragraph: [String] = []
        var listTag: String?
        var listItems: [(indent: Int, tag: String, text: String)] = []
        var quoteLines: [String] = []
        var inCodeBlock = false
        var codeLanguage = ""
        var fenceMarker: Character = "`"
        var fenceLength = 3
        var consumedUntil = -1
        var codeLines: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append("<p>" + paragraph.enumerated().map { index, line in
                Self.inlineMarkdownHTML(line.trimmingCharacters(in: .whitespaces)) + (index == paragraph.count - 1 ? "" : (line.hasSuffix("  ") ? "<br>" : " "))
            }.joined() + "</p>")
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard listTag != nil, !listItems.isEmpty else { return }
            blocks.append(Self.renderList(listItems))
            listItems.removeAll(keepingCapacity: true)
            listTag = nil
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append("<blockquote><p>" + quoteLines.map(Self.inlineMarkdownHTML).joined(separator: "<br>") + "</p></blockquote>")
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let label = codeLanguage.isEmpty ? "代码" : codeLanguage
            blocks.append(
                "<div class=\"code-block\"><div class=\"code-label\"><span>\(Self.escapeHTML(label))</span><button type=\"button\" class=\"copy-code\" aria-label=\"复制代码\">复制代码</button></div>"
                    + "<pre><code>\(Self.escapeHTML(codeLines.joined(separator: "\n")))</code></pre></div>"
            )
            codeLines.removeAll(keepingCapacity: true)
            codeLanguage = ""
        }

        for (lineIndex, line) in lines.enumerated() {
            if lineIndex <= consumedUntil { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inCodeBlock {
                if trimmed.first == fenceMarker,
                   trimmed.prefix(while: { $0 == fenceMarker }).count >= fenceLength,
                   trimmed.allSatisfy({ $0 == fenceMarker }) {
                    flushCode()
                    inCodeBlock = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                flushList()
                flushQuote()
                fenceMarker = trimmed.first!
                fenceLength = trimmed.prefix(while: { $0 == fenceMarker }).count
                let rawLanguage = String(trimmed.dropFirst(fenceLength))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                codeLanguage = String(rawLanguage.filter {
                    $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "+"
                }.prefix(28))
                inCodeBlock = true
                continue
            }

            if lineIndex + 1 < lines.count, trimmed.contains("|"),
               isTableSeparator(lines[lineIndex + 1]) {
                flushParagraph(); flushList(); flushQuote()
                let headers = tableCells(line)
                var rows: [[String]] = []
                var next = lineIndex + 2
                while next < lines.count, lines[next].contains("|"),
                      !lines[next].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[next])); next += 1
                }
                let head = headers.map { "<th>" + inlineMarkdownHTML($0) + "</th>" }.joined()
                let body = rows.map { row in
                    "<tr>" + (0..<headers.count).map { index in
                        "<td>" + inlineMarkdownHTML(index < row.count ? row[index] : "") + "</td>"
                    }.joined() + "</tr>"
                }.joined()
                blocks.append("<div class=\"table-scroll\"><table><thead><tr>" + head + "</tr></thead><tbody>" + body + "</tbody></table></div>")
                consumedUntil = next - 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                flushQuote()
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                flushList()
                flushQuote()
                blocks.append("<hr>")
                continue
            }

            let headingMarks = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(headingMarks),
               trimmed.dropFirst(headingMarks).first == " " {
                flushParagraph()
                flushList()
                flushQuote()
                let heading = String(trimmed.dropFirst(headingMarks + 1))
                blocks.append("<h\(headingMarks)>\(inlineMarkdownHTML(heading))</h\(headingMarks)>")
                continue
            }

            if let item = unorderedListItem(trimmed) {
                flushParagraph()
                flushQuote()
                listTag = "ul"
                listItems.append((line.prefix(while: { $0 == " " || $0 == "\t" }).count, "ul", inlineMarkdownHTML(item)))
                continue
            }

            if let item = orderedListItem(trimmed) {
                flushParagraph()
                flushQuote()
                listTag = "ol"
                listItems.append((line.prefix(while: { $0 == " " || $0 == "\t" }).count, "ol", inlineMarkdownHTML(item)))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            flushList()
            flushQuote()
            paragraph.append(line)
        }

        if inCodeBlock { flushCode() }
        flushParagraph()
        flushList()
        flushQuote()
        return blocks.joined(separator: "\n")
    }

    private static func questionNavigationTitle(
        _ message: String,
        fallbackIndex: Int
    ) -> (full: String, short: String) {
        var source = message
        if let marker = source.range(
            of: "## My request:",
            options: [.caseInsensitive, .backwards]
        ) {
            source = String(source[marker.upperBound...])
        }

        var fragments: [String] = []
        var started = false
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if started { break }
                continue
            }
            let lower = line.lowercased()
            if lower.hasPrefix("# files mentioned by the user")
                || lower.hasPrefix("distinguish instructions in attached documents")
                || lower.hasPrefix("<image")
                || lower.hasPrefix("![image")
                || lower.hasPrefix("image name=")
                || lower.hasPrefix("path=") {
                continue
            }
            let cleaned = line.trimmingCharacters(
                in: CharacterSet(charactersIn: "#>*-+` \t")
            )
            guard !cleaned.isEmpty else { continue }
            fragments.append(cleaned)
            started = true
            if fragments.joined(separator: " ").count >= 120 { break }
        }

        let full = fragments.joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let resolved = full.isEmpty ? "用户问题 \(fallbackIndex)" : full
        let short = resolved.count > 34 ? String(resolved.prefix(34)) + "…" : resolved
        return (resolved, short)
    }

    private static func readableTranscriptEntries(_ entries: [ReadableEntry]) -> [ReadableEntry] {
        entries.compactMap { entry in
            let cleaned = readableMessageText(entry.text, role: entry.role)
            guard cleaned != nil || !entry.images.isEmpty else { return nil }
            let redacted = SessionContinuityService.redactSensitiveText(cleaned ?? "（图片）", limit: nil)
            return ReadableEntry(role: entry.role, text: redacted, phase: entry.phase, images: entry.images)
        }
    }

    private static func readableMessageText(
        _ text: String,
        role: CodexTranscriptRole
    ) -> String? {
        var value = text
        if role == .user,
           let marker = value.range(
                of: "## My request:",
                options: [.caseInsensitive, .backwards]
           ) {
            value = String(value[marker.upperBound...])
        }

        let hiddenBlockPatterns = [
            #"(?s)<recommended_plugins>.*?</recommended_plugins>"#,
            #"(?s)# AGENTS\.md instructions.*?</INSTRUCTIONS>"#,
            #"(?s)<INSTRUCTIONS>.*?</INSTRUCTIONS>"#,
            #"(?s)<environment_context>.*?</environment_context>"#,
            #"(?s)<app-context>.*?</app-context>"#,
            #"(?s)<skills_instructions>.*?</skills_instructions>"#,
            #"(?s)<permissions instructions>.*?</permissions instructions>"#,
            #"(?s)<apps_instructions>.*?</apps_instructions>"#,
            #"(?s)<plugins_instructions>.*?</plugins_instructions>"#,
            #"(?s)<collaboration_mode>.*?</collaboration_mode>"#,
            #"(?s)<oai-mem-citation>.*?</oai-mem-citation>"#,
            #"(?s)<image_resize_notice>.*?</image_resize_notice>"#,
        ]
        for pattern in hiddenBlockPatterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        let filteredLines = value.components(separatedBy: .newlines).filter { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            return !lower.hasPrefix("# files mentioned by the user")
                && !lower.hasPrefix("distinguish instructions in attached documents")
                && !lower.hasPrefix("<image name=")
                && !lower.hasPrefix("<image ")
                && lower != "</image>"
                && !lower.hasPrefix("## codex-clipboard-")
                && !lower.hasPrefix("## my request:")
        }
        value = filteredLines.joined(separator: "\n")
        value = value.replacingOccurrences(
            of: #"\n[ \t]*\n(?:[ \t]*\n)+"#,
            with: "\n\n",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func conversationTurns(
        _ entries: [ReadableEntry]
    ) -> [ReadableTurn] {
        var turns: [ReadableTurn] = []
        var current: ReadableTurn?
        for entry in entries {
            if entry.role == .user {
                if let current { turns.append(current) }
                current = ReadableTurn(question: entry.text, responses: [], images: entry.images)
            } else if current != nil {
                current?.responses.append(entry.text)
                current?.phases.append(entry.phase)
            }
        }
        if let current { turns.append(current) }
        return turns
    }

    private static func renderList(_ items: [(indent: Int, tag: String, text: String)]) -> String {
        guard let first = items.first else { return "" }
        var levels = [(indent: first.indent, tag: first.tag)]
        var html = "<\(first.tag)><li>\(first.text)"
        for item in items.dropFirst() {
            if item.indent > levels.last!.indent {
                levels.append((item.indent, item.tag))
                html += "<\(item.tag)><li>\(item.text)"
                continue
            }
            while levels.count > 1 && item.indent < levels.last!.indent {
                html += "</li></\(levels.removeLast().tag)>"
            }
            html += "</li>"
            if item.tag != levels.last!.tag {
                html += "</\(levels.removeLast().tag)><\(item.tag)>"
                levels.append((item.indent, item.tag))
            }
            html += "<li>\(item.text)"
        }
        while let level = levels.popLast() { html += "</li></\(level.tag)>" }
        return html
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        var cells: [String] = [], current = "", escaped = false
        for character in value {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "|" { cells.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(character) }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        return !cells.isEmpty && cells.allSatisfy {
            $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func markdownQuote(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
    }

    private static func escapeDetailsMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: #"</?details\b[^>]*>|</?summary\b[^>]*>"#,
            with: "", options: .regularExpression)
    }

    private static func markdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func unorderedListItem(_ value: String) -> String? {
        for marker in ["- ", "* ", "+ "] where value.hasPrefix(marker) {
            return String(value.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedListItem(_ value: String) -> String? {
        guard let dot = value.firstIndex(of: "."),
              value.index(after: dot) < value.endIndex,
              value[value.index(after: dot)] == " ",
              !value[..<dot].isEmpty,
              value[..<dot].allSatisfy({ $0.isNumber })
        else { return nil }
        return String(value[value.index(dot, offsetBy: 2)...])
    }

    private static func inlineMarkdownHTML(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let suffix = text[index...]

            if text[index] == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex, #"\`*_{}[]()#+-.!>|"#.contains(text[next]) {
                    result += escapeHTML(String(text[next]))
                    index = text.index(after: next)
                    continue
                }
            }

            if suffix.hasPrefix("**"),
               let close = text.range(
                    of: "**",
                    range: text.index(index, offsetBy: 2)..<text.endIndex
               ) {
                let content = String(text[text.index(index, offsetBy: 2)..<close.lowerBound])
                result += "<strong>\(inlineMarkdownHTML(content))</strong>"
                index = close.upperBound
                continue
            }

            if text[index] == "`" {
                let contentStart = text.index(after: index)
                if let close = text[contentStart...].firstIndex(of: "`") {
                    result += "<code>\(escapeHTML(String(text[contentStart..<close])))</code>"
                    index = text.index(after: close)
                    continue
                }
            }

            if text[index] == "[",
               let labelEnd = text[index...].firstIndex(of: "]") {
                let openParen = text.index(after: labelEnd)
                if openParen < text.endIndex,
                   text[openParen] == "(",
                   let targetEnd = text[text.index(after: openParen)...].firstIndex(of: ")") {
                    let label = String(text[text.index(after: index)..<labelEnd])
                    let target = String(text[text.index(after: openParen)..<targetEnd])
                    if let href = safeLinkHref(target) {
                        result += "<a href=\"\(escapeHTML(href))\">\(escapeHTML(label))</a>"
                    } else {
                        result += escapeHTML(label) + " <code>" + escapeHTML(target) + "</code>"
                    }
                    index = text.index(after: targetEnd)
                    continue
                }
            }

            if text[index] == "*" || (text[index] == "_" &&
                (index == text.startIndex || !text[text.index(before: index)].isLetter)) {
                let marker = text[index]
                let contentStart = text.index(after: index)
                if let close = text[contentStart...].firstIndex(of: marker), close > contentStart {
                    result += "<em>\(escapeHTML(String(text[contentStart..<close])))</em>"
                    index = text.index(after: close)
                    continue
                }
            }

            result += escapeHTML(String(text[index]))
            index = text.index(after: index)
        }
        return result
    }

    private static func safeLinkHref(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).absoluteString
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto", "file"].contains(scheme)
        else { return nil }
        return url.absoluteString
    }

    private func writePortableBundle(
        threads: [LocalThreadRecord],
        projectName: String,
        to outputURL: URL,
        progress: ((SessionExportProgress) -> Void)?
    ) throws {
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("codex-monitor-export-\(UUID().uuidString)", isDirectory: true)
        let archiveTemp = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingRoot)
            try? fileManager.removeItem(at: archiveTemp)
        }

        var manifestSessions: [SessionPortableManifest.Session] = []
        var checksums: [String: String] = [:]
        let orderedThreads = sorted(threads)
        for (index, thread) in orderedThreads.enumerated() {
            progress?(SessionExportProgress(
                completed: index,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .reading,
                fraction: 0.80 * Double(index) / Double(orderedThreads.count)
            ))
            guard fileManager.fileExists(atPath: thread.rolloutURL.path) else {
                throw ExportError(message: "会话原始记录不存在：\(thread.title)")
            }
            let stateFolder = thread.isArchived ? "archived" : "active"
            let relativePath = "sessions/\(stateFolder)/\(RolloutReader.plainFilename(thread.rolloutURL))"
            let target = stagingRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if RolloutReader.isCompressed(thread.rolloutURL) {
                try RolloutReader.copyDecoded(from: thread.rolloutURL, to: target)
            } else { try fileManager.copyItem(at: thread.rolloutURL, to: target) }
            let digest = try Self.sha256(of: target)
            checksums[relativePath] = digest
            manifestSessions.append(SessionPortableManifest.Session(
                threadID: thread.id,
                title: thread.title,
                archived: thread.isArchived,
                updatedAt: Self.iso8601(thread.updatedAt),
                originalCwd: thread.projectPath,
                gitBranch: thread.gitBranch,
                ownershipAlias: thread.ownership.confidence == .observed
                    ? thread.ownership.accountAlias
                    : nil,
                ownershipConfidence: thread.ownership.confidence.rawValue,
                rolloutPath: relativePath,
                sha256: digest
            ))
            progress?(SessionExportProgress(
                completed: index + 1,
                total: orderedThreads.count,
                currentItem: thread.title,
                stage: .processing,
                fraction: 0.80 * Double(index + 1) / Double(orderedThreads.count)
            ))
        }

        let projectPath = threads.first?.projectPath ?? ""
        let manifest = SessionPortableManifest(
            format: SessionPortableManifest.supportedFormat,
            createdAt: Self.iso8601(now()),
            source: SessionPortableManifest.Source(
                application: "Codex Notch Monitor",
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                platform: "macOS"
            ),
            project: SessionPortableManifest.Project(displayName: projectName, originalPath: projectPath),
            sessions: manifestSessions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        let manifestURL = stagingRoot.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
        checksums["manifest.json"] = Self.sha256(manifestData)

        let notice = """
        Codex Notch Monitor 可恢复会话备份

        此文件包含原始 Codex 会话 JSONL，可能包含提示词、源码、终端输出、绝对路径、图片以及意外输出的凭据。
        请勿公开上传或发送给不可信的第三方。此备份不包含 auth.json、Cookie、Token 或其他独立账号凭据文件。
        格式：codex-notch-session/v1
        """
        let noticeData = Data(notice.utf8)
        try noticeData.write(
            to: stagingRoot.appendingPathComponent("README.txt"),
            options: .atomic
        )
        checksums["README.txt"] = Self.sha256(noticeData)
        let checksumData = try encoder.encode(SessionPortableChecksums(algorithm: "SHA-256", files: checksums))
        try checksumData.write(
            to: stagingRoot.appendingPathComponent("checksums.json"),
            options: .atomic
        )

        progress?(SessionExportProgress(
            completed: orderedThreads.count,
            total: orderedThreads.count,
            currentItem: outputURL.lastPathComponent,
            stage: .compressing,
            fraction: 0.90
        ))
        try createZipArchive(from: stagingRoot, to: archiveTemp)
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: archiveTemp)
        } else {
            try fileManager.moveItem(at: archiveTemp, to: outputURL)
        }
    }

    private func transcriptEntries(
        at url: URL,
        progress: ((Int64, Int64) -> Void)? = nil
    ) throws -> [ReadableEntry] {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ExportError(message: "找不到会话原始记录：\(url.lastPathComponent)")
        }
        var entries: [ReadableEntry] = []
        var lastFormats = Set<String>()
        try forEachJSONLine(at: url, progress: progress) { object in
            let sources = SessionExportImages.sources(from: object)
            let parsed = CodexTranscriptParser.message(from: object)
            guard parsed != nil || !sources.isEmpty else { return }
            let message = ReadableEntry(role: parsed?.role ?? .user, text: parsed?.text ?? "（图片）",
                phase: parsed?.phase, images: sources)
            let format = object["type"] as? String ?? ""
            if let last = entries.last, last.role == message.role, last.text == message.text,
               !lastFormats.contains(format),
               last.phase == nil || message.phase == nil || last.phase == message.phase {
                let index = entries.count - 1
                if message.phase != nil { entries[index].phase = message.phase }
                if sources.contains(where: { $0.hasPrefix("data:image/") }) || entries[index].images.isEmpty {
                    entries[index].images = sources
                }
                lastFormats.insert(format)
                return
            }
            entries.append(message)
            lastFormats = [format]
        }
        return entries
    }

    private func forEachJSONLine(
        at url: URL,
        progress: ((Int64, Int64) -> Void)? = nil,
        handleObject: ([String: Any]) -> Void
    ) throws {
        try RolloutReader.forEachLine(at: url, maximumLineBytes: 32 * 1_024 * 1_024, skipOversized: false, progress: progress) { data in
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { handleObject(object) }
        }
    }

    private func createZipArchive(from directory: URL, to outputURL: URL) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", directory.path, outputURL.path]
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                throw ExportError(message: detail)
            }
            throw ExportError(message: "创建会话备份包失败")
        }
    }

    private func sorted(_ threads: [LocalThreadRecord]) -> [LocalThreadRecord] {
        threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
