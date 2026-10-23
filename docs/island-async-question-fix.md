# 灵动岛：中文输入与异步提问消失 修复方案

先读 `AGENTS.md`、`docs/island-text-answer.md`。不提交、不推送、不安装。受保护动效文件不得修改。

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
3. 提交：`CodexDesktopIPCClient.submit` 的异步分支要求 `acknowledgement.result.turnId == handle.turnID`，否则判为 `outcomeUnknown`。本轮已结束时，桌面端会开启新的一轮来回答，返回的 turnId 与原 turnId 不同。根据协议与夹具确认正确的判定：
   - 本轮仍在进行：维持现有判定；
   - 本轮已结束：只要返回了一个非空 turnId，并且之后的快照里该问题已解决（`resolvedAnswer` 有值或问题消失），就视为成功；
   - 无法确认时，仍按“结果未知，请在 Codex 中确认”处理，不得重复发送（`attempted` 去重保留）。
   - 提交前沿用现有的 refresh + validate 校验，不放松 handle 一致性校验。
4. 不新增发起新回合的通用能力，只用于回答这一个仍在等待的提问（符合 AGENTS.md）。

## 3. 测试

- 编辑器：组字时 `updateNSView` 不覆盖内容（把同步判断抽成纯函数测试）；激活与归还前台的策略写成纯函数测试（只有点击才激活，失焦或结束后归还）。
- 投影与会话：“异步提问后本轮完成”时，会话保持等待回复，不被移除，不触发完成庆祝；回答后进入完成且不补放礼花。
- 提交：轮次已结束时，新 turnId 加上问题已解决视为成功；问题未解决时为 outcomeUnknown；已尝试过的不重复发送。
- 运行完整测试（`SKIP_COST_SMOKE_TESTS=1`）与 arm64 Release 构建，核对受保护文件哈希；中文报告根因证据、改动和测试结果。
