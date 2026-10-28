# 灵动岛材质：硬件黑＋边缘光 施工方案

设计稿：https://claude.ai/code/artifact/b6274fcd-26ab-43d7-8a65-5792bf00a0fa （方向 A）

先读 `AGENTS.md`。不提交、不推送、不安装。

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 岛体 | 与刘海完全相同的纯黑（`#000`），紧凑态与展开态一致 |
| 顶部 | 保留 `IslandNotchShape` 现有的内凹上角（lip），不改形状算法 |
| 边缘光 | 沿岛体底边和两侧的极细光，颜色跟随焦点任务状态 |
| 投影 | 岛体下方一层大而柔的投影 |
| 原"玻璃程度" | 改名为"边缘光强度"，沿用原偏好键 `activityIsland.glassDegree`，用户已保存的值继续生效 |

## 2. 动效保护（重要）

- 以下文件仍然**不得修改**，哈希须与 `build/island-focus-stage-baseline.sha256` 一致：`ActivityIslandStateSmoke.swift`、`ActivityIslandTaskEffectHost.swift`、`ActivityIslandEffects.swift`、`ActivityIslandCompletionConfetti.swift`、`RippleGlowOrb.swift`、`ActivityIslandScrollingText.swift`。
- `ActivityIslandMotion.swift` 中的 `ActivityIslandSurfaceMotion`（展开／收起曲线）**不得修改**。新的纯黑形状沿用原曲线，与原几何同步连续变形。
- `ActivityIslandGlass.swift` 本轮**允许修改**，但只能改材质、背板和形状描边相关的代码（`IslandExpandedGlassBackdrop`、`IslandGlassSurface` 的岛内用法、`IslandGlassChrome` 等），不得改动其中任何动画时长、曲线或 `IslandGlassGeometry` 的时序逻辑。完成后在报告里贴出该文件的 diff，并更新基线：`build/island-focus-stage-baseline.sha256` 中该文件的哈希换成新值，同时在报告里写明新哈希。
- 焦点卡背后的 Metal 进度效果、彩屑、确认脉冲、光眼球角色、待回复提示全部保留，层级不变：效果在卡片底色之上、文字之下。

## 3. 岛体背板（替换 `IslandExpandedGlassBackdrop` 的视觉）

- **填充**：用 `IslandNotchShape` 填纯黑。去掉 `glassEffect(.clear)` 和 `ActivityIslandGlassDegree.gradientStops` 黑色渐变；紧凑态与展开态都是纯黑，不再需要 `value.compact` 的黑色覆盖层。
- **边缘光**：
  - 同一 `IslandNotchShape` 描边两层：核心线 1 pt，外晕线 6 pt 加约 4 pt 模糊。
  - 颜色取焦点行的光眼球颜色（`IslandMascotMood` 的中间色）：思考 `#9AA8FF`、工具 `#62D0FF`、待批准／待回复 `#FFB340`、完成 `#4CD47A`、失败 `#FF5A4E`。
  - 空闲（额度分支）用 `#A2A8B6`，强度减半，并且**完全静态**，不呼吸、不流动。
  - 用自上而下的遮罩：顶部 30 pt 内从 0 渐变到 1，保证边缘光不碰菜单栏和刘海接缝。
  - 状态切换时颜色 0.3 秒过渡；Reduce Motion 下直接切换。
  - 强度：核心线不透明度 = `glassDegree × 1.25`（取值 0.25–1.0，默认约 0.56），外晕不透明度 = 核心 × 0.5。紧凑态的强度再乘 0.6。
- **投影**：岛体下方投影，偏移 y 18、模糊 40、黑色 50%；紧凑态用偏移 y 6、模糊 14、黑色 35%，与形状同步变化。
  - 窗口底部需要为投影留出空间。新增的透明边距**必须让鼠标事件穿透**，不得遮挡下方窗口的点击和悬停；沿用现有的命中区域逻辑，只扩大绘制区域，不扩大交互区域。
- **降低透明度**：本来就不透明，保持纯黑；边缘光照常显示。

## 4. 岛内表面

- 焦点卡（`ActivityIslandFocusCard`）、紧凑卡片（`ActivityIslandView` 第 538 行附近）：
  - `islandGlass` 改为不透明深灰 `#121215`。
  - 顶边加 0.5 pt、白色 7% 的高光，外圈 0.5 pt、白色 5% 的描边。
  - 完成态保留现有的微绿底色：`#0F1A13`。
  - Metal 效果仍然绘制在卡片底色之上。
- 会话胶囊（rail）、审批卡（`ActivityIslandApprovalCard`）、页眉额度胶囊、圆形图标按钮（`IslandGlassChrome`）：统一改为不透明的深灰或白色 10% 填充，加 0.5 pt 细描边，不再使用玻璃。
- 用量页（`ActivityIslandUsageDashboard`、`IslandUsageSections`、`IslandDashboardResetActionStyle`）在岛内显示，同样改为不透明深灰，保持整体统一。
- `GlanceWeatherViews.swift` 是菜单栏玻璃面板，**不在本次范围**，不得修改。

## 5. 设置

- `QuotaStyleSettingsView` 中原"玻璃程度"滑块改名为"边缘光强度"。
  - 现在滑块显示的是 `1 - glassDegree`，改为直接显示 `glassDegree`：20%–80%，向右更亮。
  - 原来的反向映射要去掉；存储的值不变，含义改为强度。
  - 加一行说明："岛体为纯黑；边缘光颜色跟随任务状态"。
- 设置页里的预览同步改为纯黑加边缘光。
- "液态玻璃／经典纯色"材质选项和"浅色／深色／自动"外观选项：岛体不再受它们影响。如果它们仍作用于悬浮额度胶囊等岛外元素，就保留，并把说明文字改为只描述这些元素；如果改后已没有任何作用，在报告里说明，暂不删除，由 Claude 决定。

## 6. 测试

- 边缘光颜色映射（7 种表情加空闲）和强度换算（0.2、0.45、0.8，紧凑态系数）用纯函数测试。
- 设置滑块的显示值与存储值：确认旧值 0.45 读出后显示为 45%，强度为 0.56。
- 命中区域：投影边距不改变可交互区域（沿用现有的面板命中测试）。
- 现有面板、审批、角色测试全部通过；因材质变化失效的断言逐条说明。
- 跑沙箱能跑的测试和 `scripts/build-app.sh arm64`，报告中逐条列出因沙箱无法执行的测试组。

## 7. 范围

只改：
- `ActivityIslandGlass.swift`（限第 2 节允许的部分）
- `ActivityIslandPanel.swift`
- `ActivityIslandFocusCard.swift`
- `ActivityIslandView.swift`
- `ActivityIslandApprovalCard.swift`
- `ActivityIslandUsageDashboard.swift`
- `IslandUsageSections.swift`
- `IslandDashboardResetActionStyle.swift`
- `QuotaStyleSettingsView.swift`
- `ActivityIslandPreferences.swift`（只改注释或标题，不改键）
- `ActivityIslandMascot.swift`（只暴露颜色）
- 对应测试和 `scripts/test.sh`
