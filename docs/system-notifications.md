# 系统通知：关注信号、额度恢复与重置卡到期

## 目标

1. 动态中心出现新的“正在关注的待验证信号”或“正在关注的重置预告”时发送系统通知。
2. 额度突然恢复到 100%（`QuotaResetMonitor.evaluate` 检测到 ≥99% 且旧值 ≤95% 的跳变）时立即通知，不再等待证据。

## 一、关注信号通知

- 触发：`refreshTiboFeed` 成功后，对 radar 中的置顶信号（与 NotchView `pinnedSignal` 同一来源）调用 `CodexResetRadarService.resolvePinnedSignal`，状态为 `.pending` 或 `.activePreview` 且 `tweetId` 未通知过时发送。
- 去重：已通知 tweetId 持久化到应用支持目录的新文件（或 UserDefaults 新键），最多保留最近 50 条。
- 基线：首次运行（无已通知记录）时，只把当前信号写入基线，不发送通知。缓存快照（`cachedSnapshot`）不触发通知，只有网络获取成功才触发。
- 内容：
  - 标题：`.pending` →「Tibo 发布了待验证的重置信号」；`.activePreview` →「Tibo 发布了重置预告」
  - 副标题：信号时间 `MM-dd HH:mm`
  - 正文：`signal.displayText`，超过 120 字截断加「…」
  - identifier：`tibo-signal-<tweetId>`
- 后续：信号被确认／兑现时不再单独通知，由额度恢复通知负责。

## 二、额度恢复通知（立即 + 原位更新）

- 检测到跳变就立即通知，所有原因都适用，包括进入 `pending` 的未证实跳变。
- 每次跳变生成稳定的 `notificationID`（例如 `quota-recovery-<detectedAt 秒>`），存放在 `Pending` 里，最终的 `QuotaResetEvent` 也带上它（新增可选字段，保持 Codable 向后兼容）。
- 首次通知：
  - 已有证据（natural／official／manual／mixed）：标题沿用 `reason.title`，正文沿用 `QuotaResetNotifier.body(for:)`。
  - 未证实：标题「额度已恢复至 100%」，正文为变化明细，再另起一行「来源确认中…」。
- 原位更新：未证实跳变之后在 `reconcile` 或用户确认中被归类时，用同一 identifier 重新 `add`，系统会替换原通知。标题为 `reason.title + " · 已核对"`，并且不再播放声音（`sound = nil`）。
- 3 小时仍未证实并过期为 `.unverified`：不再发送任何通知。`isNotifiable` 的语义调整为“是否需要原位更新”。
- 账号切换／上下文变化本来就不会产生跳变（monitor 已校验 accountID 与 contextSignature），保持不变。

## 三、交互

- 注册两个 `UNNotificationCategory`：
  - `TIBO_SIGNAL`：动作「在动态中心查看」(`open-center`)、「打开原帖」(`open-source`)
  - `QUOTA_RECOVERY`：动作「查看重置记录」(`open-center`)；未证实时额外加「标记为手动重置」(`confirm-manual`)，使用单独的 category `QUOTA_RECOVERY_UNVERIFIED`
- 点击正文（default action）与 `open-center`：激活应用，并通过 `MonitorCenterWindowController.show(section: .tibo)` 打开动态中心。
- `open-source`：打开 `userInfo["sourceURL"]`。
- `confirm-manual`：调用与界面「标记为手动重置」相同的路径（`confirmUserQuotaReset`，按 pending 或候选匹配 notificationID），完成后原位更新通知。找不到对应候选时只打开动态中心。
- 已有的账号切换、应用更新通知保持原行为，点击后仍打开 sourceURL。

## 四、设置

- 设置 → 通知区域（`quotaNotificationStatusControl` 所在卡片）新增两个开关，默认开启，使用新的偏好键：
  - 「关注信号提醒」`notifyTiboSignals`
  - 「额度恢复提醒」`notifyQuotaRecovery`
- 关闭后对应类型不发送通知。关闭关注信号提醒期间，仍继续把 tweetId 写入去重记录，避免重新开启时补发旧通知。

## 五、测试

- `Tests/QuotaResetMonitorTests.swift`：未证实跳变立即产生“待通知”结果；后续 reconcile 归类后沿用同一 notificationID；过期为 unverified 时不再产生通知。
- `Tests/TiboFeedTests.swift`（或新文件）：首次基线不通知；新 tweetId 只通知一次；`.confirmed`／`.expired` 不通知；关闭开关期间仍写入去重记录。
- 通知内容构造（标题、正文截断、category）应抽成纯函数，以便测试。

## 重置卡到期提醒

- 来源为成功获取的 `rateLimitResetCredits`；仅处理状态为 `available`、有可靠卡片 ID 和有效到期时间的卡。没有可用卡、数据未知、已使用或过期均跳过。
- 应用运行时复用 60 秒额度刷新，达到 24／12／6 小时内时发送 `CREDIT_EXPIRY` 系统通知及橙色岛内提醒；不新增高频定时器或系统后台任务。系统通知需要 macOS 授权。
- 首次发现或应用重开已跨过多个阶段时，只补当前最紧迫的一条。离线期间不根据陈旧数据通知，待成功刷新再判断；已过期不补发。
- UserDefaults `creditExpiryReminderLedger` 记录账号指纹、卡片 ID、到期时间组合的 SHA-256 标识及最紧迫已通知阶段；重启去重、账号隔离，到期时间变化开始新提醒周期。不保存卡片正文或账号凭据。
- 提醒仅接受刷新前后账号一致且无切换／识别中的结果；账号变化使在途请求失效。没有可靠账号身份时暂缓到后续刷新。
- “安装与权限”新增 `notifyCreditExpiry` 开关，默认开启；不受关注信号／额度恢复两个开关控制，关闭后停止产生新提醒并清除岛内待显示队列中的同类提醒。
- 岛内提醒沿用现有 8 秒展示、任务审批优先与最多 3 条排队规则。此类提醒只提示卡片名称和本地时间下的到期时刻，不提供使用卡片的操作，避免误消费。
