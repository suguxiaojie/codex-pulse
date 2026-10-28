# 灵动岛状态角色「光眼球」施工方案

设计稿：https://claude.ai/code/artifact/d9df9612-ed53-49db-86d5-39cedbabf602 （方向 A）

先读 `AGENTS.md` 和 `docs/island-focus-stage.md` 第 2 节（受保护动效文件）。不提交、不推送、不安装。

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 形象 | A 光眼球：发光球体加一双深色胶囊眼睛，原创 |
| 位置 | 紧凑态的状态球位置，以及展开焦点卡左上的状态图标位置 |
| 注视 | 鼠标靠近刘海时，眼睛跟随鼠标 |
| 设置 | 直接替换，不加"换回状态球"的开关 |
| 许可 | 不使用 aora-bot 的任何代码、数据或形象 |

## 2. 硬性约束

- `RippleGlowOrb.swift` 等受保护文件不改；它们的 SHA-256 必须与 `build/island-focus-stage-baseline.sha256` 一致（`ActivityIslandMotion.swift` 除外）。
- 用户更新决策：全部 7 种表情统一使用角色自己的 SwiftUI 渐变球体，角色不再引用 `RippleGlowOrb`。`RippleGlowOrb.swift` 文件及其运行时测试仍保留，哈希须与基线一致。
- 焦点卡背后的进度效果（StateSmoke 等）、完成彩屑、确认脉冲、待回复提示的去重逻辑全部保留。
- 空闲状态不得出现运行态动效（见 AGENTS.md 中的空闲验收）。

## 3. 新文件 `ActivityIslandMascot.swift`

### 3.1 状态映射（纯函数，可测）

```swift
enum IslandMascotMood { case think, tool, approve, reply, done, fail, idle }
static func mood(for row: ActivitySessionSnapshot?) -> IslandMascotMood
```

| 输入 | 表情 |
|---|---|
| `.starting`、`.working` | `think` |
| `.usingTool` | `tool` |
| `.waitingApproval` 且 `waitReason == .userInput` | `reply` |
| `.waitingApproval`（其他） | `approve` |
| `.completed` | `done` |
| `.failed` | `fail` |
| `endReason == .cancelled`、`.ended`、无会话 | `idle` |

颜色（球体渐变的中间色与外圈色）：

| 表情 | 中间色 | 外圈色 |
|---|---|---|
| think | `#9AA8FF` | `#4B3CB0` |
| tool | `#62D0FF` | `#1D5F9A` |
| approve、reply | `#FFB340` | `#A8520E` |
| done | `#4CD47A` | `#16733A` |
| fail | `#FF5A4E` | `#8E1C16` |
| idle | `#A2A8B6` | `#3C4150` |

切换表情时，颜色用 0.3 秒过渡。

### 3.2 视图 `IslandMascotView(mood:size:animated:reduceMotion:gaze:oneShot:)`

- **球体**：
  - 全部 7 种状态：用 SwiftUI 画一个球体，使用第 3.1 节各状态配色，样式为径向渐变（高光点在左上 36%/30%，白色→中间色→外圈色），再加同色、约 0.35 不透明度的模糊外发光。
  - 表情切换时渐变颜色在 0.3 秒内过渡，尺寸保持一致。think／tool 球体以约 3.2 秒周期、3.5% 幅度呼吸缩放。
- **眼睛**：深色（`#1A1238`）胶囊。以 100 为基准：每只宽 9、高 17，左右眼中心 x 为 39.5 和 60.5，y 为 50。按 `size` 等比缩放；`size` 不足 22 pt 时，眼睛额外放大 1.15 倍，保证可读。

各表情的眼睛和动作（"一次性"表示只在进入该状态时播放一次）：

