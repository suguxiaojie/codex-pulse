# Grok 岛内提问与用户输入

## 当前状态

2026-11-01：已实现问答与工具单次批准；用户随后明确要求取消目录选择，并授权一次性自动配置。源码现使用官方默认共享服务，正常 `grok` 启动自动识别项目；安装与实机状态以 `ROADMAP.md` 为准。现有独立终端不迁移、不重启、不接管。

## 使用与实现

在监控中心 Grok CLI 页面一次性开启自动接入，之后正常在任意项目运行 `grok` 即可。`GrokLauncher.swift` 只管理 `$GROK_HOME/config.toml` 的 `cli.use_leader=true`，不选择目录、不生成 `.command` 或新终端，不设置 auto／always-approve，不注入 prompt。用户已明确授权本机配置；监控本身不在后台重复改写配置。

配置修改保留其他内容、注释及换行；已启用时不写文件。仅备份共享开关的原值、原文件是否存在与 SHA-256，不复制其他模型参数或凭据。备份采用 0600 权限，写前复核文件内容，原子替换后回读；链接、不可写文件、歧义格式、复杂多行写法及并发更改拒绝自动处理。关闭监控不自动还原全局共享设置，避免影响原生终端和其他客户端；备份保留供显式回退。

`GrokSharedClient.swift` 仅连接已存在的官方 `$GROK_HOME/leader.sock`，核对所有者、写权限、peer UID 和协议版本；每个连接有独立 epoch。通过只读 `_x.ai/session/info` 确认本机已登记会话的 ID 与 cwd 后订阅未来事件，不调用 initialize／load／resume／prompt。无已登记终端时断开，不阻止原生服务正常退出。

会话查询的实际回执是 JSON-RPC `result` 中再嵌套 `ExtMethodResult.result`，其内 `SessionInfoResponse` 的 `sessionId`、`cwd` 与模型／轮次字段位于同层；不是 `success/data` 结构。已核对 [原生结果包装](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/session/result.rs) 与 [会话字段定义](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/session/acp_types.rs)，并查询官方 CLI 确认空 resident 的原生 `result.result={}` 不会被误认为有效会话。错误或部分结果不授予交互能力。

Pulse 尊重自身的 `GROK_HOME`，未设置时使用 `~/.grok`；正常终端须使用同一数据根目录。不会改写用户 shell 的环境配置，也不会将不同数据根目录的会话混合。

`GrokQuestion.swift` 仅接收官方反向请求和当前连接中的工具／轮次证据；原始 RPC ID、tool call ID、会话、轮次、问题与选项共同决定身份。支持最多 4 题、每题最多 16 选项及受限自由文字。多选保留数组，含逗号的标签不拆分；自由文字以 `Other` 和 `annotations.notes` 提交。数据与草稿仅在内存中保留。

工具批准按 [ACP v1 权限协议](https://agentclientprotocol.com/protocol/v1/tool-calls#requesting-permission)实现，只显示当前原生 `allow_once`／`reject_once` 选项，返回其原始 `optionId`。操作参数缺失、过大或不存在单次选项时回原终端，不截断后盲目批准，不生成 allow-always／reject-always，不处理计划批准或 MCP 表单。

提交后锁定该请求，不以发送成功宣称操作已生效。原终端先答、原生 resolved、轮次结束、断线或关闭接入时撤销控件；连接断开不发送 cancelled，不重发结果不明的回答。事件回调有递增修订号，旧回调不能恢复已撤销的请求。沿用现有灵动岛焦点抢占、草稿、中文输入及隐私隐藏。

限制：不通过 session/load 回放既有问题，因此首次连接和重连之前已存在的问题回原终端处理。共享模式并不让当前独立终端变成可被旁路回答的会话。

## 已核对的协议

来源为 xAI 官方 `xai-org/grok-build` 提交 `2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8`。源码提交与本机二进制构建 ID 不视为同一版本；本机 `grok 1.0.70 (f50904eaee6c)` 静态包含提问、pending interaction、resolved 及共享回放相关标识，真实收发仍需隔离协议验证。

- [等待请求登记](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/session/pending_interaction.rs)：提问、权限与计划批准均为阻塞的 ACP 反向请求；请求通过内存通道等待，按 tool call ID 登记，不落入日志。日志中的问题正文不能证明它现在仍等待回答。
- [问答字段](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-tools/src/implementations/grok_build/ask_user_question/types.rs)：请求携带 session ID、tool call ID、问题数组与模式；接受回答使用 `outcome=accepted`，答案按问题映射为选择数组，自定义文字通过注释的 notes 携带。取消是独立结果，不可把缺失／断线当作用户取消。
- [共享 leader 路由](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/leader/server.rs)：互动请求可发给该会话的多个订阅者，先回答者生效；原终端回答后广播 resolved。连接帧与注册格式见 [leader 协议](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/leader/protocol.rs)。重新附着时的待处理请求回放依赖会话附着流程，不能直接假定只读查询会回放问题。

## 本机证据与边界

- 当前登记的 Grok 终端为独立运行；`grok leader list --json` 返回空数组，没有发现默认 Grok leader socket。当前终端的 Unix IPC 为匿名连接，未发现可供 Pulse 连接的旁路回答端点。这是本轮观察，不推断所有运行方式均如此。
- 新建一个 `grok agent --no-leader stdio` 查询进程不会取得原终端内存中的等待请求；不能把额度查询进程用于伪装原问题的回答。
- 不向当前真实会话投递测试答案，不重启、迁移或停止当前 Grok，不读取凭据，不通过键盘注入模拟回答。
- 项目边界禁止监控自动创建／恢复会话及发送 prompt。用户已确认只修改共享启动设置，以替代旧的目录选择入口；这不授权迁移或重启现有独立终端。

## 验证边界

本机 1.0.70 在隔离 GROK_HOME 中的原生 `grok --leader` 启动已确认创建共享 Socket；实际 Swift 客户端与官方 leader 的注册、协议版本及只读连接已验证，不调用模型。合成服务覆盖问答和权限的完整帧收发、原生选项 ID、多选数组、断线不取消、重发拒绝及旧轮次／旧 epoch 失效。生产真实用户提问／批准仍须下一次正常共享终端任务验收，不将合成结果称作真实模型回传通过。

默认入口 `zsh scripts/test-grok.sh` 会运行核心、共享问答／权限传输和运行时检查；完整脚本另含原有岛内审批回归。验证证据保存在 `.tmp/grok-questions/`，最终检查结果见 `ROADMAP.md`。

回答操作必须绑定连接 epoch、会话、原始 RPC ID、tool call ID、当前轮次和原问题／选项；显式点击后再次核对可用性。过期、原终端已答、连接重建或未知提交结果时禁用重复投递。权限批准、计划批准、MCP 表单与普通问题分别处理，不扩大普通文字回答的权限。

没有读取或迁移真实凭据，也没有向现有用户会话投递测试决定。
