# 光眼球「软糖」重制施工方案

设计稿：https://claude.ai/code/artifact/8c051676-7822-460e-a957-b15f37e0e3d2 （方向 A · 软糖 Gummy）

先读 `AGENTS.md`、`docs/island-mascot.md`（现行角色方案）和 `docs/island-focus-stage.md` 第 2 节（受保护动效文件）。不提交、不推送、不安装。工作区里有其他未提交改动（IPC、审批相关），一律不碰。

## 1. 目标

保留现有角色的状态映射、配色、注视鼠标、一次性动作去重、可见性与 Reduce Motion 门控；只把"身体怎么动"换成软糖：身体会被挤压拉伸，带弹簧回弹和轻微表面晃动，眼睛有高光和眨眼回弹。

不变的部分（`docs/island-mascot.md` 中以下内容继续有效）：

- 第 3.1 节状态映射与配色、0.3 秒颜色过渡。
- 第 3.3 节注视鼠标（`IslandMascotContext`、`gazeOffset`、30 Hz 节流、可见时才安装监听）。
- 一次性动作去重：`claimCompletion`、`claimReply`、`claimFailure`、`IslandSessionMascot.update()` 的逻辑不改。
- 第 4 节接入点与尺寸（紧凑态 20 pt、额度分支 18 pt、焦点卡 26 pt）。
- 受保护文件哈希与 `build/island-focus-stage-baseline.sha256` 一致。

## 2. 纯函数姿态模型（必须可测、无状态）

不要在 `TimelineView` 里逐帧写 `@State` 或积分。用解析式的阻尼弹簧，把每次"冲击"的响应叠加起来，这样视图重建、隐藏再显示都不会出现跳变，也便于测试。

新增：

```swift
struct IslandMascotGummyPose: Equatable {
    var squashY: CGFloat      // 纵向比例 sy，1 为原状
    var squashX: CGFloat      // 1 + (1 - sy) * 0.9，近似保体积
    var lean: CGFloat         // 顶部相对底部的水平偏移，单位为半径 R
    var lift: CGFloat         // 整体上移（负数向上），单位为 size
    var shakeX: CGFloat       // 单位为 size
    var tiltDegrees: Double   // 绕底部中心旋转
    var wobble: CGFloat       // 表面晃动幅度系数，0 表示正圆
    var eyeLagY: CGFloat      // 眼睛二次运动，单位为 R
    var eyeOpen: CGFloat      // 眨眼开合，含回弹，可略大于 1
    var eyeOffset: CGSize     // 表情自带偏移，单位为 R
    var orbit: (x: CGFloat, y: CGFloat, z: CGFloat)?  // think 光点，z < 0 表示在身后
}
enum IslandMascotGummy {
    static func pose(mood: IslandMascotMood, time: TimeInterval, oneShot: IslandMascotOneShot,
                     blinkStartedAt: Date?, now: Date, animated: Bool, reduceMotion: Bool) -> IslandMascotGummyPose
}
```

（`orbit` 若因 Equatable 不便，可改成独立的小结构体。）

### 2.1 弹簧

- 阻尼弹簧参数：刚度 320、阻尼 7.5（单位质量），即 ω₀ ≈ 17.9、ζ ≈ 0.21、ωd ≈ 17.5。
- 一次速度冲击 v 在 τ 秒后的位移：`v / ωd · e^(−ζω₀τ) · sin(ωd τ)`；速度用其导数。
- 某状态的 `squashY = 目标值 + Σ 最近 1.2 秒内各冲击的位移`。冲击时间由周期相位或一次性动作的起始时间推出（见下表），不保存历史。
- `lean` 用同样方法：刚度 120、阻尼 10，仅受目标值变化影响时用 0.3 秒 ease 过渡即可。
- `wobble = 0.35 + min(2.2, |sy 速度| × 1.1)`；**idle 与 Reduce Motion 时为 0**。
- `eyeLagY = clamp(sy 速度 × 0.03, −0.12, 0.12)`。
- 切换表情时 `squashY` 目标值随颜色一起 0.3 秒过渡，不得跳变。

### 2.2 各表情

时间 t 为全局时钟；el 为一次性动作开始后的秒数；R = size / 2。

| 表情 | 目标 squashY | 冲击 | 其他 |
|---|---|---|---|
| think | `1 + 0.035·sin(2πt/3.2)` | 无 | lean 目标 `0.08·sin(2πt/3.6)`；整体上下漂浮 `sin(2πt/1.8)·0.025 size`；眼睛偏移 `(0.10 + 0.08·sin(2πt/3.6), −0.10) R`；光点沿 3D 椭圆环绕：角度 `2πt/2.4`，x = `cos·1.32R`，y = `sin·0.34R − 0.12R`，z = sin，z < 0 时画在身体之前（被挡住）且透明度 0.6 |
| tool | 1.05 | 每 0.62 s 落地一次，冲击 −2.6 | 小跳步：lift = `−sin(π·p)·0.08 size`，p 为 0.62 s 周期相位；眯眼 0.45；眼睛下移 0.04R；`size ≥ 24` 时每次落地在底部两侧溅出两颗白色小火花（0.42 s 内抛物线消失），小于 24 pt 不画。去掉原来的旋转光弧 |
| approve | 1.05 | 每 1.4 s 一次，冲击 +2.0，与光环扩散同步 | 圆眼；外圈琥珀光环保留 |
| reply | 1 | 一次性开始时冲击 +2.2 | 绕底部倾斜 −9°；"?" 浮动保留现有 `claimReplyCue` 逻辑 |
| done | 一次性：el < 0.16 为 0.76（下蹲）；0.16–0.62 为 `1.16 − 0.14q`（拉伸起跳）；之后为 1 | el = 0.62 落地冲击 −3.6 | 弯月笑眼；起跳 lift = `−sin(πq)·0.24 size`，q = (el − 0.16)/0.46；彩点 5 颗在 el ≥ 0.2 时从头顶抛出，沿用现有颜色与时长；回弹结束后保持静止 |
| fail | 0.9（泄气） | 无 | 叉眼，不跟随鼠标；一次性：el < 0.5 时 shakeX = `sin(el·52)·(1 − el/0.5)·0.08 size`；el 0.3–1.9 秒右上侧有一滴浅蓝冷汗沿身体滑下并淡出 |
| idle | `0.95 + 0.035·sin(2πt/5)` | 无 | 闭眼弧线；lean 0，wobble 0；不得出现光点、光弧、火花或任何运行态动效 |

