# Grok CLI 接入调研

## 当前状态

2026-11-01 核对本机 xAI 官方 `@xai-official/grok`，版本为 `1.0.70 (f50904eaee6c)`。用户要求支持 Grok CLI 的额度与任务能力，并明确将真实剩余额度作为硬性要求。

**真实账号额度的主动查询已实测成功，无须 Pulse 读取凭据。** 使用一个短生命周期的官方 `grok agent --no-leader stdio` 子进程，仅发送 `_x.ai/billing` 请求；由 CLI 自行处理已有登录身份与服务端鉴权，Pulse 只接收账单结果。应用实现已接入监控中心、菜单栏与岛内用量来源，完整回归和本机安装状态以 `ROADMAP.md` 为准。

## 应用实现

- `GrokData.swift`：严格解析额度、账期、共享池、预付余额和 CLI 报告成本；上下文容量不参与订阅额度计算。
- `GrokBillingClient.swift`：仅发 `_x.ai/billing`；20 秒总查询期限、1 MiB 输出上限、响应 ID 匹配。对上游、网络等短暂失败最多尝试 3 次，间隔 0.6／1.2 秒；认证、不支持、空额度、畸形数据或取消不重试。区分官方 CLI 返回的上游账单失败与网络失败，不记录或展示原始错误正文。标准错误不保存，结束或停用时回收自己创建的进程，不影响原 TUI。不发送 initialize、模型请求或会话恢复。
- `GrokSessionReader.swift`：读取 `$GROK_HOME/sessions` 的摘要和增量通知流，按原始 prompt ID 去重继承历史；明确标记子 Agent 的会话不再与父汇总相加。常规会话发现与历史更新间隔 30 秒，活动会话每 2 秒读取，每次总读取预算 8 MiB。会话数、目录数和单行均有上限；截断／inode 替换会重建该文件状态；半行不发布实时状态，损坏记录标记统计不完整。
- `GrokRuntime.swift`：接入默认关闭，可在“Grok CLI”页面启用。额度每分钟查询，也可手动刷新；失败保留带标记的上次观测，认证失效／无额度清除旧值，周期结束后隐藏旧比例。历史为本机全部记录，不推断当前账号归属。只有同用户、进程开始时间与官方安装位置匹配的 Grok 进程，以及对应 cwd 和本进程启动后更新过的任务证据，才能产生实时卡片。初次读到的完成历史不触发提醒；进程失联产生中性结束，完成回执保留 60 秒。
- `GrokPresentation.swift`／`GrokView.swift`：共享池与预付余额分开显示，缺失成本保留未知；已知成本可显示下界；不提供 Codex 额度重置操作，不在缺失 Grok 数据时回退其他提供商数据。
- 显示时间使用当前渲染时间兜底，页面出现和收到新额度时重置采样时间；不能用保留页面的旧时间将新成功快照误判为未来数据。只有实际过期周期才显示“周期已结束”。
- Claude Helper 发现 `GROK_HOOK_EVENT` 时直接返回，不读取 Claude route，也不转发事件或权限决定。原因是 Grok 默认发现 Claude 兼容 Hook；该保护不修改 Grok／Claude 配置。

完成礼花与声音沿用现有灵动岛策略。用户显式启动的共享模式支持连接后收到的新问答和单次工具批准，详见 [岛内问答与批准](grok-island-questions.md)；独立终端、旧待处理请求与不支持的交互仍回原端。监控不安装 Grok Hook，不自动创建、恢复或启动任务。

定向入口：`zsh scripts/test-grok.sh`，由完整 `scripts/test.sh` 调用；合成测试不访问真实凭据或调用模型。运行时测试的 `--live` 参数仅在独立手动验证时查询真实官方额度，不属于默认完整测试。真实活动任务的完成提醒须由用户后续正常任务验证，不为验收创建付费模型任务。

## 真实额度查询验证

### 方法名与请求

线上 JSON-RPC 扩展方法名带前导下划线。源码内部的 `x.ai/billing` 不能直接作为线上方法名：

```json
{"jsonrpc":"2.0","id":1,"method":"_x.ai/billing","params":{}}
```

