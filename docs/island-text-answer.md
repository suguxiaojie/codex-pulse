# 灵动岛直接打字回答 Codex 提问 施工方案

先读 `AGENTS.md` 与 `docs/island-focus-stage.md` 第 2 节（受保护动效文件）。不提交、不推送、不安装。

## 1. 用户已确定的决策

| 项 | 决定 |
|---|---|
| 范围 | 只回答 Codex 当前正在等待的提问（`item/tool/requestUserInput` 与 `desktop/tool/requestUserInputAsync`）。**不**做“Codex 一轮结束后发送下一条消息”，也不新增任何发起新回合的 IPC 方法 |
| 输入框 | 提问卡展开时直接显示输入框，点一下就能输入。有选项的提问，在选项下方加一个「其他」输入框 |
| 发送 | 回车发送，Shift+回车换行。发送前重新核对请求是否仍在等待（沿用现有 handle 校验：epoch、owner、revision、nonce、rawRequest） |

## 2. 现状

- `IslandCodexApproval.questions`：遇到没有选项的提问，整张卡会退回“请在 Codex 中处理”；`response()` 只接受选项里已有的答案。
- IPC 层已经支持任意文本：异步提问走 `thread-follower-steer-turn`，答案上限为 65 536 字节 UTF-8；同步提问走 `thread-follower-submit-user-input`。
- `ActivityIslandPanel.canBecomeKey == true`，窗口可以获得键盘焦点。

## 3. 数据规则（纯函数，可测）

- `Question` 新增 `allowsText: Bool`：
  - 规则为 `isOther == true || options.isEmpty`；
  - 异步提问的投影里本来就是 `isOther: true`。
- 放宽 `questions` 的解析：`options` 可以为空，但这时 `allowsText` 必须为 true。以下情况保持原规则不变，整张卡交回 Codex 客户端处理：
  - `isSecret == true`；
  - `multiSelect == true`；
  - 超过 4 个问题；
  - id 重复。
- `response()` 的校验：每个问题的答案要么在 `options` 里；要么 `allowsText` 为 true，且去掉首尾空白后不为空、长度不超过 4 000 个字符、UTF-8 不超过 65 536 字节。答案按原文提交（只去掉首尾空白）。
- 不自动作答，忽略 `autoResolutionMs`。

## 4. 界面（`ActivityIslandApprovalCard.swift`）

- 每个问题下：先显示选项按钮（如果有），再显示一个输入框。
  - 有选项时占位文字为「其他…」；
  - 没有选项时为「输入回答…」。
- 输入框用多行 `TextField`，高 1～4 行，超出后在框内滚动；字体与颜色沿用 `FloatingSurfaceTypography`／现有卡片样式；获得焦点时有可见的焦点环。
- 选项和文字互斥：点选项会清空该题的输入框；在输入框里打字会取消该题已选的选项。
- 回车：
  - 所有问题都已作答时，等同于点「提交回答」；
  - 否则把焦点移到下一个还没作答的问题。
- Shift+回车换行；输入法正在组字（marked text）时，回车不触发发送。
- 「提交回答」按钮的可用条件改为：每题都选了选项，或者填了有效文字。
- 发送中：禁用输入并显示进度。失败时保留草稿，并沿用现有错误提示：
  - 请求已过期或已被处理：「这个提问已在 Codex 中处理或已过期」，并提供「在 Codex 中查看」；
  - 其他错误：显示原错误信息。
- 草稿按请求 handle（nonce）保存在内存里，请求消失后丢弃，不写盘。

## 5. 焦点与收起

- 点击输入框时让面板成为 key window。卡片收起或请求结束时 `resignKey`，不主动激活本应用，也不抢其他应用的前台。
- 输入框有焦点或草稿不为空时，视为正在交互：灵动岛不得自动收起，也不被其他提醒（含 `docs/island-alert-card.md` 的提醒卡）顶掉。
- 隐私模式下保持现有的提问文本显示规则，不新增泄露。

## 6. 约束与测试

- 受保护动效文件哈希与 `build/island-focus-stage-baseline.sha256` 一致。
- 不改 Claude Code 的审批路径。
- 扩展 `Tests/IslandApprovalTests.swift`：
  - 无选项的提问可以解析，且 `allowsText` 为 true；
  - isSecret／multiSelect 仍然被拒绝；
  - 文字答案的校验（空白、超长、字节上限）；
  - 选项与文字互斥后生成的 response；
  - 异步提问的自由文本能通过 `validResponse`。
- 运行完整 `scripts/test.sh`、arm64 Release 构建；中文报告改动、取舍、哈希核对与测试结果。
