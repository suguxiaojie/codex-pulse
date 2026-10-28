# 性能优化第二轮：恢复首次过滤、快速时间戳、错开启动任务

先读 `AGENTS.md` 和 `docs/perf-cost-incremental.md`（上一轮）。不提交、不推送、不安装。工作区里有大量其他未提交改动，一律不碰、不回滚、不格式化。

## 0. 上一轮实测结果（真实 5 GB 会话目录，arm64 Release）

| 指标 | 上一轮之前 | 上一轮之后 |
|---|---|---|
| 启动后 30 秒累计 CPU | 62 s | 64 s |
| 6 分钟累计 CPU | 91 s | 103 s |
| 内存峰值 | 522 MB | 739 MB |

启动后 25 秒采样：四个任务同时各占满一个核——`CostService.scanCodex`、`SessionActivityService.readSnapshot`、`SessionContinuityService.scanLocalThreads`、`ClaudeCodeUsageScanner.scan`。最大单项热点是时间戳解析：`SessionActivityService.parseDate` 约 6000 次采样、`ClaudeCodeTranscriptDecoder.timestamp` 约 4800 次（25 秒、约 10000 次/线程）。

## 1. 恢复首次全量解析的 ripgrep 预过滤（修正上一轮退步）

`CostService.cachedParseCodexFile` 首次（非追加）解析未压缩文件时，恢复上一轮之前的路径：优先 `ripgrepRelevantLines` 只取含 `session_meta` / `turn_context` / `token_count` 的行，失败再回退现有逻辑。增量追加部分保持现在的 `incrementalLines`。

- 首次解析完成后，`offset` 必须设为解析时的文件末尾的最后一个完整换行之后（与现在的语义一致），保证之后的增量从正确位置继续；`ParseState` 取首次解析结束时的 model / sessionID / projectPath。
- 注意 ripgrep 只返回匹配行，无法得知最后一个换行位置：用「首次解析时读到的文件大小」及该处之前最后一个 `\n` 的位置计算 `offset`（只需读文件末尾一小段确认），不要整份读入内存。
- 保持 `Tests/CostIncrementalTests.swift` 现有断言全部通过；补一个用例：首次走 ripgrep、随后追加走增量，结果与全量解析一致（ripgrep 不可用时测试应能跳过或走回退路径，不得失败）。

## 2. 快速时间戳解析

新增一个共享的纯函数（建议 `Sources/CodexNotchMonitor/FastTimestamp.swift`，并加入 `scripts/test.sh` 中所有编译到相关源文件的组），解析 Codex / Claude 日志里的 ISO 8601 时间：

- 支持 `YYYY-MM-DDTHH:MM:SS(.fraction)?(Z|±HH:MM)`，小数位 0–9 位均可。
- 直接从 UTF-8 字节计算（不分配中间字符串），用整数运算得到 Unix 时间（天数换算用标准公历算法），不使用 `Calendar` 或 `DateFormatter`。
- 不符合格式时返回 nil，由调用方回退到现有 `ISO8601DateFormatter` 路径，保证兼容。
- 替换以下调用点的首选路径：`SessionActivityService.parseDate`、`ClaudeCodeTranscriptDecoder.timestamp`（现在每次调用都新建两个 `ISO8601DateFormatter`，这本身就很慢）、`CostService.parseCodexFile` 内的时间解析、`SessionContinuityService` 第 798 行附近的时间解析。
- 测试：与 `ISO8601DateFormatter`（含小数秒）对 1 万个随机时间（含时区偏移、闰年 2 月 29 日、年末、0 位与 3/6/9 位小数）逐一比较，误差不超过 1 微秒；非法输入返回 nil；打印两者耗时对比。

## 3. 错开启动任务

`MonitorStore` 第 428–432 行在启动时同时调用 `refreshQuota`、`refreshSessionActivity`、`refreshCost`、`refreshTiboFeed`、`refreshContinuity(forceInventory: true)`；`ClaudeCodeRuntime` 启动时也会 `refreshUsage()`。

- `refreshSessionActivity` 与 `refreshQuota` 立即执行（灵动岛依赖）。
- `refreshContinuity(forceInventory: true)` 延后 8 秒；`refreshCost` 延后 15 秒；Claude Code 用量扫描（`ClaudeCodeRuntime` 启动后的首次 `refreshUsage`）延后 20 秒。用户主动触发（打开对应页面、手动刷新）时不延后，立即执行。
- `CostService`、`SessionContinuityService`、`ClaudeCodeUsageScanner` 所在的后台队列使用 `.utility`（已是的保持）；启动阶段的首轮扫描使用 `.background`。
- 不改变定时器周期与任何结果；只改首次触发时机与优先级。若某个界面在数据就绪前显示，沿用现有的加载态，不得显示空数据为 0 的误导内容（确认现有加载态即可）。

## 4. 测试与范围

可改：`CostService.swift`、新增 `FastTimestamp.swift`、`SessionActivityService.swift`（仅 `parseDate`）、`ClaudeCodeTranscript.swift`（仅 `timestamp`）、`SessionContinuityService.swift`（仅时间解析函数）、`MonitorStore.swift`（仅启动调度那几行及必要的延迟辅助）、`ClaudeCodeRuntime.swift`（仅首次 `refreshUsage` 的时机）、相关测试与 `scripts/test.sh`。其他文件不碰。

修改 `SessionContinuityService` 后必须运行 `Tests/ContinuityTests.swift` 对应的组（见 `AGENTS.md`）。尽量运行完整 `scripts/test.sh`；沙箱无法执行的部分（例如 SwiftUI 宏、SwiftPM 构建）逐条列出。报告写明每项改动的位置、时间戳解析的对照测试结果与耗时对比。
