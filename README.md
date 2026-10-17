<div align="center">

<img src="Resources/Pulse-Logo.svg" alt="Codex Pulse 标识" width="72">

# Codex Pulse

**在菜单栏与灵动岛里，掌握 Codex 的额度、任务和本地用量。**

[English](README.en.md) · [下载 v1.8.1](https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.8.1) · [MIT License](LICENSE)

macOS 13+ · SwiftUI / AppKit · Apple Silicon / Intel

</div>

## 功能

- **额度概览**：查看当前账号的额度窗口、重置倒计时、Credits 和额度恢复记录。
- **实时任务**：灵动岛展示运行阶段、工具进展、待批准与结果摘要，支持多会话、隐私模式和任务特效。
- **用量与成本**：按周期查看 Token、缓存、项目排行和趋势；成本按公开模型价格估算 API 等价金额。
- **动态中心**：汇集官方额度、社区动态、重置时间轴和本地恢复记录，分别标明来源。
- **会话管理**：搜索项目与会话，查看账号归属和异常摘要，支持 Markdown／HTML 导出、原始备份、导入及项目迁移。
- **原生外观**：暖中性色与陶土强调，保留原生玻璃、浅／深／自动外观、实时设置预览及辅助功能支持。

任务监控使用只读桌面 IPC 与本地日志，无需安装 Hook；批准和回答继续在 Codex 中完成。

## 界面预览

### 灵动岛：运行任务与用量看板

<p align="center">
  <img src="docs/images/pulse-island-running.png" alt="灵动岛真实运行态：任务进展、额度入口与玻璃底栏" width="94%">
</p>
<p align="center">
  <img src="docs/images/pulse-island-usage.png" alt="灵动岛用量看板：额度、Token、成本与活动热图" width="72%">
</p>

### 用量分析与成本估算

<p align="center">
  <img src="docs/images/pulse-usage.png" alt="用量分析：Token 概览、趋势、活动与项目排行" width="49%">
  <img src="docs/images/pulse-cost.png" alt="成本估算：API 等价成本与趋势" width="49%">
</p>

### 动态中心与会话管理

<p align="center">
  <img src="docs/images/pulse-dynamic-center.png" alt="动态中心：官方额度、社区预测与公开动态" width="49%">
  <img src="docs/images/pulse-sessions.png" alt="会话管理：项目摘要、更新时间与账号归属" width="49%">
</p>

### 面板与灵动岛设置

<p align="center">
  <img src="docs/images/pulse-panel-settings.png" alt="菜单栏与面板设置，左侧为真实数据只读预览" width="49%">
  <img src="docs/images/pulse-island-settings.png" alt="灵动岛设置，预览使用示例数据" width="49%">
</p>

<details>
<summary>安装与权限</summary>

<p align="center">
  <img src="docs/images/pulse-setup.png" alt="安装与权限：原生任务连接、通知和更新入口" width="82%">
</p>

</details>

## 下载与安装

当前版本：**v1.8.1（Build 27）**。前往 [GitHub Releases](https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.8.1) 下载对应安装包：

| Mac 处理器 | 安装包 |
|---|---|
| Apple Silicon（M 系列） | [arm64 DMG](https://github.com/suguxiaojie/codex-pulse/releases/download/v1.8.1/CodexNotchMonitor-v1.8.1-arm64.dmg) |
| Intel | [x86_64 DMG](https://github.com/suguxiaojie/codex-pulse/releases/download/v1.8.1/CodexNotchMonitor-v1.8.1-x86_64.dmg) |

1. 打开 DMG，将 App 拖入 Applications。
2. 启动 App，保持 Codex／ChatGPT Desktop 已安装并登录。
3. 按需开启通知，在“安装与权限”中查看任务监控连接。

应用使用临时签名，尚未通过 Apple 公证。若系统拦截首次打开，请核对下载来源后，在“系统设置 → 隐私与安全性”中允许打开。

v1.8.0 用户请从本页手动下载安装一次 v1.8.1，以更新应用内的 GitHub 仓库地址；配置和数据继续沿用。

由 Codex Monitor 更名为 Codex Pulse 后，Bundle ID、`CodexNotchMonitor.app` 文件名、偏好键与数据目录沿用原值，现有配置和数据继续使用。应用内检查更新会打开下载地址，由用户完成安装。

## 数据来源与边界

| 内容 | 来源与说明 |
|---|---|
| 官方额度与账号 | 本机 Codex App Server；显示额度比例与重置时间，不等于剩余消息条数 |
| Token 与项目统计 | 本机结构化会话日志，包含缓存；只覆盖本机仍可读取的历史 |
| 实时任务 | 只读桌面 IPC 与本地日志；桌面协议随客户端版本变化，断线时回退 |
| 成本 | Token × 公开模型价格，是 API 等价估值，**不是订阅账单**；未知价格明确标注 |
| 社区动态与预测 | [codex-reset.com](https://codex-reset.com/zh/tibo) 第三方聚合；预测不保证账号重置 |
| 会话账号归属 | 仅使用可靠观察到的证据；基线前及证据不足的记录保持未归属 |

- 正常监控不读取 `auth.json`、Cookie、API Key 或密码，也不将本地会话、项目和用量上传给社区源或价格目录。
- 可读导出在本机处理所选会话，默认遮盖敏感正文；图片像素不自动脱敏。原始备份和项目迁移包可能包含源码、提示词及附件，请私下保管。
- 导入、恢复、删除、迁移和手动额度重置属于用户主动操作，操作前展示范围；手动额度重置需要二次确认。
- 本地文件存在、App Server 可见与 Codex 侧栏可见是不同状态，恢复结果分别报告。

## 从源码构建

需要 Swift 6 工具链及 macOS 系统构建工具，无需额外安装第三方 Swift Package。

```bash
git clone https://github.com/suguxiaojie/codex-pulse.git
cd codex-pulse
./scripts/build-app.sh native
open build/CodexNotchMonitor.app
```

```bash
# 按需运行完整测试
./scripts/test.sh

# 分别生成两种架构的 DMG
./scripts/build-dmg.sh arm64
./scripts/build-dmg.sh x86_64
```

压缩历史会话读取说明见 [docs/compressed-rollouts.md](docs/compressed-rollouts.md)，项目进度与待办见 [ROADMAP.md](ROADMAP.md)。

## 致谢与许可

感谢 [Codex Island](https://github.com/ericjypark/codex-island)、[QuotaView](https://github.com/Duoasa/QuotaView) 和 [Open Claude UI](https://github.com/Caho1/open-claude-ui)。第三方来源与完整许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目采用 [MIT License](LICENSE)，Copyright (c) 2026 CoverAI。Codex Pulse 为独立项目，与 OpenAI 无官方关联。

支持项目：[CoverAI 自家代充服务](https://www.coverai.store/)。
