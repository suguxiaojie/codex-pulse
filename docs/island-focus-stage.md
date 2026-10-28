# 灵动岛会话区重设计：方向 B「焦点舞台」施工方案

交给 Codex 执行。执行前先读 `AGENTS.md`，本文件与 AGENTS.md 冲突时以 AGENTS.md 为准。完成后不要提交、推送或发布，由 Claude 做最终验收。

设计稿：https://claude.ai/code/artifact/3476fb6e-a82b-4b9e-8bb7-e16e5d0bdc32 （方向 B）

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 布局 | 方向 B 焦点舞台：一个焦点会话占主卡片并显示最近步骤轨迹，其余会话在下方成一排胶囊，点击切换焦点 |
| Token 口径 | 运行中与结果都显示**本轮** Token；累计 Token 移到悬停提示（help）和无障碍描述 |
| 动作文字 | **单行横向滚动**，沿用现有 `IslandScrollingText` |
| 已完成会话 | 在列表中保留 **10 分钟**后自动移出 |
| 颜色 | 用户未要求改色，**保持现有配色**（`FloatingSurfaceTheme` 不改） |

## 2. 硬性约束：现有动效一律保留

用户明确要求不得删除或削弱任何现有动效。下列文件**只允许被调用，不允许修改其内部实现、参数、曲线或时长**：

- `ActivityIslandStateSmoke.swift`（StateSmoke／Metal 整卡效果、完成过渡、量子动效）
- `ActivityIslandTaskEffectHost.swift`（完成光晕、完成描边、确认脉冲 `IslandConfirmationPulse`、边缘强调）
- `ActivityIslandEffects.swift`（`ActivityIslandTaskEffect` 包装）
- `ActivityIslandCompletionConfetti.swift`（完成彩屑）
- `RippleGlowOrb.swift`（紧凑态状态球）
- `ActivityIslandScrollingText.swift`（横向滚动文字）
- `ActivityIslandGlass.swift`（液态玻璃、`IslandNotchShape`、玻璃背板）
- `ActivityIslandMotion.swift` 中的 `ActivityIslandSurfaceMotion`（展开／收起曲线）。同文件的 `ActivityIslandPanelMetrics`／`ActivityIslandListLayout` 可按第 4.3 节调整尺寸。

挂载要求：

1. **焦点卡片**就是现在的"选中卡片"。它必须继续用 `.background { ActivityIslandTaskEffect(...) }` 挂载用户在设置里选的进度效果（`model.progressEffect`），条件与现在一致（`selected && (!isResult || phase == .completed)`），并继续传入 `replyCueActive`。
2. 待回复提示 `IslandReplyCue` 和 `claimReplyCue` 去重逻辑原样作用在焦点卡片和紧凑态上。
3. 紧凑态运行中仍显示 `RippleGlowOrb`；完成彩屑仍由 `completionBurstSerial` 触发，触发条件不变。
4. 焦点卡片和胶囊都使用 `.islandGlass(...)`，完成态的绿色 tint 保留。
5. Reduce Motion、`reduceMotionOverride`、`playbackVisible` 的门控对所有新视图同样生效。
6. 胶囊行是新增的轻量元素，**不挂载** Metal 效果，与现在的非选中卡片一致，只用状态色圆点表示状态。

如果实现中发现某个动效无法按原样挂载，停下来在交付报告里说明，不得自行删减。

## 3. 数据层改动

任务卡片直接呈现原有任务特效与玻璃材质，不在特效上叠加整卡黑色渐变遮罩；运行态与完成态使用相同规则。

### 3.1 步骤轨迹 `recentSteps`

- Codex 与 Claude Code 共用 `IslandStep` 状态和三节点选择规则：`done`／`running`／`waiting`／`failed`／`ended`。优先保留正在执行或等待的调用，再补最近结果；同一调用 ID 只显示一次。
- Codex 从当前 turn 的非 progress 活动生成节点；Claude 从当前轮次真实 Hook／转录工具事件生成节点。缺少工具证据时退回动作文字，不伪造进度百分比。
- 等待态只标记尚未结束的调用；新轮次清空旧步骤。同一轮稀疏刷新保留已有证据。
- 整轮完成、失败或取消时，保留已知成功／失败，只将未确认结果的运行／等待节点变为灰色“已结束”。整轮失败不再强制把最后一个节点标红；迟到的明确结果可以修正节点，但不重启完成回执计时。
- Codex 工具失败仅采信显式布尔错误标记或结构化执行结果的非零退出码，不按普通输出中的“error”文字猜测。
- 两端共用顶部状态文案、图标、颜色与运行节点动画；等待请求的操作入口仍按真实来源显示。
- `hidingDetails()` 清空步骤。无工具数据时不显示节点。