没有一次性动作（`oneShot.kind == .none`，例如重建视图、隐藏后恢复、保留的完成回执）时，done／fail／reply 直接显示终态静止姿态，不播放下蹲、起跳、甩头、冷汗。

### 2.3 眨眼

think、tool、approve、reply 每 3–6 秒随机一次，曲线（x 为开始后秒数）：0–0.07 s 从 1 线性到 0.1；0.07–0.15 s 从 0.1 到 1.15；0.15–0.22 s 回到 1。沿用 `IslandMascotBlink` 的计时，只把开合曲线改为上述回弹（可以让 Blink 发布开始时间，而不是布尔值）。tool 眨眼乘在 0.45 眯眼上。

### 2.4 Reduce Motion 与隐藏

`animated == false` 或 `reduceMotion == true`：t 固定为 0，无冲击、无 wobble、无光点、无火花、无眨眼、无注视，只显示各表情的静态目标姿态与颜色。`TimelineView` 暂停。

## 3. 绘制

在 `IslandMascotView` 内用 SwiftUI `Canvas`（放在现有 `TimelineView` 里）绘制，视图不得引用 `RippleGlowOrb`。

- **身体**：72 个点的闭合路径，半径 `r(θ) = R·(1 + wobble·0.028·(sin(3θ + 2.3t) + 0.7·sin(2θ − 1.7t + 1.3)))`。每个点先乘 `(squashX, squashY)`，以底部为锚点（底部不动），再加 lean：`x += lean·R·(R − y·squashY)/(2R)`（顶部偏移约 lean·R，底部为 0），然后绕底部中心旋转 tilt，最后加 lift、shakeX。
- **填充**：径向渐变，起点在变换后的 (−0.30R, −0.40R)，白色（0.88 不透明度）→ 中间色（42%）→ 外圈色（100%），半径 1.06R。外发光：同色 0.34 不透明度、从 0.6R 淡出到 1.8R 的径向渐变，画在身体之前。
- **镜面高光**：变换后的 (−0.36R, −0.52R) 处一个白色椭圆，半轴 0.17R × 0.085R，旋转 −0.6 rad，不透明度 0.42，宽度随 squashX 缩放。
- **眼睛**：深色 `#1A1238`，宽 0.22R、高 0.42R，中心 (±0.30R, −0.02R)，加上表情偏移、注视偏移（x 0.13R、y 0.10R 为满量程，沿用现有 `gaze` 换算）和 eyeLagY；整体随身体同一变换（含 squash 与 tilt）。`size < 22` 时眼睛放大 1.15 倍。胶囊眼与圆眼在开合 > 0.55 时左上角加白色高光点（直径 0.4 × 眼宽，0.92 不透明度）。闭眼、笑眼、叉眼的线宽 `max(1.3, 0.10R)`，圆头。
- **画布范围**：允许绘制超出 `size` 方框（起跳、彩点、光点），但不得改变布局尺寸；用 `.frame(width: size, height: size)` 占位，Canvas 放在略大的 overlay 中，`allowsHitTesting(false)`。

## 4. 测试

更新 `Tests/IslandMascotTests.swift`，保留现有映射、注视、去重、监听相关断言；删除只针对旧呼吸缩放／旋转光弧的断言，并新增：

- Reduce Motion 与 `animated == false`：各表情姿态与 t 无关、wobble 为 0、无 orbit、eyeOpen 为 1。
- idle：wobble 为 0，无 orbit；squashY 只在 0.915–0.985 内变化。
- tool：落地后约 0.09 s（1/4 个 ωd 周期）squashY 明显小于 1.05；lift 在相位中点最大，绝对值 ≤ 0.08 size。
- done：oneShot 为 done 时 el = 0.1 的 squashY < 0.85，el = 0.39 的 lift < 0；el = 0.7 有落地压扁；el > 2 回到静止（squashY ≈ 1、wobble ≈ 0.35 以内）；oneShot 为 none 时始终为静止终态。
- fail：shakeX 只在 el < 0.5 非零；fail 不跟随注视。
- 体积关系 `squashX == 1 + (1 − squashY)·0.9`；底部锚点：任意姿态下变换后的底部点 y 不随 squashY 改变（lift、shake 之前）。
- 弹簧解析式：单次冲击在 1.2 s 后响应 < 0.01。
- 眨眼曲线端点与回弹峰值 1.15。
- 视图树中没有 RippleGlowOrb（沿用现有断言）。

## 5. 范围与验证

只改 `Sources/CodexNotchMonitor/ActivityIslandMascot.swift`、`Tests/IslandMascotTests.swift`，确有必要时改 `scripts/test.sh`。不改 `ActivityIslandView.swift`、`ActivityIslandFocusCard.swift` 的接入方式，除非尺寸或 overlay 无法在角色文件内解决，并在报告里说明。

交付前：运行能在沙箱中运行的测试、`scripts/build-app.sh arm64`，校验受保护文件 SHA-256 与基线一致，报告逐条列出未能执行的测试组。
