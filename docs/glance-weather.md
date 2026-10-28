# 菜单栏玻璃面板重设计：方向 C「气象」施工方案

交给 Codex 执行。执行前先读 `AGENTS.md`，冲突时以 AGENTS.md 为准。完成后不要提交、推送或发布，由 Claude 做最终验收。

设计稿：https://claude.ai/code/artifact/cf0d3c76-5ba4-4f12-b96a-dabfe333d70c （方向 C）

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 布局 | 方向 C 气象：玻璃随额度状态轻度染色；主区是大数字加一句"能不能撑到重置"的预报；下方是 7 天条带和小数据块 |
| 大数字字体 | SF Pro Rounded（`.system(size:weight:design: .rounded)`） |
| 状态色 | 随额度变化：充足为冷青单色，偏紧为琥珀，告急为红 |
| 透明度 | "面板不透明度"滑块控制**整个面板**；去掉内容区固定 72% 的深色底 |
| Spark | 已下架，不做任何专门处理；额度窗口完全按接口返回的数据显示 |

## 2. 硬性约束

- 保留液态玻璃：macOS 26 用 `NSGlassEffectView`，旧系统用 `NSVisualEffectView` 回退。`GlanceGlassSurface`、`GlanceGlassCompositionView` 的结构不变。
- 偏好键全部不迁移：`glance.surfaceOpacity`（10%–90%）和 7 个 `glance.content.*` 开关原样沿用，用户已保存的值继续生效。
- 系统"降低透明度"或"增强对比度"打开时，面板变为不透明，染色光晕关闭。
- 额度重置的二次确认、官方接口调用、`IslandResetActionPolicy` 等逻辑不改；`quotaReset` 子页面只调整视觉，使它与新外观一致，功能不变。
- 成本必须保留"估算，非账单"字样；预报必须标"估算"。
- 不读取凭据，不写 `~/.codex` 和应用支持目录，不改 QuotaService／CostService 的数据口径。
- 只改与本方案相关的文件。工作区里有大量用户未提交的改动，包括正在验收的灵动岛改动，**不得触碰灵动岛相关文件**。

## 3. 新增纯逻辑（可测）

新文件 `Sources/CodexNotchMonitor/GlanceForecast.swift`，不依赖 SwiftUI：

### 3.1 `QuotaPaceForecast`

输入：一个 `RateLimitWindow`（`usedPercent`、`windowDurationMinutes`、`resetsAt`）和 `now`。

- 窗口开始时间 = `resetsAt − windowDurationMinutes`，已过时长 = `now − 开始时间`。
- 缺少时长或重置时间、已过时长小于 1 小时、或数据不合法时，返回 `.insufficient`。
- `usedPercent == 0` 时返回 `.lastsUntilReset`。
- 消耗速度 = `usedPercent / 已过时长`；预计用完时间 = `now + remainingPercent / 速度`。
  - 预计用完时间不早于 `resetsAt`：返回 `.lastsUntilReset`。
  - 早于 `resetsAt`：返回 `.exhausts(at: Date)`。
- `remainingPercent == 0` 时返回 `.exhausted`。

展示文案（中文，统一由一个函数生成，便于测试）：

| 结果 | 主句 | 副句 |
|---|---|---|
| `.lastsUntilReset` | 按当前速度，可用到重置 | 估算 · X 天 Y 小时后重置 |
| `.exhausts(at:)` | 按当前速度，约 N 天／N 小时后用完 | 估算 · X 天 Y 小时后重置 |
| `.exhausted` | 额度已用完 | X 天 Y 小时后重置 |
| `.insufficient` | 数据不足，暂不预测 | X 天 Y 小时后重置 |

倒计时文字复用现有的 `QuotaResetCountdown`。

### 3.2 `GlanceTone`

`case calm, tight, critical`，由主窗口（`limitingWindow`）决定：

- 剩余低于 20%，或结果为 `.exhausted`：`critical`。
- 剩余低于 50%，或结果为 `.exhausts`：`tight`。
- 其他情况：`calm`。

阈值与现有 `FloatingSurfaceTheme.quotaHealth` 保持一致（20／50）。颜色：calm 用冷青（约 `#3FB5C9`），tight 用系统橙／琥珀，critical 用系统红。

### 3.3 `GlanceDayStrip`

从 `selectedCostScope.costActivity`（成本）或 `usage.activity`（Token）取最近 7 天，生成 7 个桶。每个桶包含星期标签（最后一天显示"今"）、数值和是否为峰值。缺失的日期补 0。

## 4. 视图改动（`GlanceView.swift`，可拆出 `GlanceWeatherViews.swift`）

自上而下：

