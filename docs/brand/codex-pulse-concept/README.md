# Codex Pulse 品牌标识探索

这版原创“脉点”已由用户采纳，用于应用品牌 Logo 与系统应用图标。应用展示名称已统一为 Codex Pulse；保留原有 Bundle ID、可执行文件、安装路径、偏好键和数据目录以保持兼容。原 CoverAI 文件保留。

正式运行素材为 `Resources/Pulse-Logo.svg` 和 `Resources/Pulse-AppIcon.icns`；`CodexMark` 共用矢量素材，并保留同形原生绘制回退。本目录保留设计稿与预览。

目录约定：`*.svg` 为可编辑矢量源，`*.png` 为对应预览；`brand-board` 展示标识、配色与小尺寸应用。生成脚本保存在本次任务 `.tmp/pulse-brand/`，交付文件不依赖该目录。

- `icon-dark.svg`：暖炭灰底与陶土色 P 形开放轮廓、独立脉点。
- `icon-light.svg`：浅色底版本，使用更深的陶土色保持辨识。
- `mark-clay.svg`：透明背景品牌图形。
- `mark-mono.svg`、`mark-reverse.svg`：透明背景单色图形，用于模板图标和反白场景。
- `brand-board.svg`、`brand-board.png`：完整方案板。

图形以粗线、圆端与开放负空间组成，避免依赖渐变表达轮廓；背景的中性轻渐变仅用于图标底板。脉点是固定品牌元素，不代替应用的绿色／橙色／红色健康状态。P 表达 Pulse，开放轮廓表示会话持续与轮次衔接。

颜色：陶土 `#D97757`，浅底深陶土 `#C6613F`，暖炭灰 `#1B1B19`，浅暖灰 `#F7F7F5`。配色与表面参考 open-claude-ui 本地快照 ddf3aea，图形原创，未使用 Anthropic 或 OpenAI 官方标识、商业字体或二进制素材。方案板仅使用系统字体。

标识保持静态，不引入持续动画；所在控件继续沿用现有 CDS hover／press 预设和 Reduce Motion 行为。应用打包脚本直接使用正式素材，不依赖任务临时目录。