### 3.2 已完成会话保留 10 分钟

现在已完成行的保留时间等于 `completionHold`（`expandedHold + 6` 秒），这个期限同时驱动紧凑态回执和窗口生命周期。**不要直接把它改成 600 秒**。

- 在 `ActivitySessionState` 中把期限拆成两个：
  - `receiptDeadline`：保持现在的语义和数值，继续驱动 `compactReceipt`、紧凑态回执、自动收起。
  - `retentionDeadline`：结束时刻 + 600 秒，只决定该行是否还留在列表里。
- 新增参数 `retention: TimeInterval = 600`，由 `MonitorStore` 传入，常量放在 `ActivityIslandPreferences` 旁，不加设置项。
- 行上新增 `var isRetainedReceipt: Bool`：超过 `receiptDeadline`、但未超过 `retentionDeadline` 时为 true。
- 新 turn 覆盖旧回执的规则保持不变（`if let turn = local?.turnID, turn != previous.turnID { continue }`）。
- `failed`、`cancelled`、`ended` 行使用同样的 10 分钟保留。

`ActivityIslandWindowController.consume` 的语义要求：

- 保留期内的行（`isRetainedReceipt == true`）**不得**触发自动弹出、完成彩屑、完成光晕重播、`compactReceipt` 重建，也不得延长展开保持时间。
- 所有行都已结束时，`showsCompactQuota` 必须仍为 true，紧凑态显示额度横幅。这与 AGENTS.md 的空闲验收一致：不得出现"思考中"卡片或运行态动效。
- 手动展开时，保留行以结果样式出现在胶囊排和焦点卡中。

## 4. 视图层改动

### 4.1 展开态 `ActivityIslandExpandedList`

自上而下的结构：

1. **头部**：额度胶囊、置顶、收起按钮保持不变。
2. **焦点卡片** `ActivityIslandFocusCard`（新文件 `ActivityIslandFocusCard.swift`，可改造现有 `ActivityIslandTaskCard`；如果其他地方仍在用 `ActivityIslandTaskCard`，保留它）：
   - 第 1 行：状态图标（沿用现有符号、颜色、`replyCueActive` 缩放），标题，状态文字。
   - 第 2–4 行（运行中）：`recentSteps`，每行一个前导符号：done 用 ✓（secondary 色），running 用现有 accent 色，waiting 用橙色。**最后一行**（当前步）用 `IslandScrollingText` 横向滚动，最新助手进展 `actionText` 与当前步合并显示；其余步骤静态单行截断。`recentSteps` 为空时只显示一行 `runningDetail` 滚动文字，与现状一致。
   - 结果态：`耗时 · 本轮 N tokens`（沿用 `resultLine`），下面是步骤轨迹（保留已知结果，未确认结果为 ended）。
   - 底行 meta：模型名、运行时长、**本轮** tokens（`presentation.turnTokens`），不再显示累计。累计放进 `.help` 和 `accessibilitySummary`。
   - 待批准／待回复且为焦点时，`ActivityIslandApprovalCard` 仍紧跟在焦点卡片下方，测量和高度回报逻辑不变。
3. **胶囊排** `ActivityIslandSessionRail`：除焦点外的所有行，顺序沿用 `ActivitySessionState.rows`（待处理在前）。每个胶囊包含状态圆点、标题（截断）、运行时长或"完成"。点击调用现有 `onSelect`。超出宽度时横向滚动，不换行、不加"+N"。保留行使用较低的不透明度。
4. **底栏**：刷新、设置按钮和 `IslandSessionSummaryView` 保留，删除左侧重复的"N 个会话"文字。

焦点规则：焦点为 `focusedSessionID ?? ActivitySessionSnapshot.compactFocus(...)`。**新出现**的待批准／待回复请求抢占焦点（复用现有 `waitingApproval` 置前逻辑）。用户手动点了其他胶囊后，同一请求不再反复抢回焦点。

### 4.2 紧凑态 `ActivityIslandCompactContent`

- 左侧：状态球（`RippleGlowOrb`／符号）＋焦点会话当前步骤的横向滚动文字（`compactTitle` 改为当前步优先，没有步骤时回退原文案）。
- 右侧：有其他会话时，显示每个其他会话一枚状态色竖条（最多 6 枚，超出时显示 `+N`）；只有焦点会话时显示运行时长和本轮 tokens。
- 有硬件刘海（`hardwareGap > 0`）时，左右分栏逻辑不变。

