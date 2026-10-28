# 菜单栏玻璃面板：Codex／Claude Code 切换 施工方案

在已完成的方向 C「气象」（`docs/glance-weather.md`）基础上，增加和灵动岛展开面板一致的来源切换。先读 `AGENTS.md`，Claude 相关边界以 AGENTS.md 和 `docs/claude-code-integration.md` 为准。不提交、不推送、不安装。

## 1. 切换控件

- 页眉右侧原账号胶囊的位置，改为一个两段的胶囊分段控件"Codex｜Claude"。样式与灵动岛 `ActivityIslandUsageDashboard` 的来源切换保持一致：玻璃胶囊，选中段高亮。
- 只有 `store.claude.enabled == true` 时才显示切换；未启用 Claude 时只显示 Codex，页眉恢复账号胶囊。
- 选择用 `@AppStorage("glance.provider")` 记住（`codex`／`claude`）。Claude 被停用时自动回到 Codex。
- 切换时内容交叉淡入约 0.2 秒（Reduce Motion 下无动画），面板高度随内容重算。
- 账号胶囊在 Codex 模式下移到主区窗口名同一行的右侧，显示状态圆点＋别名 · 套餐；Claude 模式不显示账号。不读取任何 Claude 账号或凭据。

## 2. Codex 模式

与现在完全一致，只是账号胶囊移位。

## 3. Claude 模式

数据只来自 `store.claude` 的 `limits`（`ClaudeCodeRateLimits`）、`usage`（`ClaudeCodeUsageSummary`）和 `statusLineEnabled`。

### 3.1 气象主区

- 窗口：`fiveHour`（时长 300 分钟）和 `sevenDay`（时长 10080 分钟）。大数字显示剩余更少的那个，另一个用一行小字显示在下方，与 Codex 多窗口时的处理相同。
- 把 Claude 窗口转换为 `RateLimitWindow`（`usedPercent` 四舍五入取整、`windowDurationMinutes`、`resetsAt`）后，复用 `QuotaPaceForecast` 和 `GlanceTone`，预报文案和染色规则与 Codex 一致。
- 窗口名："5 小时额度"／"每周额度"。
- 数据状态：
  - `statusLineEnabled == false`：主区显示"开启 Claude 状态栏后可显示额度"，加一个按钮打开现有的 Claude 设置入口。
  - 已开启但 `limits == nil`：显示"等待 Claude Code 下一次回复后同步额度"。
  - `capturedAt` 早于 10 分钟前：副句末尾追加"· 数据于 HH:mm"，并把染色强度减半，表示数据可能过期。

### 3.2 7 天条带

- 数据来自 `usage.days`，指标分段为"成本｜Token"，沿用 `glance.stripMetric`。
- **日期口径**：`Day.date` 是"携带本地日历日的 UTC 零点"，不能直接用 `Calendar.current.startOfDay` 换算。要用 UTC 日历取年月日，再映射到本地的同一天，否则会错位一天。为此单独写纯函数并测试。
- 有任何一天 `estimatedCost == nil` 时，成本视图标注"部分模型未计价"。该天按已知部分计入，悬停明细中注明。
- `usage == nil` 或 `complete == false` 时，显示"正在统计 Claude 用量…"。

### 3.3 小数据块

三格依次为今日 Token、30 日 Token、累计 Token（`lifetimeTokens`）。Credits 和额度重置是 Codex 专属，在 Claude 模式下隐藏。

### 3.4 页脚

刷新按钮在 Claude 模式调用 `store.claude.refreshUsage()`。更新时间取 `usage.updatedAt` 或 `limits.capturedAt` 中较新的一个。

## 4. "显示内容"开关

`showPrimaryQuota`、`showCostEstimate`、`showTokenActivity`、`showDailyTokens`、`showThirtyDayTokens` 两种模式共用；`showCreditBalance`、`showResetEntry` 只作用于 Codex。`preferredHeight` 按当前来源分别计算。

## 5. 测试

新增或补充测试，并接入 `scripts/test.sh`：

- Claude 窗口 → `RateLimitWindow` 的转换；选取瓶颈窗口；两个窗口缺一时的处理。
- UTC 日期口径映射：东八区下 `Day.date` 落在正确的本地星期，不足 7 天时补 0。
- 状态文案：状态栏未开启、无数据、数据过期。
- 未计价标记。
- 来源选择的回退：Claude 未启用时始终为 Codex。
- 两种来源在各开关组合下的 `preferredHeight`。

跑沙箱能跑的测试和 `scripts/build-app.sh arm64`，报告中逐条列出因沙箱无法执行的测试组。

## 6. 范围

只改 Glance 相关文件（`GlanceView.swift`、`GlanceWeatherViews.swift`、`GlanceForecast.swift`、`GlanceContentPreferences.swift`、`GlanceLayout.swift`、`GlanceContentSettingsView.swift`），以及对应测试和 `scripts/test.sh`。确有需要时，可以在 `ClaudeCodeUsage.swift` 中加只读的辅助函数。不改 Claude Hook、安装器、Runtime 和灵动岛文件。
