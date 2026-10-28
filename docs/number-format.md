# 大数字统一格式（中文万／亿，可切换 K/M/B）施工方案

先读 `AGENTS.md`。不提交、不推送、不安装。

## 1. 决策

- 全项目的 Token、事件数等大数字统一由一个格式化器生成，不允许各处自己拼接。
- 默认使用**中文万／亿**；设置里提供开关，可以切换为 **K/M/B**。
- 金额（美元）、百分比、会话数、天数等小计数不在本次范围内，保持现有格式。

## 2. 规则

新文件 `Sources/CodexNotchMonitor/CountFormatter.swift`，提供纯函数 `CountFormatter.string(_ value: Int64, style: CountStyle) -> String`：

### 中文（`.chinese`，默认）

| 区间 | 写法 | 示例 |
|---|---|---|
| 小于 1 万 | 完整数字，带千分位 | 8,432 |
| 1 万到 1 亿 | 换算成万；小于 100 万保留 1 位小数，否则取整并带千分位 | 12.3万、541万、3,456万 |
| 1 亿及以上 | 换算成亿；小于 10 亿保留 2 位小数，10 亿到 100 亿保留 1 位，100 亿及以上取整 | 1.84亿、68.7亿、123亿 |

- 统一四舍五入。去掉末尾的 0：1.50亿显示为 1.5亿，2.0万显示为 2万。
- 进位跨档时换到上一档：9,999.96 万应显示为 1亿，而不是 10,000万。
- 数字和单位之间不加空格。
- 负数、NaN 一律显示"—"。

### 英文（`.western`）

沿用现有 `CodexActivityTokenUsageFormatter` 的规则（K/M/B，保留 1 位小数，去掉 .0），缩写后达到 100 的不带小数（121M），与玻璃面板现有规则一致。

### 偏好

- 新偏好键 `display.countStyle`，取值 `chinese`／`western`，缺省为 `chinese`。
- 修改时发通知（或通过 `@AppStorage`），让菜单栏、灵动岛、玻璃面板、监控中心即时刷新。

## 3. 替换范围

把下列各处换成调用 `CountFormatter`，并逐一列出：

- `CodexActivityTokenUsageFormatter`：灵动岛卡片、胶囊、紧凑态，保留类型名作为转发外壳，避免大范围改名。
- `TurnTokenState` 中的 K／M／B 格式，以及菜单栏本轮 Token 显示。
- `GlanceView.compactTokens`、`GlanceDayStrip.tokenText`。
- `NotchView` 中自定义的"万"格式（约第 4084 行）以及其他直接显示完整位数的 Token 数字。
- `IslandUsageSections`／`IslandUsagePresentation`／`ActivityIslandUsageDashboard` 等用量页中的 Token 数字。
- 用 `rg` 全局搜索 `"%.1fM"`、`"K"`、`"M"`、`"B"`、`1_000_000`、`.decimal` 等，不要遗漏。

## 4. 菜单栏宽度

`StatusItemLayout` 依赖文本宽度预算。中文写法可能更宽，比如"541.1万"和"5.4M"。布局按实际文本测量，不得硬编码字符数。相关测试中写死的字符串断言要按新的默认值（中文）更新，同时补充 western 样式下的断言。

## 5. 设置入口

在现有的通用或面板设置页（沿用原生设置控件和现有分组，不新建页面），加一项"数字单位"：分段控件，两段为"万／亿"和"K／M／B"，下方用一行小字示例当前样式（例如"1.84亿 · 541万"）。

## 6. 测试

新增 `Tests/CountFormatterTests.swift` 并接入 `scripts/test.sh`：

- 覆盖 0、9,999、10,000、99,999、999,999、1,000,000、99,995,000、99,999,999、100,000,000、999,999,999、1,000,000,000、9,995,000,000、10,000,000,000、12,345,678,901 等边界，两种样式都测。
- 进位跨档、去掉末尾 0、负数。
- 偏好缺省值和切换。

现有测试中依赖 K/M/B 字符串的断言，按默认中文样式更新，并逐条说明。跑沙箱能跑的测试和 `scripts/build-app.sh arm64`，报告中逐条列出因沙箱无法执行的测试组。

## 7. 约束

- 只做格式替换，不改任何统计口径或数据来源。
- 不碰 `docs/island-focus-stage.md` 列出的受保护动效文件。

## 8. 本轮实现与验证记录

记录时间：2026-10-22 00:46（北京时间）。实现已落地；完整编译、构建与界面验收仍待可运行环境验证。

### 替换点

下列位置以函数／类型作为稳定入口，具体行号见本轮交付报告。

| 文件（均在 Sources/CodexNotchMonitor） | 位置与改动 |
|---|---|
| CountFormatter.swift | 新增 CountStyle 偏好与通知、纯函数 string、展示入口 display 和图表入口 chart；Decimal 四舍五入，跨档进位、末尾零清理、非法值保护 |
| ActivitySessionState.swift | CodexActivityTokenUsageFormatter 保留类型名，转发统一格式；覆盖岛内卡片、胶囊、紧凑态和累计提示 |
| TurnTokenState.swift | MenuBarTokenFormatter.shortCount 转发；本轮标签和菜单栏标题沿用调用链 |
| GlanceView.swift | compactTokens 转发，增加偏好刷新依赖 |
| GlanceForecast.swift | GlanceDayStrip.tokenText 转发；原成本缩写单独保留在 compactCost，美元规则不变 |
| GlanceWeatherViews.swift | 七日条带悬停／辅助功能 Token 文案转发，增加偏好刷新依赖 |
| NotchView.swift | tiboCompactCount、formatTokens、formatCompactTokens、AnalysisSmoothTrendPlot.formatted、AnalysisActivityStyle.tokens、AnalysisActivityBarChart.formatted／detail、TokenActivityHeatmap.compactTokens；监控中心及子图表增加偏好刷新依赖 |
| IslandUsageSections.swift | IslandUsageFormatting.tokens 转发；指标、趋势与热图随偏好刷新。IslandUsagePresentation 和 ActivityIslandUsageDashboard 通过现有该视图链路获得统一格式，无须修改数据投影 |
| ClaudeCodeView.swift | 按日 Token 明细和图表辅助功能转发；总量复用 MenuBarTokenFormatter；增加偏好刷新依赖 |
| GlanceContentSettingsView.swift | 内容 → 用量中增加“数字单位”分段控件和实时示例 |
| App.swift | 订阅样式通知，刷新菜单栏与 MonitorStore 观察视图 |
| ActivityIslandWindowController.swift | 订阅样式通知，刷新岛体模型的展示；不改变窗口／动效时序 |

