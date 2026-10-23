# 灵动岛提醒卡：方向 A「展开卡」施工方案

设计方向：A，灵动岛内展开提醒卡。

先读 `AGENTS.md`、`docs/system-notifications.md`、`docs/island-focus-stage.md` 第 2 节。不提交、不推送、不安装。

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 样式 | A 展开卡：岛体向下展开成完整卡片，带操作按钮，8 秒倒计时，悬停暂停，结束后收回 |
| 系统通知 | 与岛内提醒同时发送。岛内提醒本身不播放声音 |
| 触发 | 与 `docs/system-notifications.md` 相同：新的关注信号、额度跳到 100%、确认后原位更新 |
| 开关 | 复用「关注信号提醒」「额度恢复提醒」两个开关。关闭后岛内提醒和系统通知都不发 |

## 2. 硬性约束

- `build/island-focus-stage-baseline.sha256` 中列出的文件一律不改，完成后哈希必须一致（用 `shasum -a 256` 校验并写进报告）。展开／收起继续使用 `ActivityIslandSurfaceMotion` 现有曲线。
- 焦点卡的进度效果、彩屑、确认脉冲、光眼球、待回复提示，以及它们的去重逻辑全部保留。
- 空闲验收：提醒卡收回后回到常驻额度／空闲横幅，不得留下运行态动效或虚假任务。
- 灵动岛被关闭（hidden）或用户关闭了灵动岛时，不显示岛内提醒，只发系统通知。

## 3. 数据与调度

- 新增值类型 `IslandAlert`：`id`（与系统通知 identifier 相同）、`kind`（`.tiboSignal` / `.quotaRecovery`）、`title`、`subtitle`、`body`、`isPendingSource`（来源确认中）、`actions`（与系统通知 category 的动作一致，顺序为：次要动作在前，主动作在后）。由 `SystemNotificationContent` 构造：在同一处生成，岛内提醒和系统通知的文案保持一致。
- `MonitorStore` 在调用 `quotaResetNotifier.notify(...)` 时，同时把 `IslandAlert` 推给灵动岛（例如新增 `@Published var islandAlert` 或回调，跟随现有 store → island 的传递方式）。
- 队列（纯函数，可测）：
  - 有待批准、待回复任务（`requiresAttention`），或审批卡正在显示时，提醒排队，岛体空出来后再显示。
  - 同一 `id` 的新内容（原位更新）：如果该提醒正在显示，就直接替换文字，不重新计时；如果在排队，就替换排队里的条目；如果已经显示过，就不再弹出。
  - 队列最多 3 条，超出时丢弃最旧的一条（系统通知仍在）。
- 显示时长 8 秒；鼠标悬停期间暂停，移出后剩余时间继续走。点「×」或点任一动作后立即收回。

## 4. 视觉（照设计稿 A）

- 岛体：沿用现有硬件黑 `IslandNotchShape` 与展开曲线，提醒卡尺寸约 380×156 pt，大圆角跟随现有展开态。
- 边缘光颜色：关注信号用工具青 `#62D0FF`（对应 `IslandMascotMood.tool`），额度恢复用完成绿 `#4CD47A`（对应 `.done`）。
- 左侧放 30 pt 的 `IslandMascotView`，mood 按上面对应；遵守 reduceMotion 设置。
- 文字：标题 14 pt 粗体，副标题为等宽小字，用 50% 白；正文 12 pt，用 78% 白，最多 2 行，超出部分截断。来源确认中时，在标题后加琥珀色 `#FFB340` 小胶囊「确认中」。
- 操作按钮放在右下，用胶囊样式；主动作填充边缘光颜色、文字为黑色，次要动作用 8% 白底。右上角放一个淡色「×」。
- 底部 2 pt 倒计时细线，颜色同边缘光，从满宽线性缩到 0；悬停时停住。

## 5. 动作

与系统通知相同，并复用已有的路由（`SystemNotificationAction` 和 store 的 `onOpenNotificationCenter`／`confirmUserQuotaReset`）：

- 「在动态中心查看」「查看重置记录」：打开动态中心。
- 「打开原帖」：打开 sourceURL。
- 「标记为手动重置」：按 notificationID 确认。确认后系统通知和岛内提醒（如果还在显示）都原位更新。
- 点卡片空白处：打开动态中心。

## 6. 测试

- 新增 `Tests/IslandAlertTests.swift`（加入 `scripts/test.sh`）：
  - 队列在有 attention 时排队，attention 解除后才出队；
  - 原位更新的三种情况；
  - 队列上限；
  - 悬停暂停后的剩余时间计算；
  - 关闭开关后不产生提醒。
- 空闲验收：提醒结束后的状态与提醒出现前一致（presentation、expansion），不出现运行态。
- 跑完整 `scripts/test.sh` 和 arm64 Release 构建；受保护文件哈希与基线一致。
- 报告用中文，写明改动文件、取舍和测试结果。


## 7. 本轮实现与验证记录

记录时间：2026-10-24 01:42（北京时间）。

实现文件：

