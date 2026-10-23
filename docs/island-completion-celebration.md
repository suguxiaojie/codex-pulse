# 会话完成：加大礼花与完成提示音 施工方案

先读 `AGENTS.md`、`docs/island-focus-stage.md` 第 2 节、`docs/island-alert-completion.md`。不提交、不推送、不安装。

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 礼花 | 加大：发射时间更长、片数更多、尺寸更大、落得更远；设置里新增「礼花强度」：轻／标准／热烈 |
| 提示音 | 会话完成时播放 macOS 自带的短提示音，可关闭、可选音色 |
| 受保护文件 | 用户本次明确授权修改 `ActivityIslandCompletionConfetti.swift`。其余受保护文件仍然不得修改。完成后更新 `build/island-focus-stage-baseline.sha256` 中该文件的哈希，并在报告里贴出 diff 和新哈希 |

## 2. 现状

- 两个点状发射器分别位于刘海左下角和右下角，发射 0.16 秒，5 种颜色、每种 birthRate 55，寿命 1.6 秒，2.2 秒后清理。礼花画在灵动岛面板自己的 layer 里，可见范围只有刘海附近，所以很容易被忽略。
- 触发条件：`ActivityIslandWindowController.consume` 中 `newlyCompleted` 使 `completionBurstSerial += 1`。触发条件不改。

## 3. 礼花

- 新增一个专门画礼花的透明覆盖窗口，不改灵动岛面板的尺寸和形状：
  - 窗口属性：borderless、`ignoresMouseEvents = true`、不成为 key、`.canJoinAllSpaces`／`.fullScreenAuxiliary`，层级与灵动岛面板相同或略高；
  - 位置与大小：放在灵动岛所在屏幕，宽度为屏幕宽，高度为屏幕高的 40%，顶部对齐；
  - 显示时机：只在礼花播放期间显示，结束后 `orderOut`。
- 礼花发射点仍在刘海两侧，向斜下方喷出，受重力下落；花片要能落到屏幕上方大约三分之一处。
- 三档参数：
  - **轻**：和现在完全一致（0.16 秒、birthRate 55、velocity 155、scale 0.75、寿命 1.6 秒），并且仍画在原面板里，不使用覆盖窗口；
  - **标准（默认）**：发射约 0.5 秒，birthRate 约 90，velocity 约 320，寿命约 2.6 秒，scale 约 1.0，增加 yAcceleration 重力和 spin；
  - **热烈**：发射约 0.8 秒，birthRate 约 140，velocity 约 420，寿命约 3.2 秒，scale 约 1.2；颜色增加完成绿 `#4CD47A`。
- 清理时间随寿命延长；`isActive` 的语义保持“礼花仍在播放”（`docs/island-alert-completion.md` 依赖它让提醒卡排队）。
- 打开“减弱动态效果”（系统设置或 `reduceMotionOverride`）时，不播放礼花（与现在一致）。灵动岛不可见或已关闭时也不播放。
- 礼花强度存为新的偏好键，例如 `activityIsland.confettiIntensity`，放进 `ActivityIslandPreferences`，并在灵动岛设置里加一个三档分段控件。

## 4. 完成提示音

- 触发：与 `completionBurstSerial += 1` 相同的时机。冷启动基线（baseline）不响。2 秒内多个会话完成只响一次。
- 用 `NSSound(named:)` 播放系统自带音色。可选：Glass（默认）、Hero、Ping、Purr、Submarine。音量约 0.7，跟随系统输出音量。
- 设置：灵动岛设置里新增「完成提示音」开关（默认开启）和音色选择器；选择音色时试听一次。新偏好键例如 `activityIsland.completionSound`、`activityIsland.completionSoundName`。
- 提示音不受“减弱动态效果”影响。灵动岛被关闭时不响。
- 不检测勿扰／专注模式（没有可靠的公开 API）；在设置说明里写明“跟随系统音量”。

## 5. 测试

- 偏好：默认值（标准、开启、Glass）、读写往返、旧配置缺键时取默认值。
- 礼花参数：三档参数表是纯函数，轻档与原参数完全一致。
- 提示音节流（纯函数）：2 秒内两次完成只响一次；baseline 不响；关闭开关后不响。
- 受保护文件：除 Confetti 外，哈希与基线一致；Confetti 的新哈希写入基线。
- 运行完整测试（`SKIP_COST_SMOKE_TESTS=1`）与 arm64 Release 构建；中文报告。
