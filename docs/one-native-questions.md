# One Native 异步提问接入

## 范围与来源

本机 Codex 0.166.0 的共享 daemon 可以通过 `codex app-server proxy` 建立 WebSocket 连接。One Native 现有 CoreRuntime 的 `cli_agents/native/codex_runtime.py` 使用同一入口查询运行中的线程。

Codex Pulse 使用原生 Swift 实现，只启动自己的 proxy 子进程，不启动或重启 daemon，不修改 One Native、Codex 配置、Hook、账号或历史会话文件。该通道也适用于使用同一默认 Codex home／daemon 的 CLI 会话；不是通过窗口名称判断来源。

接口依据为本机 `codex app-server generate-ts --experimental` 导出的协议，以及 [官方 App Server 文档](https://learn.chatgpt.com/docs/app-server)。实现入口：`CodexProxyTransport.swift`、`CodexSharedQuestions.swift`、`MonitorStore.swift`。

## 显示与回答

- 只观察本地日志已识别为用户会话、且 `thread/loaded/list` 仍包含的线程；要求 `canAcceptDirectInput=true` 和可识别的原生来源，不将内部线程混入。
- 读取最新轮次和 `thread/items/list` 的原生 `agentMessage.questions`，复用桌面提问解析器识别带 `questionItemId` 的真实回答；工具输出 `accepted:true` 不是用户回答。
- 每 5 秒轮询，按轮次缓存已读项目，仅补读新项目与尾页。分页不完整、异常、混入其他轮次、断线或超过容量限制时不发布部分问题。超过 15 秒未刷新则禁止回答；断线重连使用新 epoch。
- 岛内复用现有选项、自定义文本、隐私模式与草稿控件。当前活动轮次可以直接回答；已结束轮次只引导回 One Native，不隐式开启新一轮。
- 用户显式提交后重新读取完整当前轮次，核对 epoch、线程、轮次、原问题／选项和未回答状态。只调用带 `expectedTurnId` 的 `turn/steer`，不调用 `thread/resume` 或 `turn/start`。
- 回答使用 Codex 原生 `<send_user_message_question_reply>` JSON 包装，保留问题精确 ID／正文与回答。RPC 回执不等同于送达，只有原生历史中出现精确回答才提示确认送达；其他情况明确显示受理或结果未确认。
- 写入一旦尝试，不自动重试。该进程内对同一问题的重复提交在断线重连后仍被阻止；需要回原客户端核对不确定结果。
- 不支持接管其他客户端拥有的同步审批 RPC；本轮接入的是用户报告的 `request_user_input_async`。

## 验证入口

`zsh scripts/test-shared-questions.sh` 已纳入 `scripts/test.sh`。全部模型请求均由隔离 fixture 替代；覆盖陈旧／跨轮次／已回答请求、选项变化、内部线程、加载状态、答案边界、多题、重复点击、未知回执、分页异常、WebSocket 握手／分片／ping／大小上限／关闭与方法白名单。

只读实机探针：`.tmp/shared-question-tests/transport --live` 与 `.tmp/shared-question-tests/questions --live`，只查询运行中的 daemon，不发送模型任务、回答或启动新轮次。

真实岛内点击回传需用户在真实等待中的问题上操作，不能用测试程序自动回答真实任务来代替验收。
