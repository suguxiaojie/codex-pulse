# 灵动岛审批

展开任务列表后，点击待批准／待回复任务，在当前聚焦行下方处理请求。新卡片和内容变化后的前 0.6 秒禁用操作；提交期间禁用按钮。隐私模式隐藏命令、路径和题干，只提供原客户端入口或交回终端。

## Codex

桌面 IPC follower 只观察已有 owner，不声明会话所有权。只有当前快照允许 `supportsUntrustedAppInput` 且 handle 的 epoch、owner、revision、nonce、rawRequest 及请求身份均匹配时，用户点击才能提交。request 仅用单数 `targetClientId` 指向 owner，不包含 broadcast 专用的 `targetClientIds`。每个请求身份只尝试一次，不自动重试；客户端配置与日志不写入。

- 命令／文件审批：允许一次、本会话允许、拒绝、取消任务；显式 `availableDecisions` 进一步限制选项，不支持策略改写。
- 权限：本轮允许、本会话允许、拒绝；批准按上游规则重建全部已识别项：仅 enabled=true 的 network 与 fileSystem.read／write／entries，省略空数组；拒绝返回空权限。出现未知顶层或 fileSystem 子键时仅提供原客户端入口。展示层与 IPC 共用构造规则，不能扩大范围；摘要只显示条目标题与路径，不输出原始 JSON。
- 同步提问：最多 4 题，全部具有非 secret 单选选项；只回传用户点选的选项，不提供自定义文本。异步问题按单题选择，刷新快照后走上游 steer-turn 协议。
- MCP 表单／URL、未知请求及无输入能力的 owner：在 Codex 中处理。CLI 或无 handle 时保持只读提示。

IPC 回执只表示已发送，界面显示“已发送，等待 Codex 确认”，以后续快照移除请求为准。旧请求或重复提交显示“请求已变化，请在 Codex 中查看”；超时、失联或不确定回执显示“结果未知，请在 Codex 中确认”。原客户端始终可用，先回答者生效。“在 Codex 中处理”只激活桌面 App，不使用深链。

## Claude Code

经用户启用的专属 PermissionRequest Hook 与 Helper 私有连接承载审批。route 的等待上限为 120 秒，运行时同步到期撤销按钮，关闭连接而不返回决定，交回原终端。原 Hook 配置的 3600 秒 timeout 保留；重新启用时迁移 route，设置内容相同时不改写 settings.json。

岛内提供允许一次、有 suggestions 时的本会话允许、拒绝、回终端，以及最多 4 题单选的 AskUserQuestion。回答写入原输入副本的 `updatedInput.answers`。始终允许、取消任务、完整参数仅保留在“查看详情”的原请求窗口。

实现参考 QuotaView `f7795311bf06c2a54c9b9756da375c50d0f4930e`，MIT 许可见项目第三方声明。测试只使用合成快照、隔离配置和私有测试 socket，不向真实会话提交。