本轮验证不发送 `initialize`、`session/new`、`session/load`、`session/resume` 或 `session/prompt`，不修改权限模式，不调用模型。收到指定 ID 的结果后结束本轮创建的子进程，不连接或终止用户的现有 TUI。探针没有读取 `auth.json`、Cookie、Keychain 或环境中的凭据值；CLI 内部正常使用自身登录状态不向 Pulse 暴露凭据。

隔离 `GROK_HOME`、没有登录信息的测试结果：

| 线上方法 | 结果 |
|---|---|
| `x.ai/billing` | `-32601 Method not found` |
| `_x.ai/billing` | `-32000 Authentication required` |

随后在本机现有登录状态下，仅发送正确请求成功获取 `config` 与 `subscription_tier`。本轮没有通过 `initialize` 触发初始化逻辑；所核对的上游源码显示初始化还会安排工作树回收、过期权限清理与信任迁移，因此不应为了账单查询无条件增加初始化调用。CLI 启动与查询本身仍可能正常更新其日志／缓存，不承诺它是完全无本地副作用的进程。

### 本机真实结果

北京时间 `2026-11-01 12:19` 的主动查询与同次 CLI 账单日志一致：

| 字段 | 观测值与含义 |
|---|---|
| `subscription_tier` | `SuperGrok Plus` |
| `config.creditUsagePercent` | `1.0`，服务端报告已用 1%，可显示剩余 99% |
| `config.currentPeriod.type` | `USAGE_PERIOD_TYPE_WEEKLY`，本次为周周期 |
| `config.currentPeriod.end` | `2026-11-07T17:18:14.814+00:00`，北京时间 `2026-11-08 01:18:14` |
| `config.prepaidBalance.val` | `0`，预付余额为 0 美分，与订阅剩余比例分别展示 |
| `config.isUnifiedBillingUser` | `true`，统一额度池；不能把它描述成 Grok CLI 独享额度 |

这是带查询时间的真实服务端观测值，不是未来持续有效的固定值。新结构只返回比例时，不能反推剩余美元金额或消息条数。

验证证据位于 `.tmp/grok-quota-research/`：`isolated-protocol-probe.json`、`authenticated-protocol-probe.json`、`billing-log-entry.json`、`verified-quota-snapshot.json`。最后两份是主动查询前 `12:09` 的日志快照，应按其原始采集时间解释；主动查询结果和 `12:19:20.357` 的新 CLI 日志另行核对一致。证据不含账号凭据。

### 一手源码依据

已下载核对 xAI 官方 `xai-org/grok-build` 上游提交 `2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8`：

- [账单扩展与字段定义](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/extensions/billing.rs)：内部 `x.ai/billing` 处理器经 CLI proxy 的 `GET /billing?format=credits` 获取服务端账单；`creditUsagePercent` 优先于旧的金额比值，`currentPeriod` 优先于旧账期字段；预付余额单位为美元美分。
- [ACP 扩展分发及初始化](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/agent/mvp_agent/acp_agent.rs)：账单方法实际注册在扩展分发器，初始化包含其他维护动作。上游源码提交与本机二进制构建 ID 不能视为相同提交；本机兼容性由上述 1.0.70 实测单独证明。
- [原生账单展示处理](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-pager/src/app/dispatch/billing.rs)：空账单需清除旧余额，不能将旧值当作当前；统一额度与 legacy PAYG 分支独立处理。

第三方资料中有“`x.ai/billing` 只在 TUI 可用”的说法，本机测试证明不带下划线时确实返回方法不存在，但正确线上方法可以成功。不能依赖这一未经版本／方法名核对的结论否定 ACP 路径。

## 已核对的数据入口

