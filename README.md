<div align="center">

<img src="Resources/Pulse-Logo.svg" alt="Codex Pulse 标识" width="72">

# Codex Pulse

**在菜单栏和刘海里，随时看清 Codex 与 Claude Code 的额度、任务和用量。**

[English](README.en.md) · [下载 v1.9.0](https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.9.0) · [MIT License](LICENSE)

macOS 13+ · 原生 SwiftUI / AppKit · Apple Silicon / Intel

</div>

## 它能做什么

Codex Pulse 是一个原生 macOS 菜单栏应用，有三个入口：

- **刘海里的灵动岛**：看正在运行的任务；
- **菜单栏玻璃面板**：随手查额度；
- **监控中心**：深入分析用量、成本和会话。

所有数据来自本机：Codex App Server、桌面 IPC 和本地会话日志。不读取任何账号凭据。

### 灵动岛

- **光眼球**：紧凑态左侧是一颗会做表情的小角色。思考时左右张望，执行工具时眯眼，待批准时睁圆眼并亮起琥珀光环，完成时笑着蹦一下，失败时变成叉眼；鼠标靠近刘海时，眼睛会跟着看过来。
- **硬件黑岛体**：岛体与刘海同色，顶部内凹圆角和菜单栏平滑衔接；边缘有一圈细光，颜色跟随任务状态，强度可在设置里调节。
- **焦点舞台**：展开后只有一张焦点卡片，显示当前任务最近 3 个步骤和本轮 Token；其他会话排成一行胶囊，点击即可切换。新出现的待批准／待回复请求会自动抢占焦点；任务完成 3 秒后，焦点转到仍在运行的任务。已结束的会话在列表中保留 1 分钟。
- **岛内审批**：对 Codex 和 Claude Code 当前正在等待的请求，可以在岛内显式批准或回答单选问题；其他请求交回原客户端处理，不会自动批准。
- **动效**：保留状态烟雾、量子噪点、液态涌浪三种 Metal 进度效果，以及完成彩屑和确认脉冲；"减弱动态效果"打开时全部改为静态显示。

### 菜单栏玻璃面板

- **气象主区**：瓶颈额度窗口的剩余百分比用大号圆体数字显示，并按本周期的消耗速度给出预报：可用到重置，或大约多久后用完（明确标注为估算）。面板颜色跟随额度变化：充足时为冷青，偏紧时为琥珀，告急时为红色。
- **Codex／Claude 切换**：启用 Claude Code 接入后，页眉可在两个来源之间切换。Claude 显示 5 小时额度和每周额度。
- **7 天条带**：标题本身就是"成本　Token"切换。柱子下只写星期，数值集中在下方一行；有未计价模型的日子标注为"金额未知"。
- **玻璃质感**：保留液态玻璃效果，"面板不透明度"作用于整个面板；系统开启降低透明度或增强对比度时，自动改为不透明。

### 监控中心

- **用量与成本**：按周期查看 Token、缓存、项目排行和趋势。成本按公开模型价格估算，是 API 等价金额，不是订阅账单。
- **动态中心**：汇集官方额度、社区动态、重置时间轴和本地恢复记录，并标明各自的来源。
- **会话管理**：搜索项目与会话，查看账号归属和异常摘要；支持导出 Markdown／HTML、原始备份、导入和项目迁移。
- **Claude Code**：独立的连接开关、权限请求、官方额度，以及本机 Token 与成本历史。

### 数字单位

大数字默认用中文万／亿显示，例如 `8,432`、`541万`、`1.84亿`。可在"菜单栏与面板 → 内容 → 用量 → 数字单位"中切换为 K／M／B。金额、百分比和会话数不受影响。

## 界面预览

### 灵动岛

<p align="center">
  <img src="docs/images/pulse-island-focus.png" alt="展开的灵动岛：硬件黑岛体、状态边缘光、光眼球焦点卡与会话胶囊" width="90%">
</p>

### 菜单栏玻璃面板

<p align="center">
  <img src="docs/images/pulse-glance.png" alt="玻璃面板：左为 Codex 页（剩余额度、速度预报、7 天成本），右为 Claude 页（每周与 5 小时额度）" width="72%">
</p>

### 监控中心

<p align="center">
  <img src="docs/images/pulse-usage.png" alt="用量分析：Token 概览、趋势、活动与项目排行" width="49%">
  <img src="docs/images/pulse-cost.png" alt="成本估算：API 等价成本与趋势" width="49%">
</p>
<p align="center">
  <img src="docs/images/pulse-dynamic-center.png" alt="动态中心：官方额度、社区预测与公开动态" width="49%">
  <img src="docs/images/pulse-sessions.png" alt="会话管理：项目摘要、更新时间与账号归属" width="49%">
</p>
<p align="center">
  <img src="docs/images/pulse-claude-code.png" alt="Claude Code：连接开关、官方额度与本机用量" width="49%">
