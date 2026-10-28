# 提醒卡让位于会话完成礼花 修复方案

先读 `AGENTS.md`、`docs/island-alert-card.md`。不提交、不推送、不安装。受保护动效文件（含 `ActivityIslandCompletionConfetti.swift`）不得修改。

## 问题

`ActivityIslandWindowController.synchronizeAlerts()` 的 `blocked` 条件只覆盖审批、待回复和重置确认，不包含会话完成：

- 会话刚完成、灵动岛正在展示完成卡片和礼花时，提醒卡会立刻展开，把完成卡片顶掉，礼花喷在提醒卡上。
- 提醒卡正在显示时，如果有会话完成，礼花同样会喷在提醒卡上，完成卡片也看不到。

## 修复

1. `blocked` 新增“完成庆祝中”，满足以下任一条件即为 true：
   - 生命周期处于完成弹出状态，即 `lifecycle.isCompletion` 且灵动岛为展开态，并处在自动弹出的保持时间内；
   - 面板礼花正在播放（`completionConfetti.isActive`，只读查询，不改礼花实现）；
   - 紧凑态正在显示完成回执（`model.compactReceipt != nil` 且 `showsCompletedStatistic`），同时礼花仍在播放。
2. 提醒卡显示期间，如果有会话完成，沿用现有 blocked 逻辑：当前提醒退回队首，倒计时暂停，剩余时间保留。
3. 完成卡片按原节奏收起后，提醒卡再展开，不改动完成卡片的保持时长和收起曲线。
4. `completionBurstSerial` 的递增与 `noteCompletion` 的触发条件保持不变。
5. 还要处理一个时序：提醒卡退回队列后，灵动岛要回到完成卡片的展示（展开态显示 `ActivityIslandExpandedList`，焦点为已完成会话），保证礼花喷在完成卡片上。

## 测试

在 `Tests/IslandAlertTests.swift` 增加以下用例：

- 完成庆祝中收到提醒：提醒排队，`current == nil`；
- 提醒显示中发生完成：提醒退回队首，剩余时间不变；
- 庆祝结束后：提醒出队并显示。

运行完整测试（`SKIP_COST_SMOKE_TESTS=1`）与 arm64 Release 构建，核对受保护文件哈希，用中文报告。
