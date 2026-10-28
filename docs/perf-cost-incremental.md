# 费用统计性能优化：增量解析与日期分桶

先读 `AGENTS.md`。不提交、不推送、不安装。工作区里有大量其他未提交改动（灵动岛、Claude 接入、IPC 等），一律不碰、不回滚、不格式化。

## 1. 现状与问题（实测）

- 用户 `~/.codex/sessions` 约 220 个会话、5.0 GB，单文件最大 403 MB；`archived_sessions` 220 MB。
- `CostService.fetch` 每 5 分钟（`MonitorRefreshCadence.cost`）调用 `scanCodex(lookbackDays: 30)`。
- `cachedParseCodexFile` 按「修改时间 + 文件大小」缓存整份解析结果；正在进行的会话持续追加，所以每次刷新都会把这些大文件**从头**重新解析。采样中表现为周期性 CPU 90–130% 的脉冲；启动时内存峰值曾达 5.8 GB。
- `summarize` 及其辅助函数（约 `CostService.swift` 第 660–840 行）对每条事件调用 `calendar.startOfDay`、`calendar.dateComponents([.day], from:to:)`、`calendar.component(.hour, ...)`，采样中 `_CalendarGregorian.dateComponents`、`TimeZone` DST 规则计算是主要热点之一。

## 2. 要做的事

### 2.1 增量解析（优先）

把 `cachedParseCodexFile` 改为按文件**增量**读取：

- 缓存项保存：已解析到的字节偏移 `offset`、该偏移处的解析状态（当前 `model`、`sessionID`、`projectPath`）、已得到的事件、文件标识（`fileResourceIdentifier` 或 inode）与上次大小。
- 文件变大且标识不变：只从 `offset` 读新增部分，只处理完整行；末尾不完整的行留到下次（`offset` 停在最后一个换行之后）。
- 文件变小、标识变化或修改时间回退：视为替换，丢弃缓存从头解析。
- 压缩文件（`RolloutReader.isCompressed`）不能增量，保持整份解析 + 现有「时间+大小」缓存。
- 读取新增部分时不要把整个文件映射或读入内存；用 `FileHandle` 定位到 `offset` 分块读取（例如 4 MB 一块），逐行处理，单行上限沿用 1 MB 规则（超长行跳过）。
- `ripgrepRelevantLines` 只用于首次全量解析；增量部分直接在 Swift 中按现有标记（`session_meta` / `turn_context` / `token_count`）过滤。
- 缓存只保留 `scanCodex` 本次实际扫描到的文件，其余条目删除，避免内存只增不减。
- 结果必须与当前实现**完全一致**：同样的事件、同样的去重（`deduplicated`）。

### 2.2 汇总阶段的日期分桶

- 在 `summarize` 等函数入口一次性预计算所需的日界（今天起往前最多 180 天的每天 `startOfDay`，升序数组），按事件时间二分查找得到「第几天」，替代逐条 `dateComponents([.day], ...)` 与 `startOfDay`。
- 小时分布：按「事件所在日的日界」计算本地小时；不得逐条调用 `calendar.component(.hour, ...)`。夏令时切换日需与原结果一致（可对日界数组中长度不是 24 小时的那天退回原有 Calendar 计算）。
- 输出（各窗口合计、每日/每小时分布、180 天活动图等）必须与当前实现逐项相同。

### 2.3 启动峰值内存

- 首次全量解析时，`relevantLines` 的 `Data(contentsOf:options:.mappedIfSafe)` 路径保留可以，但不得把多个大文件的中间缓冲同时留在内存里；确认 `autoreleasepool` 覆盖每个文件，ripgrep 输出逐文件释放。

## 3. 测试

在现有 `Tests/CostSmokeTests.swift`（`scripts/test.sh` 中已编译）里补充，或新增测试文件并接入 `scripts/test.sh`：

- 增量正确性：临时目录写一个 JSONL，解析；追加若干 `token_count` 行（含一行不完整、下次补全的行）再次扫描；结果与对整份文件全量解析一致，且第二次只读取了新增字节（通过可测的读取计数或偏移断言）。
- 替换检测：文件被截短或换成新文件时从头解析。
- `turn_context` 中途更换 `model` 后，增量部分的事件使用新 model。
- 日期分桶：构造跨多天、含夏令时切换（用 `TimeZone(identifier: "America/New_York")` 的 Calendar 与 3 月/11 月切换日）的事件，新旧算法的 `summarize` 结果逐项相等（可在测试里保留一份旧算法的参考实现做对照）。
- 性能冒烟：10 万条事件的 `summarize` 在测试机上应明显快于旧实现（打印耗时即可，不设硬阈值）。

## 4. 范围与验证

只改 `Sources/CodexNotchMonitor/CostService.swift`、相关测试文件，必要时 `scripts/test.sh`。不改界面、不改其它服务。

交付前运行：`scripts/test.sh` 中涉及 CostService 的编译组（至少包含 `Tests/CostSmokeTests.swift` 的那一组）以及你新增的测试；能跑则跑完整 `scripts/test.sh`。沙箱可能无法访问 `~/.codex` 或构建 App，逐条列出未能执行的部分。报告写明改了哪些函数、缓存结构、以及与旧结果一致性的验证方式。
