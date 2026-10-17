# Codex Pulse 项目规范

## 适用范围

- GitHub 仓库为 suguxiaojie/codex-pulse；应用更新接口、Release 校验与文档链接统一使用该仓库，安装包文件名继续保留 CodexNotchMonitor 兼容标识。
- 应用展示名称为 Codex Pulse；为兼容现有配置与数据，保留 CodexNotchMonitor target／可执行文件／安装路径、com.coverai.codex-notch-monitor Bundle ID、既有偏好键与数据目录，不随品牌名称迁移。
- 本项目是 Swift 实现的原生 macOS 应用，保持现有 Swift Package 结构和 AppKit／SwiftUI 技术栈。
- 任务监控仅使用只读桌面 IPC 与本地日志；已移除 lifecycle Hook、Helper 及客户端配置写入，不重新引入安装／审核链路。
- 只修改与当前需求直接相关的文件，不清理、回滚或覆盖用户已有的未提交改动。

## 本地数据安全

- `~/.codex` 与 `~/Library/Application Support/CodexNotchMonitor` 中的会话、账号连续性和备份数据默认只读；需要改写、迁移或删除时必须先得到用户确认。
- 不读取、保存或输出 `auth.json`、Cookie、Token、API Key 等账号凭据。
- 历史会话的账号归属必须保持证据边界：只记录插件可靠观察到的归属，不把基线前会话猜测为当前账号。

## 会话连续性

- 区分用户会话、Subagent／Guardian 内部线程和无用户消息的系统记录。内部线程不得计入“待恢复”。
- 恢复前后必须使用一致的 App Server 线程来源口径。
- 项目路径缺失、归属未知和 App Server 不可见是不同状态，界面不得混用。

## 验证

- 会话连续性或账号归属改动后，至少运行 `Tests/ContinuityTests.swift` 对应的定向测试。
- 交付前运行项目现有完整测试脚本和 Release 构建；无法执行时明确说明未验证项。

- 灵动岛空闲验收以语义正确为准：完成反馈后保留常驻额度／空闲横幅；允许窗口可见，但不得包含虚假活动任务、“思考中”卡片或运行态动效。不能再用“窗口必须消失”作为通过条件。

## 本机覆盖安装授权

- 迭代阶段只构建当前 Mac 使用的 `arm64` Debug／Release；完整测试与 `arm64` Release App 构建通过后，默认先完整备份现有 `/Applications/CodexNotchMonitor.app`，再覆盖安装并启动验收，不再重复要求用户输入“覆盖”。
- 只有用户明确说明“最终版”“正式发布”或要求双版本／Universal 时，才构建 `arm64 + x86_64` Universal App、双架构 DMG 或其他正式发布产物；普通功能迭代不得重复构建双架构。
- 覆盖前仍须只读核对源 App、目标 App、版本、架构、签名和运行进程；备份保存在项目 `build/backups/`，并在交付中给出精确回滚路径。
- 该持续授权只适用于 `/Applications/CodexNotchMonitor.app` 的本机覆盖安装，不包括修改 `~/.codex`、Hook 配置、账号或会话数据、应用支持目录、其他 App、提交、推送、公开发布或其他外部写操作。