### 4.3 尺寸 `ActivityIslandPanelMetrics`

- 列表区高度由"行数 × 62"改为：焦点卡片高度（运行中按步骤数 1–3 行计算，建议 3 步时约 112 pt）+ 胶囊排 30 pt（只有一个会话时为 0）+ 间距。
- 高度不再随会话数线性增长；批准卡片的额外高度继续通过 `approvalHeight(width:)` 叠加。
- `capacity`、`visibleRowCount` 相关逻辑如果失去意义，可以简化，但相关测试要同步更新，并说明原因。
- 窗口宽度、`expandedWidth` 偏好和 560–680 范围不变。

## 5. 不在本次范围

不改配色，不改额度胶囊和用量页，不改设置页，不加偏好项，不改 Codex 日志解析口径，不改审批协议，不碰 `~/.codex`、Hook 配置、账号和会话数据。

## 6. 测试

新增或更新以下测试，并接入 `scripts/test.sh`（已有的编译组如果漏了新文件，要补上）：

- `ActivitySessionStateTests`
  - 步骤生成：排除 progress、取最后 3 条、running／waiting 标记正确。
  - 同 turn 刷新不丢步骤；换 turn 清空。
  - 隐私模式清空步骤。
  - 回执期与保留期分离：`completionHold` 秒后 `isRetainedReceipt` 变为 true，600 秒后该行移除。
  - 新 turn 立即覆盖保留行。
- `ActivityIslandLifecycleTests`／窗口控制器相关测试
  - 保留行不触发弹出、彩屑或回执重建；全部结束时 `showsCompactQuota == true`。
- `ActivityIslandPanelTests`
  - 1 个会话、5 个会话、焦点待批准（含批准卡片）三种情况下的高度；5 个会话的高度不超过 1 个会话高度 + 胶囊排高度。
- 已有测试（`ActivityIslandPanelTests`、`IslandApprovalTests`、`RippleGlowRuntimeTests`、`ContinuityTests` 等）必须全部通过。如果某条断言因布局改变而失效，修改它并在报告中逐条说明。

## 7. 构建、安装与交付

按 AGENTS.md 的本机覆盖安装授权执行：

1. `scripts/test.sh` 全部通过。
2. `scripts/build-app.sh arm64`（Release，**只构建 arm64**，不做 Universal／DMG）。
3. 覆盖前只读核对源 App、目标 App、版本、架构、签名和运行进程，然后用 `scripts/install-app.sh` 备份到 `build/backups/` 并覆盖安装，启动应用。
4. 实机检查：
   - 单会话运行：焦点卡片显示步骤和当前步滚动，进度效果正常播放。
   - 至少 2 个会话：胶囊排出现，点击能切换焦点，进度效果跟着切到新焦点。
   - 待批准：抢占焦点，确认脉冲和批准卡片正常。
   - 完成：彩屑和完成光晕各只播放一次；约 9 秒后紧凑态回到额度横幅；手动展开仍能看到已完成胶囊；10 分钟后胶囊消失。
   - 打开 Reduce Motion：所有动效停止，布局不乱。
   - 隐私模式：不显示步骤。
5. 不提交、不推送。

### 交付报告必须包含

- 改动的文件清单，每个文件一句话说明。
- 第 2 节受保护文件未被修改的证明：这些文件原本就有未提交改动，所以不要用 `git diff`。在项目根目录运行 `cd Sources/CodexNotchMonitor && shasum -a 256 -c ../../build/island-focus-stage-baseline.sha256`。`ActivityIslandMotion.swift` 允许不一致，但只能改 Metrics／ListLayout，需在报告中贴出该文件的 diff。
- `scripts/test.sh` 的结尾输出和 Release 构建结果。
- 安装的 App 版本、架构、签名校验结果，以及精确的备份回滚路径。
- 第 7.4 节每一项的实机结果，标明"已验证"或"未验证及原因"。
- 截图存放在 `build/qa/island-focus-stage/`：单会话、多会话、待批准、全部完成。

## 可见性与小幅脉动

状态点透明度（1 ↔ 0.35）与运行步骤节点缩放（1 ↔ 1.15）使用原生 Core Animation，单程 1.2 秒，不通过 SwiftUI 状态驱动逐帧更新。非运行结果、减少动态效果、隐藏祖先或不可见窗口停止脉动。

展开／收起仍使用既有原生过渡；淡出完成后将非活动 NSHostingView 真正隐藏，保留宿主与回答草稿。快速反向切换通过每个宿主独立的代次标记作废旧隐藏回调，重新显示先解除隐藏。任务 Metal、角色帧动画与画质档位沿用现有行为。