- 官方安装包的 README 指向 [Grok Build 文档](https://docs.x.ai/build/overview)，与 npm 包名及本机版本一致，不能套用同名第三方 Grok CLI 的协议。
- [会话文档](https://docs.x.ai/build/features/sessions)确认本地会话持久化。本机随 CLI 分发的 `docs/user-guide/17-sessions.md` 进一步记录 `GROK_HOME`、编码工作目录、`summary.json`、`updates.jsonl` 与 `grok usage <session-id>`。
- `grok usage --help` 确认其读取持久化会话 Token／成本。随包文档规定返回 `sessionId`、`updatedAt`、`session`、`turns`，成本 `costUsdTicks` 为每美元 `10^10` ticks。本机已有会话的结构与文档一致；未运行模型请求。
- 本机会话的 `updates.jsonl` 为包含 `timestamp`、`method`、`params` 的通知流，`params.update.sessionUpdate` 可见用户消息、公开助手文本、工具调用／更新与 `turn_completed`。`params._meta` 可包含 `promptId`、`turnStartMs`、事件 ID 和事件时间。思考块不作为公开摘要读取或展示。
- 随包 `25-status-line.md` 列出会话模型、上下文、累计 Token、成本和活动 `prompt_id`；明确不发送 rate-limit summary。公开 [Status Line 文档](https://docs.x.ai/build/features/status-line)确认其可提供模型、上下文和成本，但不能据此把上下文百分比当订阅剩余额度。
- 随包 `17-sessions.md` 将交互式 Credits／账单查看入口指向 TUI 的 `/usage`；它不是“账单只能通过 TUI 获取”的协议限制。后续已按上文实测确认可通过 `_x.ai/billing` 主动获取。
- 官方账单处理器会将成功查询的额度快照记录为 `billing: fetched credits config`，写入 `$GROK_HOME/logs/unified.jsonl` 的 `ctx.config`。已核对本机原有 11 条记录。该日志可作为明确标注观测时间的后备来源；不能凭其自动刷新，不能在账号变化后将旧快照归给新账号。只解析明确的账单事件及允许字段，不导出整个日志；其他日志可能含身份或凭据片段。

## 任务与交互边界

- 终端进程存在只证明客户端存活，不代表任务忙碌；最近修改时间也不是任务完成证据。完成反馈须对应之前观察到的同一轮真实活动与明确终态；启动时的旧完成记录不得触发庆祝。
- 本地 `active_sessions.json` 包含 session ID、PID、进程开始时间和 cwd。用于实时任务前，还需验证用户、可执行身份与开始时间，拒绝 PID 复用；缺少可靠归属时只显示历史数据。
- `grok leader list --json` 在本轮返回空列表；`grok leader info --json` 返回没有可达 leader。这是本机当时状态，不能推断其他用户或未来版本的运行方式。
- 随包 `15-agent-mode.md` 描述 ACP 客户端建立／加载会话、发 prompt 及处理权限的能力，但尚未验证旁路客户端能安全回答现有 TUI 请求。不能为实现监控而启动会话、resume、接管客户端或自动批准。
- [权限文档](https://docs.x.ai/build/features/permissions)描述原生 Ask／Auto／Always-approve，不构成 Pulse 操作现有权限请求的协议证据。
- 专属 Hook 可采集真实生命周期与 `Notification.permission_prompt`，但安装会修改 Grok 接入配置且受文件夹信任控制。采用前需明确产品方案，保留其他工具配置，不自动修改 trust 或权限模式。

## 实施方案与验收要求

真实额度的硬性前置条件已通过本机可行性验证。应用采用短生命周期 CLI ACP 查询；失败时仅保留本次运行中已查询的旧观测，不自动从日志加载不明账号的额度，也不引入直接读取 Token 或浏览器 Cookie 的替代方案。日志额度快照保留为调研与人工核对入口。

额度展示优先消费 `creditUsagePercent` 与 `currentPeriod`；缺失、非法百分比、过期周期或空账单均不能显示成当前剩余量。查询失败须区分未登录、方法不支持、网络／超时、无账单和旧观测；不能将失败显示成 0%／100%。当前只证明本机 1.0.70，无登录环境的失败分支已验证；其他版本与账号套餐须在实现中处理不支持状态。刷新频率、进程开销与长期轮询仍待工程验证，避免高频启动 CLI。

只读扫描与展示的验收要求包括缺失／损坏／部分写入、超大文件、inode 替换、截断、未知字段、非法／溢出数字、跨时区日期、缓存包含关系、fork／继承历史去重、子 Agent 去重、旧轮迟到事件、进程退出及 PID 复用。成本缺失不算零，本地历史不等于当前账号账单，未定价记录不伪造完整金额。实时审批／提问必须另有当前请求的可靠身份和回传协议证据。已执行的验证及尚待实机验收项以 `ROADMAP.md` 为准。

实施后按项目规范完成定向回归、完整 `scripts/test.sh` 和 arm64 Release 构建。全部通过后才进入既有本机备份覆盖安装流程；既有完整测试的成本排行别名失败必须保留并重新核对，不自动沿用其他任务的例外授权。
