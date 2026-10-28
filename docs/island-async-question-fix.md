# 灵动岛：中文输入与异步提问消失 修复方案

相关边界见 `AGENTS.md`、`docs/island-text-answer.md`。本说明记录中文输入、提问保留与回答投递的实现。

## 1. 中文输入法无法上屏

现象：在灵动岛输入框里用中文输入法打字，拼音和汉字都显示不出来；英文正常。

已确认的原因：

1. `IslandAnswerEditor.updateNSView` 每次 SwiftUI 刷新都会执行 `if editor.string != text { editor.string = text }`。组字期间，marked text 不会写回 binding，于是刷新时组字内容被清空。灵动岛刷新很频繁，所以中文永远上不了屏。
2. 灵动岛面板是 `.nonactivatingPanel`，App 没有成为前台 App。输入法服务只为前台 App 提供组字，这也会造成问题。

修复：

- `updateNSView`：`editor.hasMarkedText()` 为 true 时，跳过所有对 `string` 的赋值和测量写回。只有在没有 marked text 时，才用 binding 同步内容。
- 用户点击输入框（`mouseDown`／`becomeFirstResponder` 由点击触发）时：
  - 先记录当前前台 App（`NSWorkspace.shared.frontmostApplication`），再 `NSApp.activate(ignoringOtherApps: true)` 并 `makeKey`；
  - 发送成功、取消、请求消失或卡片收起，并且失去焦点时，如果记录的 App 仍在运行，就把它 `activate()` 回前台；
  - 不得在没有用户点击的情况下激活本 App。
  - 这一条覆盖 `docs/island-text-answer.md` 第 5 节“不主动激活本应用”的规定：现在限定为用户点击输入框时临时激活。
- 回车判定继续使用 `hasMarkedText()`，组字中的回车交给输入法。

## 2. 异步提问在本轮结束后从灵动岛消失

现象：Codex 用 `request_user_input_async` 提问后继续工作；本轮 `task_complete` 后，Codex 客户端仍然显示提问卡等待回答，但灵动岛把会话当作已完成，1 分钟后移除，提问也随之消失。

真实时间线（用户本机，只看事件类型）：17:32、17:33 两次 `request_user_input_async`，18:11 `task_complete`，提问卡仍在客户端。

要求：

1. 先查清 `CodexDesktopRequestProjection`（`asyncQuestions`／`authoritativeAsyncQuestionIDs`／`resolvedAnswer`）在本轮结束后是否仍投影出未回答的异步提问。可以参考 `Tests/Fixtures` 和 NativeActivity 的测试夹具；如果夹具不够，就新增一个模拟“提问后本轮完成”的夹具。不要读取真实 `~/.codex`。
2. 会话状态（`ActivitySessionState` 等）：只要会话仍有未回答的权威异步提问（或任何仍在等待的 handle），就保持“等待回复”状态（沿用现有 waitingApproval／reply 的表现与 replyRequestIDs），不进入完成态、不触发完成礼花／提示音、不按 1 分钟保留期移除。提问被回答或消失后，按正常完成逻辑处理（此时也不要补放完成礼花）。
3. 提交前刷新快照并重新校验完整 handle；同一请求只尝试一次，不自动补发：
   - 本轮仍在进行：调用 `thread-follower-steer-turn` v1，校验回执 `result.turnId` 等于原轮次。
   - 本轮已结束：调用 `thread-follower-start-turn` v2，发送 `turnStart.request` 和 `turnStart.context`。请求只含当前 threadId、标记化回答 input、clientUserMessageId 和 `send_user_message_async_question` trigger；context 使用 `inheritThreadSettings=true`，由 owner 继承模型、目录和权限，不覆盖这些设置。
   - `restoreMessage` 包含 id、text、createdAt、cwd、context；text、context.prompt 和 input 使用同一标记化回答。
   - 新回执读取 `result.turn.id`。只有更新后的同 owner／同 stream 快照中，回执对应的新轮次实际包含相同问题 ID、题干和答案的用户消息或 accepted steering 消息，才显示已确认。问题消失本身不算投递证据。
   - 回执缺失、答案不符、轮次不符或无法确认时仍显示结果未知；保留 attempted 去重。
4. 不新增发起新回合的通用能力，只用于回答这一个仍在等待的提问（符合 AGENTS.md）。

## 3. 测试

- 编辑器：组字时 `updateNSView` 不覆盖内容（把同步判断抽成纯函数测试）；激活与归还前台的策略写成纯函数测试（只有点击才激活，失焦或结束后归还）。
- 投影与会话：“异步提问后本轮完成”时，会话保持等待回复，不被移除，不触发完成庆祝；回答后进入完成且不补放礼花。
- 提交：夹具拒绝对非 inProgress 轮次 steer；覆盖已完成／中断／失败轮次的 start v2、canonical 历史、设置继承、恢复元数据、空回执、错误答案／轮次、问题消失但答案未到达，以及重复提交。
- 运行完整测试（`SKIP_COST_SMOKE_TESTS=1`）与 arm64 Release 构建，核对受保护文件哈希；中文报告根因证据、改动和测试结果。

## 4. 已结束轮次投递故障的协议依据

本机 ChatGPT 26.1016.61520（Build 21421）的静态客户端实现确认：steerTurn 在当前轮次非 inProgress 时抛错；原生异步提问回答经过 sendMessage 协调器，在 start 与 steer 之间选择。follower start 返回 `result.turn.id`，steer 返回 `result.turnId`。v1.10.0 错将所有异步回答都送入 steer，且旧夹具接受已结束轮次的 steer，导致模拟测试通过、真实提交失败。

修复前，夹具加入真实的非活动轮次拒绝规则后，旧实现稳定抛出 outcomeUnknown。协议来源哈希与回归日志保存在 `.tmp/async-reply-delivery/`；没有向真实会话自动提交答案。