</p>

### 设置

<p align="center">
  <img src="docs/images/pulse-island-settings.png" alt="灵动岛设置：实时预览、边缘光强度与自动展开" width="49%">
  <img src="docs/images/pulse-panel-settings.png" alt="菜单栏与面板设置：实时面板预览、内容开关与数字单位" width="49%">
</p>

<details>
<summary>安装与权限</summary>
<p align="center">
  <img src="docs/images/pulse-setup.png" alt="安装与权限" width="82%">
</p>

</details>

## 下载与安装

当前版本：**v1.9.0**。在 [GitHub Releases](https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.9.0) 下载与你的 Mac 对应的安装包：

| Mac 处理器 | 安装包 |
|---|---|
| Apple Silicon（M 系列） | [arm64 DMG](https://github.com/suguxiaojie/codex-pulse/releases/download/v1.9.0/CodexNotchMonitor-v1.9.0-arm64.dmg) |
| Intel | [x86_64 DMG](https://github.com/suguxiaojie/codex-pulse/releases/download/v1.9.0/CodexNotchMonitor-v1.9.0-x86_64.dmg) |

1. 打开 DMG，把 App 拖进"应用程序"。
2. 启动 App。确保 Codex／ChatGPT Desktop 已安装并登录。
3. 按需开启通知；任务监控的连接状态可在"安装与权限"中查看。

应用使用临时签名，尚未经过 Apple 公证。如果系统拦截首次打开，请先确认下载来源，再到"系统设置 → 隐私与安全性"中允许打开。

应用由 Codex Monitor 更名而来，Bundle ID、`CodexNotchMonitor.app` 文件名、偏好设置和数据目录都沿用原值，升级后原有配置和数据继续可用。应用内的"检查更新"只打开下载页，安装仍由你自己完成。

## 数据来源与边界

| 内容 | 来源与说明 |
|---|---|
| 官方额度与账号 | 本机 Codex App Server，显示额度比例和重置时间，不等于剩余消息条数 |
| 额度预报 | 由当前窗口的已用比例和已过时间推算，只是估算；周期开始不足 1 小时时不预测 |
| Token 与项目统计 | 本机结构化会话日志，包含缓存，只覆盖本机仍能读到的历史 |
| 实时任务 | Codex 来自桌面 IPC 和本地日志；Claude Code 来自可选的专属 Hook，以及对话记录和进程兜底 |
| 成本 | Token × 公开模型价格，是 API 等价估值，**不是订阅账单**；价格未知时明确标注 |
| 社区动态与预测 | 第三方聚合 [codex-reset.com](https://codex-reset.com/zh/tibo)，预测不保证你的账号会重置 |
| 会话账号归属 | 只采用可靠观察到的证据；基线之前或证据不足的记录保持"未归属" |

- 不读取 `auth.json`、Cookie、API Key、Claude 凭据或 Keychain；本地会话、项目和用量不会上传给社区源或价格目录。
- Codex 任务监控不安装 Hook，也不写入 Codex 客户端配置。Claude Code 接入默认关闭；启用前会先备份 `settings.json`，只管理本应用自己的条目；停用时恢复原来的状态栏，并保留其他工具的配置。
- 导入、恢复、删除、迁移和手动额度重置都是你主动发起的操作，执行前会展示影响范围；额度重置需要二次确认。
- 可读导出默认遮盖敏感正文；原始备份和迁移包可能包含源码、提示词和附件，请自行妥善保管。

## 从源码构建

需要 Swift 6 工具链和 macOS 构建工具，不依赖第三方 Swift Package。

```bash
git clone https://github.com/suguxiaojie/codex-pulse.git
cd codex-pulse
./scripts/build-app.sh native        # 构建当前架构
open build/CodexNotchMonitor.app
```

```bash
./scripts/test.sh                    # 完整测试（含 Claude 接入专项）
./scripts/build-dmg.sh arm64         # Apple Silicon 安装包
./scripts/build-dmg.sh x86_64        # Intel 安装包
```

更多文档：

- [灵动岛审批](docs/island-approvals.md)
- [Claude Code 接入说明](docs/claude-code-integration.md)
- [压缩历史会话读取](docs/compressed-rollouts.md)
- [项目进度](ROADMAP.md)

## 致谢与许可

感谢 [Codex Island](https://github.com/ericjypark/codex-island)、[QuotaView](https://github.com/Duoasa/QuotaView) 和 [Open Claude UI](https://github.com/Caho1/open-claude-ui)。第三方来源和完整许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目采用 [MIT License](LICENSE)，Copyright (c) 2026 CoverAI。Codex Pulse 是独立项目，与 OpenAI、Anthropic 没有官方关联。

支持项目：[CoverAI 自家代充服务](https://www.coverai.store/)。