StatusItemLayout 原有实现已使用 NSString 实际字体宽度测量，因此未改生产布局算法。新增中文／英文文字恰好适配与少 1 pt 时退让的测试。

### 更新的旧断言

- Tests/TurnTokenStateTests.swift：999,950 的 `1.0M → 100万`；0 的 `0K → 0`；1 的 `<0.1K → 1`；750 的 `0.8K → 750`；1,234,567,890 的 `1.2B → 12.3亿`；257,800 的本轮标签及完整菜单栏标题从 `257.8K → 25.8万`。新增 western 转发断言：258K、1M、0。
- Tests/ActivitySessionStateTests.swift：会话累计 `95.3M → 9,530万`；格式化器 `128K → 12.8万`；完成态 `本轮 6.9M tokens · 累计 122.1M tokens → 本轮 690万 tokens · 累计 1.22亿 tokens`；运行态累计 `122.1M → 1.22亿`。新增 western 转发仍为 128K 的断言。统计值、会话归属和状态断言未改。
- Tests/GlanceForecastTests.swift：峰值摘要 `121M／12.3M → 1.21亿／1,230万`；Token 表中的 `1.0K → 1,000`、`12.3K → 1.2万`、`99.9K → 10万`、`100K → 10万`、`121K → 12.1万`、`1.0M → 100万`、`12.3M → 1,230万`、`99.9M → 9,990万`、`100M → 1亿`、`121M → 1.21亿`、`1.0B → 10亿`、`12.3B → 123亿`、`100B → 1,000亿`、`121B → 1,210亿`。0、999、非法值及全部美元断言保留。
- Tests/StatusItemLayoutTests.swift：布局样本文字 `999.9M → 10亿`、`1.2K → 1,200`、`1.2M → 120万`、`1.3M → 130万`、`6.5M → 650万`；候选顺序和宽度上限断言保留。补充两种样式的真实字体测量边界。
- Tests/CountFormatterTests.swift：新增 71 项检查，覆盖方案全部边界、进位、负数、NaN／无穷、Int64 极值、偏好缺省／非法值／读写和通知。既有格式测试通过进程内 volatile domain 固定中文，避免用户本机偏好影响结果，不改写用户标准偏好。
- scripts/test.sh：新增格式化器组，并向依赖它的独立编译组加入 CountFormatter.swift；没有跳过或弱化原有测试。

### 验证结果与限制

- 主脚本按原命令执行，遇到 AnalysisPresentation 编译错误中止；随后通过任务临时脚本逐组执行原有编译及测试命令，编译失败立即停止该组，避免执行残留二进制。
- 主测试共 20 组：17 组通过，包括 CountFormatter（71）、GlanceForecast（3,478）、RolloutReader（13）、ModelSmoke（123）、ActivitySessionState（147）、NativeActivity（57）、RippleGlowRuntime、ActivityIslandLifecycle、StatusItemLayout（176）、TurnTokenState、ActivityIslandPreferences、CodexSetupService、AppUpdateService、CostSmoke、PricingCatalog、TiboFeed（66）、QuotaResetMonitor（18）。括号为对应日志输出的检查数。
- AnalysisPresentationTests：编译受限，sandbox-exec 返回 Operation not permitted，SwiftUI State 宏插件无法启动。
- ActivityIslandPanelTests：同样受 SwiftUI 宏插件沙箱限制，无法完成编译／执行。
- ClaudeRuntimeTests（包含 IslandApprovalTests）：按 scripts/test-claude.sh 的原运行时编译命令单独续跑，受同一宏插件限制；审批与运行态断言未执行。
- ClaudeCodeTests：执行时抛出 BridgeError.bindFailed；独立 AF_UNIX bind 探针返回 errno=1／Operation not permitted，沙箱阻止本地 socket 绑定。
- ClaudeHookProcessTests：22/22 通过。
- ContinuityTests：运行失败于“重复问题跨轮次保留原图，图片独立提问不丢失”。本轮未改其代码和断言，原因尚未确认，不归类为已证实的沙箱问题。
- arm64 构建：执行 scripts/build-app.sh arm64，默认模块缓存目录不可写；将模块缓存定向到本任务 .tmp 目录后重试，SwiftPM manifest 的 sandbox-exec 仍返回 Operation not permitted。本轮未完成 Release 构建，build 下已有 App 不能视为本轮产物。
- 修改的界面文件通过 swiftc -frontend -parse 语法检查；此项不替代完整类型检查或 UI 验收。git diff --check 通过。
- 第 2 节所列 8 个受保护文件（含整个 ActivityIslandMotion.swift）与任务开始时 SHA-256 全部一致；未安装、提交、推送，未回滚其他改动。README 中英文同步设置入口，ROADMAP 保留未完成验证状态。
- 日志、施工前文件快照、task.diff、逐组结果及 protected-check.txt 位于项目 .tmp/number-format/。
