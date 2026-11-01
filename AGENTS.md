# Codex Pulse 项目规范

## 适用范围

- GitHub 仓库为 suguxiaojie/codex-pulse；应用更新接口、Release 校验与文档链接统一使用该仓库，安装包文件名继续保留 CodexNotchMonitor 兼容标识。
- 应用展示名称为 Codex Pulse；为兼容现有配置与数据，保留 CodexNotchMonitor target／可执行文件／安装路径、com.coverai.codex-notch-monitor Bundle ID、既有偏好键与数据目录，不随品牌名称迁移。
- 本项目是 Swift 实现的原生 macOS 应用，保持现有 Swift Package 结构和 AppKit／SwiftUI 技术栈。
- Codex 任务监控使用桌面 IPC 与本地日志；允许在用户明确点击后，经桌面 IPC follower 协议回答当前仍在等待的审批／提问，请求必须与快照中的 handle（epoch、owner、revision、nonce、rawRequest）完全一致；不恢复 Codex lifecycle Hook，不写 Codex 客户端配置；不自动批准。
- One Native／共享 Codex CLI 的异步提问通过现有 daemon 的 `app-server proxy` 读取；仅对本地日志已识别且 daemon 仍加载的用户会话显示。显式回答须重新核对连接 epoch、轮次、问题 ID／正文／选项，并用 `turn/steer.expectedTurnId` 限定当前活动轮次；已结束轮次回原客户端，不自动 `turn/start`、resume 或启动 daemon。协议与验证见 `docs/one-native-questions.md`。
- Claude Code 独立接入允许可选专属 Hook／statusLine；启用前备份配置，只管理本应用标记项，停用恢复原状态栏并保留其他工具配置。不得读取账号凭据；审批必须对应当前真实请求，等待上限 2 分钟，失联／超时交回 Claude 原客户端。
- Grok CLI 使用官方 `_x.ai/billing` 额度查询及 `$GROK_HOME` 本地记录，不读取凭据、不安装 Hook。用户已明确授权自动接入：备份共享设置的原状态，仅管理 `$GROK_HOME/config.toml` 的 `cli.use_leader`，启用官方共享模式；普通 `grok` 启动后自动识别会话与项目，不选择目录、不由 Pulse 新建终端。配置修改保留其他内容，拒绝不明确写法或并发变更，不复制其他配置中的凭据；不得迁移、重启或接管现有独立终端。监控端连接已存在的官方默认 `leader.sock`，不自动发送 initialize／创建或恢复会话／prompt；岛内仅在用户显式点击后回答真实问题，或对真实权限请求允许一次／拒绝一次，保留原生选项 ID，不生成长期授权。操作前核对连接 epoch、RPC ID、tool call ID、轮次及原请求，失效／原端已答／结果不明时不重复投递，不自动批准。统一额度池与预付余额分开显示；实时任务须有可靠归属证据。协议见 `docs/grok-cli-integration.md` 与 `docs/grok-island-questions.md`。
- 只修改与当前需求直接相关的文件，不清理、回滚或覆盖用户已有的未提交改动。

## 本地数据安全

- `~/.codex` 与 `~/Library/Application Support/CodexNotchMonitor` 中的会话、账号连续性和备份数据默认只读；需要改写、迁移或删除时必须先得到用户确认。
- 不读取、保存或输出 `auth.json`、Cookie、Token、API Key 等账号凭据。
- 历史会话的账号归属必须保持证据边界：只记录插件可靠观察到的归属，不把基线前会话猜测为当前账号。

## 会话连续性

- 项目重命名仅在用户提交后通过当前桌面 App Server 的 project/update 修改名称；使用唯一项目 ID，保留 roots、metadata 与会话绑定，不直接改写 Codex 状态文件。写后回读确认，不确定结果不自动重发；客户端侧栏刷新需与服务端保存状态区分。
- 本次用户明确授权一次离线例外：仅修正已确认的 13 个项目在 `.codex-global-state.json` 中的 `local-projects[项目 ID].name`，与已保存的英文名一致。须先完整备份，等 ChatGPT／Codex 桌面及 Pulse 退出且文件稳定后执行；核对 ID、原名、路径及文件未被并发修改，只替换名称字符串，原子写入并回读验证。保留恢复备份，重新打开后核对侧栏。本例外不适用于其他状态字段、项目或后续批次。
- 未登记的历史会话分组可单独设置 Pulse 显示名称，按完整路径保存到本应用偏好，不修改日志、目录或 Codex 登记；仅在成功查询确认没有对应项目时提供该入口，不能把连接失败或重复登记当作历史分组。原生项目名称优先于历史分组别名。
- 允许显式删除所选项目独立文件夹及全部内容，移入废纸篓；不得只凭会话分组路径执行。必须在删除任何会话前验证唯一项目登记、准确目录、共享／嵌套项目和真实路径，单独确认完整路径；执行前再次校验目录身份及范围。路径归属不明、父目录或其他项目可能受影响时拒绝文件删除，保留仅删会话选项。
- 区分用户会话、Subagent／Guardian 内部线程和无用户消息的系统记录。内部线程不得计入“待恢复”。
- 恢复前后必须使用一致的 App Server 线程来源口径。
- 项目路径缺失、归属未知和 App Server 不可见是不同状态，界面不得混用。

## 验证

- 会话连续性或账号归属改动后，至少运行 `Tests/ContinuityTests.swift` 对应的定向测试。
- Claude Code 接入边界与来源见 `docs/claude-code-integration.md`；专属 Helper 位于 `Sources/ClaudePulseHelper`，隔离验证入口为 `scripts/test-claude.sh`。
- 交付前运行项目现有完整测试脚本和 Release 构建；无法执行时明确说明未验证项。

- 灵动岛空闲验收以语义正确为准：完成反馈后保留常驻额度／空闲横幅；允许窗口可见，但不得包含虚假活动任务、“思考中”卡片或运行态动效。不能再用“窗口必须消失”作为通过条件。

## 本机覆盖安装授权

- 迭代阶段只构建当前 Mac 使用的 `arm64` Debug／Release；完整测试与 `arm64` Release App 构建通过后，默认先完整备份现有 `/Applications/CodexNotchMonitor.app`，再覆盖安装并启动验收，不再重复要求用户输入“覆盖”。
- 只有用户明确说明“最终版”“正式发布”或要求双版本／Universal 时，才构建 `arm64 + x86_64` Universal App、双架构 DMG 或其他正式发布产物；普通功能迭代不得重复构建双架构。
- 覆盖前仍须只读核对源 App、目标 App、版本、架构、签名和运行进程；备份保存在项目 `build/backups/`，并在交付中给出精确回滚路径。
- 该持续授权只适用于 `/Applications/CodexNotchMonitor.app` 的本机覆盖安装，不包括修改 `~/.codex`、Hook 配置、账号或会话数据、应用支持目录、其他 App、提交、推送、公开发布或其他外部写操作。
