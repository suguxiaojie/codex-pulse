# Claude Code 接入

## 来源与复用

本次核对的 QuotaView main 提交为 `f7795311bf06c2a54c9b9756da375c50d0f4930e`。上游采用 MIT；原许可和署名保留于 `THIRD_PARTY_NOTICES.md` 及应用内声明。

- [上游接入规格](https://github.com/Duoasa/QuotaView/blob/f7795311bf06c2a54c9b9756da375c50d0f4930e/docs/specs/claude-code-support.md)：Hook 生命周期／权限请求、statusLine 官方额度、JSONL 本地历史三条独立链路。
- `ClaudeCodeTranscript.swift`：复用有界 JSONL 解码、增量读取、文件替换与截断处理；不读取 thinking 内容。
- `ClaudeCodeUsage.swift`／`ClaudeCodePricing.swift`：复用消息＋请求去重、缓存拆分与公开单价映射；补充同路径 inode 替换缓存失效、重复流式计数更新、非法数字拒绝与明确未知价格。
- `ClaudeCodeInstaller.swift`／`ClaudeCodeBridge.swift`／`ClaudePulseHelper`：复用自有配置识别、原状态栏转发、私有 Unix socket、权限请求挂起与回退；独立命名空间、同用户连接检查、精确 route 匹配、有界输出和退出期限。
- `ClaudeCodeRuntime.swift`／`ClaudePermissionRequest.swift`／`ClaudeCodeView.swift`：按现有 Pulse 架构实现生命周期、来源分隔、显式权限操作与独立页面；不引入上游 Codex Hook 或其他 Agent 安装器。

## 产品入口

监控中心新增 Claude Code 页面。连接默认关闭；可独立启用请求处理与官方额度采集。任务汇入现有灵动岛，Claude 待确认任务在灵动岛内展开审批卡片，“查看详情”打开专属请求窗口。Codex 现有账号额度、历史、恢复与导出仍使用原链路。

灵动岛用量页复用现有玻璃布局，顶部 Codex／Claude Code 选择同时驱动额度、Token 汇总、模型成本和热图。`IslandUsagePresentation` 统一两种来源的纯值展示模型，内部 `IslandClaudeUsage` 将 UTC 编码的本地日标签转为岛体使用的本地日，避免跨时区偏移；只使用 Claude 自己的数据，缺失值不会回退 Codex。未知价格不抹去其他日期的已知成本：30 天金额以“≥”标注下界，全部记录均未定价时显示“—”；部分扫描提示优先于未定价提示；Claude 卡片不展示 Codex Credits、套餐或重置操作。停用 Claude 自动回到 Codex，正在进行或等待确认的重置操作禁止切换来源。

历史统计覆盖本机 Claude 项目目录，含子 Agent，不能据此推断当前账号。官方额度是最近状态栏提供的窗口，不读取 Keychain、`.credentials.json`、Cookie 或 API Key。采集时间距当前在 -60 秒至 300 秒内且尚未重置的窗口显示为当前额度；超过 300 秒但重置时间仍在未来时，保留百分比，以 0.55 透明度、中性进度条和“几分钟前观测／几小时前观测”明确标注上次观测，辅助功能说明“上次观测，非当前”。缺失窗口、已到重置时间、超过 300 秒且无重置时间、采集时间超前超过 60 秒或关闭状态栏采集时显示“—”。快照只在 Runtime 内存中保留，不新增落盘；会话结束及 tick 超时不再清空，重新配置（含失败）、停用或新的状态栏载荷不含窗口时清空。

## 配置与恢复

尊重 `CLAUDE_CONFIG_DIR`，默认 `~/.claude/settings.json`。首次写入前保存同目录 `settings.json.codex-pulse-backup`，仅识别本通道 helper 路径、Claude 模式和 route 路径匹配的命令。原 statusLine 单独保存，输出继续转发；停用恢复原配置项。并发修订检查失败或 JSON 结构不可保真时不覆盖文件。

自有 helper 与 route 位于应用支持目录的 Claude 专属通道下。route／socket 为私有权限，身份标识仅用于本机 IPC，不是账号凭据。审批等待上限为 120 秒，route 使用该期限，既有 PermissionRequest Hook 的 3600 秒 timeout 保持不变；启用状态重新配置时更新 route，相同 route 不重复写入，相同设置保留原字节。运行时到期撤销岛内按钮并交回终端。应用退出、请求超时、输入截断、关闭请求处理或停用接入时，未决定的请求交回 Claude Code。权限不会自动批准。

## 任务结束证据

启用状态重新配置时保持 bridge 接收与现有会话；配置期间的非审批 Hook 按接收顺序缓冲，最多 256 条，超出丢弃最旧事件，配置成功且仍启用后重放。PermissionRequest 立即交回原客户端，不进入队列；配置前或配置期间接收的迟到审批回调也不能恢复权限操作。statusLine 可在配置期间更新，失败或停用时清空；失败配置不重放事件。

Hook 结束事件仍优先。若缺失 Stop，运行时仅使用当前轮开始之后的主线程转录：识别 `end_turn`、`stop_sequence`、`max_tokens` 和用户中断标记。结束记录须晚于最近 Hook，之后没有工具调用，最近 Hook 已过去超过 5 秒，且增量读取已追上完整日志尾部，才按完成或取消结束；动作摘要使用本轮最后的助手文本，不读取 thinking。后续用户提问会使旧结束证据失效。

Helper 沿父进程链最多检查 8 层，通过 `sysctl KERN_PROC_PID` 读取父 PID 与可执行名，跳过 sh、bash、zsh、dash、fish、env、login、timeout；遇到环路或读取失败时不发送进程字段。第一个非中间进程以 `hook_process_id`／`hook_process_name` 发送。运行时仅在接收事件时该 PID 存活且名称不是上述中间进程时记录它，后续有效值替换旧值，无效或缺失证据关闭进程兜底；之后仅在 `kill(pid, 0)` 明确返回 `ESRCH` 时将活跃会话记为“已结束”，权限不足等其他错误不视为退出。兜底结束会撤销当前审批能力并交回原客户端，不自动批准。

## 协议与计价核对

- [Claude Hook 官方字段](https://code.claude.com/docs/en/hooks)：`PermissionRequest` 返回 `hookSpecificOutput.decision`；`updatedInput` 保留完整原输入；持久规则必须明确选择并确认。
- [Claude statusLine 官方字段](https://code.claude.com/docs/en/statusline)：`rate_limits.five_hour`／`seven_day`、使用百分比和 Unix 重置时间；字段可能在首次 API 响应前或特定账号下不存在。
- [官方标准定价](https://platform.claude.com/docs/en/about-claude/pricing)：2026-10-21 核对。修正 Sonnet 5.5 缓存读价，并增加 Haiku 5.5 的 100K 输入分档；未来未知版本不继承旧价格。按每条 usage 的 speed／inference_geo 计算：Opus 5.5、Opus 5 和 Opus 4.8 fast 为标准费率的 2 倍；受支持的 4.6 及以后模型美国数据驻留为 1.1 倍，包含 Haiku 5.5 超过 100K 的分档。未知档位／地域或不支持的组合保留未知，标准费率数值不变。缓存拆分不一致时保留总写入量，1 小时量封顶后其余归入 5 分钟；非法数字仍拒绝。估算不含网页搜索等按次计费或无法确认的折扣，不是账单。

## 验证入口

`zsh scripts/test-claude.sh` 在隔离目录测试解码、统计、安装往返、原状态栏转发、helper／socket 通信及实际运行态；该脚本由完整 `scripts/test.sh` 调用。所有权限应答使用合成请求，不处理用户真实请求。当前进度与真实会话验收限制统一记录在 `ROADMAP.md`。

灵动岛双端审批支持范围与安全边界见 [灵动岛审批](island-approvals.md)。