| 表情 | 眼睛 | 动作 |
|---|---|---|
| think | 向右上偏移 | 约 3.6 秒缓慢左右张望；直径约球径 8% 的白色光点沿外缘以约 2.4 秒周期匀速环绕 |
| tool | 纵向压扁到 45%，眯眼 | 球体内约 90° 的白色半透明光弧以约 1.1 秒周期匀速旋转，线宽约球径 3.5%，透明度 0.75 |
| approve | 变成圆眼 | 外圈琥珀光环，每 1.4 秒扩散一次 |
| reply | 头部倾斜 −9° | 右上角出现"?"，轻轻上下浮动；一次性，接入现有 `claimReplyCue`，播放后保持静态倾斜 |
| done | 弯月笑眼 | 蹦一下并撒 5 颗彩点；一次性，和完成彩屑同步，用同一个 `completionBurstSerial` 驱动，不得重播 |
| fail | 叉眼 | 左右晃一下；一次性 |
| idle | 闭眼弧线 | 约 5 秒的缓慢呼吸缩放（幅度 3.5%）；不显示"z"，不出现任何运行态动效 |

- **眨眼**：think、tool、approve 状态下，每 3–6 秒随机眨一次，持续约 0.15 秒，带一点回弹；tool 的眨眼缩放乘在 45% 眯眼比例上，幅度相应缩小。
- **Reduce Motion**：只显示静态表情和颜色，不眨眼、不浮动、不追随鼠标，一次性动作也不播放。
- **可见性**：`playbackVisible == false` 或岛被隐藏时，停止所有计时器和动画，TimelineView 必须暂停。

### 3.3 注视鼠标

- 只在岛可见、`playbackVisible` 为真、且没有开启 Reduce Motion 时启用。
- 用 `NSEvent.addLocalMonitorForEvents` 和 `addGlobalMonitorForEvents(.mouseMoved)`，节流到 30 Hz，读取 `NSEvent.mouseLocation`。**不得使用需要辅助功能权限的 API**；如果全局监听拿不到事件，就退化为只追随本应用窗口内的鼠标。
- 纯函数 `gazeOffset(pointer:islandRect:) -> CGSize`：
  - 鼠标距离岛的外接矩形不超过 240 pt 时，眼睛朝鼠标方向偏移，最大偏移为眼宽的 35%。
  - 超过 240 pt 时偏移归零。
  - 偏移用弹簧动画平滑（response 约 0.35）。
- 注视偏移叠加在表情自带的偏移之上，tool 眯眼照常跟随，只有 fail 的叉眼不跟随。
- 监听只在可见时安装，隐藏时移除，不能常驻。

## 4. 接入点

- `ActivityIslandCompactContent.symbol`：替换为 `IslandMascotView`，尺寸 20 pt，放在原来 30 pt 宽的位置里。保留 `replyCueActive` 的放大效果。
- `ActivityIslandCompactQuotaContent`（空闲时的额度分支）：在额度百分比左侧加一个 18 pt 的 idle 表情。
- `ActivityIslandFocusCard` 左上的状态图标（28×28 的 ZStack）：替换为 26 pt 的 `IslandMascotView`。保留原来的选中底色、`replyCueActive` 缩放和无障碍文字。
- `ActivityIslandSessionRail` 的胶囊只保留小圆点，不放角色。
- 隐私模式下表情照常显示，因为表情不包含任务信息。

## 5. 测试

新增 `Tests/IslandMascotTests.swift`（或并入面板测试），并接入 `scripts/test.sh`：

- 状态映射覆盖第 3.1 节的每一行。
- `gazeOffset`：鼠标在中心时偏移为零、边界距离、超出 240 pt 时归零、最大偏移被截断、鼠标在岛内部。
- 一次性动作：同一个 `completionBurstSerial` 和同一个回复请求只触发一次，重建视图后不重播。
- Reduce Motion 下不安装鼠标监听、不启动计时器。
- 隐藏后移除监听。
- think／tool 使用角色自己的 SwiftUI 球体，视图树中没有 RippleGlowOrb；覆盖环绕／旋转周期、呼吸幅度、tool 注视与眨眼比例，以及隐藏／Reduce Motion 下的静态参数。
- 受保护文件的哈希校验结果写进报告。

跑沙箱能跑的测试和 `scripts/build-app.sh arm64`，报告中逐条列出因沙箱无法执行的测试组。

## 6. 范围

只改新文件 `ActivityIslandMascot.swift`、`ActivityIslandView.swift`（紧凑态与额度分支）、`ActivityIslandFocusCard.swift`，以及对应测试和 `scripts/test.sh`。确有必要时，可以改 `ActivityIslandWindowController.swift` 来传递可见性和岛的位置。