1. **页眉**：Codex 标志、"Codex Pulse"、账号胶囊（状态圆点＋别名 · 套餐），合并现在的页眉和"当前账号"两行。退出按钮移到页脚。
2. **气象主区**（`showPrimaryQuota`）：
   - "每周额度"等窗口名，取主窗口的 `compactWindowTitle`。
   - 大数字：SF Pro Rounded，约 64 pt，semibold，`%` 用约 27 pt 半透明，使用 `.contentTransition(.numericText())`。
   - 预报主句（12.5 pt medium）和副句（10.5 pt，tertiary）。
   - 有多个窗口时（例如 5 小时＋每周），大数字显示瓶颈窗口；其他窗口在副句下方用一行小字显示："5 小时 81% · 2 小时后重置"。
   - 同步中、加载失败沿用现有占位文案。
3. **染色光晕**：放在 SwiftUI 内容最底层，在面板顶部做一个径向渐变，颜色取 `GlanceTone`，强度约 0.22，轻微模糊；状态切换时用 0.3 秒渐变过渡（Reduce Motion 下无动画）。浅色外观下强度降到约 0.14。降低透明度或增强对比度时不显示。
4. **7 天条带模块**（`showCostEstimate` 或 `showTokenActivity` 至少一个打开时显示）：
   - 标题行："7 天成本 · 估算"加合计金额。两个开关都打开时，右侧出现"成本｜Token"小分段，选择用 `@AppStorage("glance.stripMetric")` 记住；只开一个时不显示分段。
   - 7 列小柱：上方是星期，中间是 40 pt 高、8 pt 宽的圆角柱，下方是数值（金额取整，Token 用 K／M）。峰值柱用不透明主色，其余半透明。悬停时显示该日的完整数值（沿用现有图表的悬停方式）。
   - 原来的周／月／三月／半年切换移除；页脚的监控中心按钮仍可查看长周期。
5. **小数据块行**：三格等宽模块，依次是 Credits（`showCreditBalance`）、今日 Token（`showDailyTokens`）、30 日 Token（`showThirtyDayTokens`）。关掉的格子不占位，剩下的平分宽度；全部关掉时整行隐藏。
6. **重置行**（`showResetEntry`）："额度重置"＋"N 次可使用 ›"（强调色），点击进入现有重置子页面。没有可用次数时，显示过期或不可用状态，沿用现有文案。
7. **页脚**：状态圆点＋"刚刚更新／更新于 HH:mm／数据可能过期"，右侧依次是刷新、监控中心、设置、退出四个图标按钮。

模块样式：背景为白色约 6.5% 不透明度，顶边 0.5 pt 高光，圆角 16（面板圆角保持 `GlanceLayout.cornerRadius`），内边距 10–12。去掉现在所有的 `Divider`。

无历史数据时（`hasCurrentAccountHistory == false`），条带和数据块的位置显示现有的空状态。

## 5. 透明度作用范围

- 删除 `summaryPage` 中 `.background { RoundedRectangle … opacity(0.72) }` 这层内容区底色。
- 不透明度只由 `GlanceGlassChromeView.surfaceOpacity` 决定，覆盖整个面板。
- 低不透明度下保证可读：主要文字保持 `FloatingSurfaceTheme.primary`；次要文字在 macOS 26 上可用 vibrancy，否则保持现有颜色。不透明度低于 30% 时，给文字加一层很轻的阴影（暗色外观 `black.opacity(0.35)`、半径 1.5；浅色外观不加）。
- 降低透明度或增强对比度时，chrome 填充改为不透明，与现有行为一致。

## 6. 高度

- `GlanceContentPreferences.preferredHeight` 按新模块重算，目标是全部开启时约 520 pt。
- 去掉固定的 `accountHeaderHeight`。
- 内容超高时仍可滚动，最大高度不超过现在的 `GlanceLayout.height`（806）。

## 7. 测试

新增 `Tests/GlanceForecastTests.swift` 并接入 `scripts/test.sh`，覆盖：

- `QuotaPaceForecast`：
  - 正常可用到重置；会提前用完；已用完；`used == 0`；已过时长小于 1 小时；缺少 `resetsAt`；缺少时长；`resetsAt` 已经过去。
  - 边界：预计用完时间恰好等于重置时间时，判为可用到重置。
- 文案函数：四种结果的主句和副句。
- `GlanceTone`：19／20／49／50／100 的边界，以及剩余高于 50% 但预计提前用完时判为 `tight`。
- `GlanceDayStrip`：不足 7 天时补 0；峰值标记；最后一天显示"今"；Token 单位格式。
- `GlanceContentPreferences`：各开关组合下的 `preferredHeight` 单调合理；旧偏好值仍能正确读出。

现有完整测试必须全部通过。

## 8. 构建与交付

1. `scripts/test.sh` 全部通过。在沙箱里因为拿不到屏幕、Metal 或 socket 而失败的测试组，在报告中逐条列出，Claude 会在本机原生环境复跑。
2. `scripts/build-app.sh arm64`，只构建 arm64。
3. 不安装、不写 `/Applications`、不提交、不推送；安装和实机验收由 Claude 完成。

### 交付报告必须包含

- 改动文件清单，每个文件一句话说明。
- 确认没有触碰灵动岛相关文件：列出本次改动的文件，并说明与 `docs/island-focus-stage.md` 涉及的文件没有交集。
- 测试与构建的结尾输出。
- 与方案不一致之处及原因。