- `IslandAlert.swift`：提醒值类型、共享动作路由类型和可注入时间的纯值队列。
- `SystemNotificationContent.swift`：从同一通知内容生成提醒，保持 identifier、文案、原帖地址和动作顺序一致。
- `MonitorStore.swift`：在现有通知发送路径同步发布提醒，共用手动确认路由。
- `IslandAlertCard.swift`：展开卡、工具青／完成绿光眼球与边缘光、确认中胶囊、操作按钮、关闭按钮和倒计时线。
- `ActivityIslandView.swift`、`ActivityIslandWindowController.swift`、`ActivityIslandPanel.swift`：展示覆盖层、审批优先调度、真实指针悬停、尺寸和现有曲线接入。
- `Tests/IslandAlertTests.swift`、`Tests/SystemNotificationTests.swift`、`scripts/test.sh`：队列和内容一致性回归，提供 `SKIP_COST_SMOKE_TESTS=1` 开关。
- `README.md`、`ROADMAP.md`：功能说明与验证状态。

实现取舍：

- 提醒不向任务生命周期注入虚假任务或展开事件，展示结束后恢复任务系统当前 presentation／expansion。空闲时恢复常驻额度横幅；期间若真实任务发生变化，以真实任务状态为准。
- 进行中的提醒遇到审批时暂停并归队，审批解除后继续剩余时间。队列最多 3 条，丢弃最旧条目；已结束／关闭／溢出的 ID 不再次弹出。
- 内容区约 380×156 pt；硬件刘海屏额外预留顶部避让高度。原生窗口固定画布保持不变，只改变岛体轮廓。
- 提醒期间暂时隐藏悬浮额度胶囊；结束后按原有偏好恢复。确认动作关闭当前卡，系统通知的确认仍可对显示中的卡原位更新，且不重置倒计时。
- 通过独立 backdrop 包装调用现有硬件黑和动效实现，不改受保护文件。
- 设计稿链接返回“Sign in to view this page”，按本文文字规格实现；未完成与设计稿逐像素比对及真机视觉／鼠标／VoiceOver 验收。

验证证据位于 `.tmp/island-alert-card/`。执行完整测试入口后，对被前置失败阻断的组用临时续跑脚本逐组执行；不修改断言、不把失败计为通过。

- 新增队列测试通过：attention 排队／抢占、三种原位更新、上限、悬停剩余时间、显式关闭、关闭开关、hidden 丢弃和空闲恢复。
- 系统通知内容与动作一致性测试、额度恢复 18／18 通过。
- 通过：数字格式 71、气象 3,508、日志读取 13、分析展示、模型 123、会话状态 148、原生活动 57、Metal 状态球、生命周期 35、菜单栏布局 176、Token 32、偏好 43、安装引导 5、更新检查 43、价格目录、动态源 66、Claude 祖先解析 22。
- 面板组在 `NSScreen.main` 不可用时失败；连续性组的跨轮次原图导出断言失败，原因未确认；Claude 核心组 `bindFailed`，未通过。
- Claude Runtime 与岛内审批专项独立编译成功，运行在 `ClaudeRuntimeTests.swift:29` 启用状态断言失败，未通过；未绕过断言。
- `CostSmokeTests` 明确跳过，未启用 `CONTINUITY_BENCHMARK`；未读取或改动用户真实 Codex／应用支持目录数据。
- arm64 Release 主程序与 Helper 构建、App 打包和 deep／strict 签名校验通过。默认构建后端受沙盒限制，使用项目内模块缓存、SwiftPM native 后端及编译器 `-disable-sandbox` 选项，平台文件系统限制仍然生效。可复用命令在临时 `build-app-local.sh`；正式打包脚本未修改。
- 未安装、未启动应用、未提交、未推送。

受保护文件使用 `shasum -a 256` 核对，施工前后 8／8 一致。历史基线 7／8 一致，唯一差异在施工前已经存在；未为匹配旧基线覆盖当前实现：

| 文件 | 施工前后 SHA-256 | 历史基线 |
|---|---|---|
| `ActivityIslandStateSmoke.swift` | `cde2acf46ee2a1e5c31b32895b8143d647659e4263d90dc38fbec50a0e386891` | 一致 |
| `ActivityIslandTaskEffectHost.swift` | `62fa995b889843a44e6d59d20a15281e3da39790eceaeb60c0e72c02ca2136ea` | 一致 |
| `ActivityIslandEffects.swift` | `626886f591c4d89355f28317f4784edd1aa4a1ca2bac86e0a70c20a4f8657276` | 一致 |
| `ActivityIslandCompletionConfetti.swift` | `371bc5f12cb73e0ca72788b384c27082274ef0fe4faa234aa3191b2ddd144a71` | 一致 |
| `RippleGlowOrb.swift` | `d621526511d166727e08f63c20458f433fa9ce96bcb5c1e46a50a0ba85fcbd73` | 一致 |
| `ActivityIslandScrollingText.swift` | `8b2c09155f06b1e419763f855eb3483cc1e1b91721cfc62d560c4ac9c0f767ed` | 一致 |
| `ActivityIslandGlass.swift` | `57451b165370540fcb5d19a507ea3dfd82d07c87d41112a562abffb32e781a71` | 一致 |
| `ActivityIslandMotion.swift` | `afff79d60ec64fd1b8695e840838b38a1b9acf50dbb8e80e1a3b7ade2ffce756` | 既有差异 |

`ActivityIslandMotion.swift` 的历史基线为 `98a47b804aaffc49be28829691bd62564ce9cdc36d1ab34d17c7417b93aa1361`。完整记录见 `protected-before.json`、`protected-after.json` 和 `protected-baseline-check.log`。
