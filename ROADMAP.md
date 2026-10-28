# Codex Pulse Roadmap

## 项目目标

原生 macOS 应用，集中展示 Codex 官方额度、本地 Token／成本、任务状态、社区信号与会话管理；保持不同数据来源和账号归属的证据边界。

## 当前阶段

GitHub 仓库为 suguxiaojie/codex-pulse。v1.10.0（Build 32）已正式发布为 Latest，源码提交 f8b05822aedc2a590a0c2c8a5f9f4c473580db67 与附注标签 v1.10.0 已推送。完整测试、双架构 Release、镜像／签名／包内文件比对通过，公开下载的两份 DMG 与 SHA256SUMS-v1.10.0.txt 哈希和 GitHub digest 均与本地一致。

当前源码与本地双架构构建为 v1.11.0（Build 33），GitHub 最近公开 Release 仍为 v1.10.0。本地开发包展示名称为 Codex Pulse，配套原创“脉点”品牌；Bundle ID、可执行文件、安装路径、偏好键与数据目录沿用 CodexNotchMonitor，不迁移现有配置和数据。

本地开发交接笔记不随公开发行包上传；历史版本变化以 Git 历史为准。

## 进行中与待办

- 2026-10-29 03:05：One 内异步选择题未出现在灵动岛，已定位当前桌面 IPC socket 连接返回 errno 61（Connection refused）；仅有本地日志监控，无法取得当前请求及可靠回传 handle。原生投影已支持 async questions，One 提问／回答通道适配尚未实施；不能仅从日志生成可操作按钮。证据：.tmp/plans-pricing/async-question-diagnosis.json。




- 2026-10-27 15:56：SwiftUI 刷新链与动态日期解析已修复、完整测试一次及 arm64 Release 一次通过，已备份覆盖安装。关闭监控中心释放宿主、设置呼吸改为按可见性运行的 Core Animation、日期缓存及排序预计算；Clawd／任务 Metal 未改。现场 App CPU 56.01%→2.81%，主线程空闲 124／2858→4160／4529；基线含 Instruments 开销，不作受控收益结论。单视图精确归因与打开关闭实机回归待确认。报告：.tmp/swiftui-frame-loop/REPORT.md。未提交／推送／发布。

- 2026-10-27 15:31：Clawd 岛内版已实现并备份覆盖安装，实机视觉与严格空闲同场景性能对比待验收。紧凑左翼角色＋额度、右翼状态／×N；卡片静态头像、Core Animation 帧播放与紧凑描边；移除挂岛舞台／同伴／粒子／凹陷／定时器，保留方案 A Metal。完整测试和一次 arm64 Release 通过，导出 15 张 PNG。现场 App CPU 41.94%→26.53%，WindowServer 43.15%→43.73%，Clawd 主线程样本 310→0；场景未确认，不作受控收益结论，真实运行态未测，单次截图失败。报告：.tmp/clawd-in-island/REPORT.md；说明：docs/island-mascot-clawd.md。未提交／推送／发布。

- 2026-10-27 14:55：灵动岛动效降耗方案 A 已实现并备份覆盖安装，受控单卡／三卡性能与实机视觉待验收。任务 Metal 半分辨率、默认 24 fps／全卡 20 fps、设备与队列共享、环境不可用时暂停、提醒定时器按需创建；保留独立卡片视图及原动画时间语义。完整测试一次通过，最终 arm64 Release／签名和安装哈希通过；安装前复核补主线程保护后额外增量构建一次。截图入口无法获取显示画面，现场 CPU 仅作参考。报告：.tmp/island-effect-perf-a/REPORT.md。未提交／推送／发布。

- 2026-10-26 15:45：提醒岛体布局已完成并备份安装、启动，真实额度恢复／关注信号自动弹出待下次事件验收。宽度沿用展开设置、高度按内容测量，左右 28 pt 留白并去除纵向弹性空白；配色、光效、图标与文案不变。完整测试、arm64 Release、签名和安装哈希通过。说明：docs/island-alert-card.md；证据：.tmp/alert-layout/。

- 2026-10-26 01:19：Claude 岛内单选／多选／自定义回答已备份覆盖安装并启动，真实 Claude 会话点击回传与中文输入法交互待实机验收；现有 Claude 会话需重开以加载更新后的 Hook。合成端到端、完整测试、arm64 Release 与签名已通过。说明：docs/island-approvals.md；证据：.tmp/claude-island-choices/。

- 2026-10-24 03:54：异步文字回答的本地修复版已备份安装并启动，真实 Codex 投递仍待用户在灵动岛显式点击验收。GitHub v1.10.0 发行包尚未包含此修复；本轮未提交、推送或发布。并行角色动效工作保留，未混入此次安装。

- 2026-10-24 03:18：v1.10.0 已发布。新增功能的桌面视觉、真实中文输入法／焦点、通知端到端与 Intel 真机运行仍待人工验收；自动化验证结果以本次发布记录为准。相关实现说明见 docs/system-notifications.md、docs/island-alert-card.md、docs/island-text-answer.md、docs/island-completion-celebration.md、docs/island-async-question-fix.md。

- 2026-10-22 补充核对：重新下载 Release 三个附件，SHA-256 与本地 build/ 产物一致，SHA256SUMS 校验 OK；线上 README 与 HEAD 逐字节一致，10 张截图与 3 个 Release 链接均返回 200。遗留：docs/images/pulse-setup.png（v1.8.0 起沿用）仍显示 v1.7.0 Build 25、部分遮挡邮箱 b***@163.com 及旧审批文案，与其他截图的“本机账号”口径不一致，待用户决定是否替换。

- 2026-10-22 03:15：灵动岛设置完整／放大预览已复用生产焦点舞台：硬件黑与状态边缘光、投影、光眼球、步骤、本轮 Token、会话胶囊排及底栏；继续使用中性示例数据，设置直接联动。预览测试 48/48、硬件黑 50/50、角色 69/69、会话状态 148/148 与 arm64 Release／严格签名通过，普通／隐私离屏图已检查。完整脚本面板组因 NSScreen 不可用停止；续跑连续性原图断言、Claude socket bindFailed 失败，Claude Runtime 被前置失败阻断，待原生环境验收。8 个受保护文件本轮哈希未变（Motion 与基线的既有差异保留）。未改 Glance，未安装、提交或推送。证据：.tmp/island-settings-preview/。

- 2026-10-22 00:46：大数字统一格式已实现，验证未全部完成。默认中文万／亿，设置可切换 K／M／B；Token、社区计数、图表悬停与辅助功能共用 CountFormatter，金额与小计数不变。20 个主测试组中 17 组通过，新增格式化 71 项、菜单栏宽度 176 项通过；Claude 祖先解析 22/22 通过。AnalysisPresentation、ActivityIslandPanel、Claude Runtime／审批编译受沙箱宏插件启动限制；Claude 核心 socket bindFailed，独立探针确认 EPERM；Continuity 图片导出断言失败，原因待确认。arm64 Release 构建在 SwiftPM manifest 沙箱启动阶段被阻止，未生成本次 App；界面切换与完整类型检查待本机复验。8 个受保护文件与施工前哈希一致。未安装、提交或推送。替换点、旧断言和验证说明：docs/number-format.md 第 8 节；日志与施工前快照：.tmp/number-format/。

- 2026-10-21 22:42：菜单栏方向 C“气象”已实现，待 Claude 本机复跑与视觉验收：瓶颈额度／速度预报、状态染色、七日成本／Token 条带、三格指标、全板不透明度与辅助功能回退，旧七项偏好保留。新增纯逻辑测试 1,197 项通过；arm64 Debug、Release App 与 deep／strict 签名通过。scripts/test.sh 在面板组因 Metal／无 NSScreen 退出，后续原组已用临时脚本续跑：Claude 核心 socket bindFailed、Runtime 启用断言失败，独立 AF_UNIX 探针确认沙箱 EPERM；Continuity 图片导出断言失败，尚不能确认环境归因，留待本机复核；其余组通过。未修改灵动岛源码／测试，未安装、写 /Applications、提交或推送。方案：docs/glance-weather.md；日志、施工前哈希与范围核对：.tmp/glance-weather/；产物：build/CodexNotchMonitor.app。

- 2026-10-22 00:05：灵动岛第 5 轮 Claude 进程归属修正完成，待 Claude 本机复验。Helper 用 sysctl KERN_PROC_PID 沿父链最多检查 8 层，跳过 sh／bash／zsh／dash／fish／env／login／timeout，检测环路与缺失信息，发送首个非中间进程的 PID 和名称；无法确认时不发送。Runtime 仅接受事件到达时 kill(pid,0)==0 且名称非中间进程的 PID，最新有效值替换旧值，无效／缺失证据关闭进程兜底。祖先解析 22/22、Runtime 隔离回归（shell／死进程拒绝、有效 PID 替换、有效 owner 退出）通过，arm64 Release 主程序／Helper 架构与深度严格签名通过。此前 3 秒焦点交接、回执、60 秒保留、配置缓冲与转录兜底不变，受保护动效未改。本轮未安装、未写入 /Applications、未提交或推送。说明：docs/claude-code-integration.md；日志及差异：.tmp/claude-process-owner/。

- 2026-10-21 20:00：灵动岛审批第 3 轮视觉修正与隔离验证完成，未安装。验收方反馈第 2 轮已安装版本的真实 Claude 允许／拒绝端到端通过；Codex 真实审批、第 3 轮实机视觉与 VoiceOver 仍待验收。离屏截图可检查按钮排布和高度，但现有反馈样式的完整文字／颜色捕获仍有限制。报告：[REPORT.md](.tmp/island-approvals/REPORT.md)。

- 2026-10-21 16:54：Claude Code 可选完整接入已实现、测试并备份覆盖安装，真实官方额度成功态与长期规则落盘待验收；真实允许／拒绝审批已由 Claude 验收方反馈通过，见最新岛内审批记录。复用 QuotaView f779531 的 MIT 日志解码／增量统计／配置安装恢复／私有通信／Claude 专属 Helper，增加独立入口、来源任务与显式请求窗口；原 Codex 只读限制已由后续显式岛内审批授权取代，见最新记录。完整回归通过（连续性 37/37），最终 Claude 核心 42 项与实际运行态回归通过；最终 arm64 Release、主程序／Helper 签名和安装哈希通过。本机已启用 14 个专属事件入口、请求处理和 statusLine，其他配置及原状态栏核对一致。真实 Claude CLI 2.1.306 无工具调用两次成功，实机确认连接、完成回执保留、7 份日志／2 天／367.1M Token／$135.49 估算、日期轴与明细一致；SessionEnd 不覆盖真实终态，空会话退出不制造回执。默认关闭；本机按用户授权启用，现有会话可能需重开。说明：docs/claude-code-integration.md；证据：build/qa/claude-integration/。未提交／发布。本轮之前的回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-claude-integration-20261021-163859.app 。回滚前先在新页停用 Claude 接入以恢复客户端配置。

- 2026-10-21：监控四页（用量分析／成本估算／动态中心／会话管理）按设置页同一设计语言重构，已备份覆盖安装，待用户自行验收。Claude 设计（.tmp/monitor-redesign/DESIGN.md）、Codex 执行与测试、Claude 终验并退回一轮修复（操作与备份展开区固定高度挤压会话表；成本吞吐量单位错位）。统一卡片头字形图块与元信息胶囊、主指标／次指标排版、输入／输出／缓存构成胶囊、图表内衬、空状态、动态列表合卡与时间轴节点、会话表卡片化与语义胶囊；新增 MonitorCenterComponents.swift。统计、计价、筛选、归属与证据状态、确认流程及 AnalysisPresentation.swift 未改；恢复记录类型由菜单改为同值分段。完整测试（连续性 37/37）与 arm64 Release／签名通过；真实数据（30 项目／151 会话／31 条社区动态）写保护沙箱截图见 build/qa/monitor-redesign/。无凭据下官方额度成功态、真实导入导出／恢复、辅助功能组合未实测。未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-monitor-redesign-20261021-041142.app 。记录：.tmp/monitor-redesign/。

- 2026-10-21：设置三页（菜单栏与面板／安装与权限／灵动岛设置）视觉重构已备份覆盖安装，待用户自行验收。Claude 出设计方案（.tmp/settings-redesign/DESIGN.md），Codex 执行与测试，Claude 终验。去除页面底板、行首字形图块、卡片外分组标签、预览舞台、统一行节奏，开关／分段／滑杆细化；安装与权限新增只读状态总览（复用既有状态，不新增逻辑）与引导步骤点。偏好键、绑定、文案、侧栏结构、预览渲染与无障碍不变；scripts/test.sh 仅为面板测试补编 MonitorDesktopStyle.swift。完整测试与 arm64 Release／签名通过，12 张离屏窗口截图（三页 × 浅深色 × 1060×760／900×640）见 build/qa/settings-redesign/；VoiceOver、减少动态效果／增强对比、macOS 26 以下材质回退未实测；浅色宿主下灵动岛预览顶栏文字对比不足为既有问题（正式应用固定深色），本轮未改。未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-settings-redesign-20261021-032416.app 。记录：.tmp/settings-redesign/。

- 2026-10-17 12:33：v1.8.1 已在新仓库正式发布；v1.8.0 用户需从新 Release 手动安装一次，之后沿用新仓库更新入口。测试与实机验收由用户自行执行。工作区另有 AnalysisPresentation.swift 界面改动，保持未提交且未混入本次发行快照。

- 2026-10-17 12:20：v1.8.0 运行验收由用户自行执行：本轮未运行自动化测试、截图或交互检查，Intel 尚无真机验收。双架构构建／镜像与公开附件校验、Git 推送及 Release 发布均已完成，详见最近完成与最近验证。

- 2026-10-17 12:07：会话管理项目行会话摘要已实现并备份覆盖安装，待用户自行验收。折叠／展开项目行都汇总当前搜索和筛选后的 threads：最近会话更新时间、单账号／多账号／部分归属／未归属、待恢复与路径缺失异常。只按 observed＋已有账号标识分组，基线前与未知分别计数并在悬停明细保留，不推断当前登录账号；缺少可靠标识的 observed 记录归入未确认展示。会话数量移至项目名旁，部分匹配显示匹配数／总数；表头、项目和会话行共用列宽／间距，灰阶摘要与异常橙色沿用 CDS，保留原生 List、选择／展开／详情／菜单、完整项目操作范围和所有原筛选口径。新增只读 SessionProjectSummary 展示模型，中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或 UI 验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-session-project-summary-20261017-120721.app 。证据：.tmp/session-project-summary/。

- 2026-10-17 12:00：用量／成本概览卡精简已实现并备份覆盖安装，待用户自行验收。移除内层青绿／陶土圆角底块及额外横向缩进，保留外层暖中性卡片；主指标统一主文字色，右侧会话／项目与 Token 吞吐量使用中性次要色，分项／时间轴字号统一，Token 单位缩小且保留辅助功能组合。成本“API 等价估值，非账单”说明移至分项下方，让两页标题与核心指标对齐。保留图表数据色、趋势／柱形／热图／悬停、统计／格式化／周期／账号口径、等宽数字与原数字过渡／减少动态分支；功能、配置、数据与玻璃效果不改。中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或 UI 验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-overview-card-simplify-20261017-120037.app 。证据：.tmp/overview-card-simplify/。

- 2026-10-17 11:55：应用展示名称统一为 Codex Pulse，已备份覆盖安装，待用户自行验收。同步系统 CFBundleDisplayName／CFBundleName、概览／监控中心／岛体窗口标题、通知／退出／辅助功能文案、App Server 展示标题与新导出包来源名称／说明。菜单栏避让按当前 PID 排除自身，不再依赖旧品牌字符串。保留 Bundle ID、target／可执行文件、安装路径、偏好键、数据目录、导入导出格式与更新资源命名；不改写账号／会话数据，沿用已采纳 Logo 和回滚后的面板布局。中英文 README、AGENTS 与品牌说明同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-pulse-name-20261017-115517.app 。记录：.tmp/pulse-name/。

- 2026-10-17 11:52：用户采纳“脉点”后已接入应用品牌 Logo，并备份覆盖安装，待用户自行验收。共用 CodexMark 的三个入口读取 Resources/Pulse-Logo.svg，保留同形原生 P／脉点回退并更新辅助功能标签；新增多尺寸原生 Pulse-AppIcon.icns 与 CFBundleIconFile，打包脚本复制两份正式素材。原 CoverAI 文件保留，菜单栏额度环及客户端来源图标不改；该轮仅替换 Logo；展示名称已在后续 Codex Pulse 命名迭代统一，Bundle ID、数据目录、功能及回滚后面板布局不变。中英文 README 与品牌说明同步。按持续要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-pulse-logo-replace-20261017-115143.app 。本轮新增资源清单和原源码快照在 .tmp/pulse-logo-replace/，证据：install.json、change.diff。



- 2026-10-17 11:32：菜单栏面板阅读衬底、成本空状态、Token 排序与动态高度已调整并备份覆盖安装，待用户自行验收。主滚动阅读区采用连续暖中性衬底，增强对比／减少透明度时加强遮蔽，外围原生玻璃与不透明度偏好不变。今日／30 日 Token 移至成本前并排展示，独立开关保留。成本仅在明细就绪且估值大于零时显示图表、峰值与最近一天；零估值／无 Token 用量使用紧凑行，未就绪／缺失显示明确状态和“—”，账号日志 unknownModels 提示明确不限定所选周期。概览按实际内容自然高度测量并去除根视图固定高度，配合既有屏幕限高与滚动；原估高仅为首次后备，重置详情原高度保留。账号归属、数据／计价口径、周期、七项开关和所有操作未改，中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-glance-reading-cost-cds-20261017-113224.app 。记录：.tmp/glance-reading-cost-cds/。

- 2026-10-17 11:25：恢复可见的回执计时、摘要语义色、结果短文案与横幅提示已统一并备份覆盖安装，待用户自行验收。控制器监听已有 playbackVisible 的恢复信号，在主 RunLoop 标记提交后同步紧凑回执；不刷新／唤起窗口，不重置已开始的 3 秒计时或重播失效回执。摘要待批准为橙、失败为红，其余分类／分隔符中性，保留宽度降级与完整辅助说明。紧凑结果缩短为完成／取消／失败／结束＋标题，悬停与辅助功能保留完整状态、标题与详情并沿用隐私隐藏；额度／空闲横幅提示明确悬停展开、点击查看额度与用量。保留状态证据、待批准／新运行优先、玻璃、特效选项和原有功能，中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-island-visibility-copy-cds-20261017-112451.app 。记录：.tmp/island-visibility-copy-cds/。

- 2026-10-17 11:19：最后会话完成后的紧凑反馈已统一并备份覆盖安装，待用户自行验收。明确运行转完成后，最终完成回执暂时优先于额度分支，首次在可见紧凑态显示时启动一次 3 秒计时，到期清除并回到常驻额度／空闲横幅；普通刷新不延长，计时开始后展开／遮挡不重启，仅可见紧凑态在到期时刷新窗口。待批准、新运行轮次及较新的非成功结果清除旧完成回执，旧回调按 session／turn 核对，失效记录与历史完成不重播。保留完成证据、聚焦排序、自动弹出开关、玻璃、特效选项与礼花触发，中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。修改前回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-final-compact-receipt-cds-20261017-111718.app 。最终覆盖前中间包备份：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-final-compact-receipt-cds-20261017-111906.app 。记录：.tmp/final-compact-receipt-cds/。

- 2026-10-17 11:13：按审查前三项完成灵动岛选中反馈、多会话摘要与隐私占位，并按用户补充要求精简额度入口；已备份覆盖安装，待用户自行验收。选中卡片在固定图标位使用陶土浅底，独立于特效／结果类型，按钮标记辅助功能“已选择”。紧凑态与底栏按待批准、失败、运行、完成、取消、结束分组，运行不重复包含待批准；随宽度在完整、两组与一组摘要之间降级，完整阶段数量保留悬停与辅助功能，空列表明确无运行任务。隐私卡片保持标题／状态／行高，详情合并为单条隐藏提示，同步精简提示与播报。顶部入口改为百分比＋细右箭头，保留原生玻璃、点击用量页与“查看额度与用量”说明。保留状态证据、监控／完成判断、排序／聚焦／收起计时、额度／空闲分支计数轮换、特效选项和礼花；未改最后完成回执的呈现时序。中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-island-summary-selection-cds-20261017-111317.app 。记录：.tmp/island-summary-selection-cds/。

- 2026-10-17 11:07：灵动岛状态表达与运行／结果卡片布局已重构并备份覆盖安装，待用户自行验收。仅在 ActivityIslandView 展示层映射状态图标、文字与颜色；完成绿色勾选、取消／普通结束中性、失败红色、待批准橙色并提示在 Codex 处理。固定 62 pt 行高与图标槽位，运行卡按标题／阶段、动作、模型／时长／累计用量分层，仅聚焦动作滚动；结果卡显示冻结耗时、本轮与累计用量，本轮值只读取匹配 session／turn 的已有用量，缺失或无效为“—”，隐私继续隐藏详情。紧凑态、卡片、底栏与辅助功能统一文案，取消／普通结束不作失败警示或播放运行特效。保留状态来源／结束证据、完成判定、聚焦排序／计数轮换、展开／收起计时、玻璃合成、三种特效选项与既有完成礼花触发。中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-island-session-layout-cds-20261017-110652.app 。记录：.tmp/island-session-layout-cds/。

- 2026-10-17 10:59：导出内部层级、额度健康色与套餐标签描边已统一并备份覆盖安装，待用户自行验收。文件名、未选格式与关闭的导出选项使用既有下沉表面，聚焦／选中保留陶土。桌面额度行／动态中心、菜单栏面板、灵动岛和浮动胶囊复用同一健康颜色函数：不少于 50% 绿、20%～49% 橙、低于 20% 红，缺失灰；不改额度计算、通知／预警逻辑及原生菜单栏模板图标。套餐标签移除内层描边，保留文字、浅底和尺寸。现有功能、陶土主色、数字与 CDS 动效、玻璃材质及透明度保持；中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-export-quota-polish-cds-20261017-105932.app 。记录：.tmp/export-quota-polish-cds/。

- 2026-10-17 10:54：额度重置记录卡圆角／描边与趋势悬停圆点底色已统一并备份覆盖安装，待用户自行验收。额度恢复监控卡复用既有普通卡片表面，底色和单层细描边统一 12 pt 圆角、轻阴影与增强对比处理；用量／成本趋势圆点内部改用所在重点卡片的 prominentCardFill，外圈保留青绿／陶土数据色。保留记录、通知状态、手动确认、来源链接、图表数据与悬停定位、尺寸／动效、陶土主色及原生玻璃。中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-record-trend-details-cds-20261017-105439.app 。记录：.tmp/record-trend-details-cds/。

- 2026-10-17 10:51：按审查前三项统一剩余独立卡片、社区动态／时间轴与记录类型选择浮层，已备份覆盖安装，待用户自行验收。导入／项目迁移预览、三种备份提示、额度／社区预测、来源／事件及分析页额度等 12 处独立卡片或条目复用既有普通卡片表面、轻阴影、单层细描边与增强对比处理；社区动态与时间轴移出下沉表面，事件卡移除重复外框但保留类型图标与文字状态色。选择浮层使用 elevated，保留原生 Popover、焦点／方向键／Esc 与选择行为。保留原圆角、尺寸、功能、陶土主色及玻璃合成；记录卡圆角和趋势悬停圆点未改。中英文 README 同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-remaining-card-depth-cds-20261017-105140.app 。记录：.tmp/remaining-card-depth-cds/。

- 2026-10-17 10:47：背景与卡片层级已调整并备份覆盖安装，待用户自行验收。桌面采用暖灰画布、较沉侧栏、普通／重点卡片与较低明度的嵌套区域，深色画布由近黑调整为暖炭灰。分析主卡片、普通卡片、设置分组与导出面板复用轻阴影和单层细描边，增强对比时提高边界辨识；说明浮层与项目详情使用较高表面。保留现有圆角／尺寸／布局与交互、陶土主色、青绿用量数据色和 CDS 动效；原生菜单栏／灵动岛玻璃合成、透明度及危险操作语义未改。中英文 README 已同步。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-surface-depth-cds-20261017-104729.app 。记录：.tmp/surface-depth-cds/。

- 2026-10-17 10:44：数据图表配色与重点摘要已调整并备份覆盖安装，待用户自行验收。桌面用量折线／面积、柱状图、热力图及项目摘要采用低饱和青绿；成本保留陶土，缓存分项使用暖沙色。两张概览的核心指标增加局部轻微衬底，日志来源的 Token／成本数值按相同数据色区分；菜单栏与灵动岛 Token 数值／热图同步，成本数值继续陶土。保留陶土主操作与选中态、统计／计价／来源与缺失数据口径、图表几何和悬停／周期／辅助功能／减少动态效果分支、玻璃材质与透明度、配额健康与危险操作语义。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-data-color-cds-20261017-104406.app 。记录：.tmp/data-color-cds/。

- 2026-10-17 03:45：三处滑杆已统一轻量样式并备份覆盖安装，待用户自行验收。背景不透明度、黑色遮罩比例与展开宽度共用现有自绘滑杆及数值行，使用 4 pt 中性／陶土轨道、16 pt 实色滑块、轻阴影、32 pt 操作高度和焦点提示；移除渐变、白色描边与中心点。保留 10%～90%／1%、20%～80%／1% 和屏幕动态宽度范围／1 pt 步进、连续指针跟随、最高 20 Hz 预览更新、结束时精确写入、拖动滚动互斥、方向键与辅助功能调整；减少动态效果时不缩放。玻璃材质与真实预览保持。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-light-sliders-cds-20261017-034523.app 。记录：.tmp/light-sliders-cds/。

- 2026-10-17 03:35：本轮三项细节已实现并备份覆盖安装，待用户自行验收。“查看待恢复”复用既有次级按钮反馈，保留定位操作；固定／收起／刷新／设置等圆形玻璃图标显式使用圆形焦点框，文字／卡片按钮保持圆角矩形，不改玻璃、尺寸和点击区域；ChineseDisplayText 在应用生成的文案中统一英文字母／数字与中文间距，恢复记录空状态应用该格式，不修改用户标题、路径或原始数据。滑杆按要求未改动，危险操作语义保留。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-final-ui-details-cds-20261017-033501.app 。记录：.tmp/final-ui-details-cds/。


- 2026-10-17 03:30：侧栏动效、桌面次要文字／分隔线令牌与中文数字间距已统一并备份覆盖安装，待用户自行验收。侧栏底板复用 CDS selectionMotion，与内容切换一致，减少动态效果分支保留；桌面次要文字、分隔线、图表网格／辅助线和增强对比边界收敛为语义令牌。ChineseDisplayText 仅在渲染端整理应用生成的计数和倒计时，概览次数标签与辅助功能共用格式，覆盖可见额度倒计时及菜单栏额度提示；不改底层时间计算、统计、来源证据、原始记录、用户标题和路径。按用户要求只构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-sidebar-text-spacing-cds-20261017-032951.app 。记录：.tmp/sidebar-text-spacing-cds/。


- 2026-10-17 03:25：导入／项目迁移预览、次级操作／搜索框和禁用态样式已统一并备份覆盖安装，待用户自行验收。两种预览共用紧凑身份策略选项与桌面文字／填充令牌；会话搜索增加聚焦边界和 24 pt 清除入口，近 30 日／查看全部／项目折叠／翻译接入既有次级反馈。按钮、分段、筛选、菜单入口、概览圆形控件与相关滑杆补齐启用条件，禁用时停止悬停／按压／焦点强调。保留导入／迁移校验、归属和冲突证据、目标选择、原有策略／操作／禁用条件，搜索输入法与 Esc、项目选择／展开、翻译及危险操作语义；未改业务服务。按用户要求只构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-import-secondary-cds-20261017-032456.app 。记录：.tmp/import-secondary-cds/。


- 2026-10-17 03:13：浮动界面 CDS 风格及剩余标签／描边／文字令牌已统一并备份覆盖安装，待用户自行验收。概览面板、岛体任务／用量／胶囊／重置页沿用暖中性文字、陶土强调，账户／接口／重置次数标签移除冗余边框，分隔线／缺失数据边界／提示框和紧凑字号令牌集中；CoreText 滚动文字复用不透明 RGB 色阶。危险操作保留红色填充、必要红色边界、白色按钮文字与红色焦点；原生玻璃／透明度／浅深自动、刘海黑色壳体、黑色重置卡、阴影、任务特效与布局、统计／隐私／重置确认流程保留。按用户要求只构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-floating-details-cds-20261017-031252.app 。记录：.tmp/floating-details-cds/。


- 2026-10-17 03:08：菜单入口与说明浮层已统一 CDS 呈现并备份覆盖安装，待用户自行验收。账号／活动范围、会话／动态筛选、导入目标、项目／会话更多操作和记录类型入口复用文字、尺寸、悬停与焦点规则；停留时间继续使用原生 Picker。数据范围说明、连接诊断和会话详情共用浮层表面与文字层级，关闭入口统一；原生 Menu／Picker、右键菜单内容、动作、选择与键盘处理及会话归属证据未改，现有自定义选择浮层只更新选中呈现。按用户要求仅构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-menus-popovers-cds-20261017-030752.app 。记录：.tmp/menus-popovers-cds/。


- 2026-10-17 02:59：旧按钮反馈、项目详情弹窗及导出面板已统一 CDS 样式并备份覆盖安装，待用户自行验收。MonitorCenterPressStyle 接入悬停、显式焦点环与 CDS 弹簧，禁用时停止悬停强调；项目详情统一字体／指标／路径和操作按钮；导出面板采用 16 pt 外壳、精简内层边框、文件名焦点强调、格式与范围选择状态、统一底部操作，清除重复禁用透明度。保留统计、项目会话跳转、文件名更新、原生目录选择、导出选项／进度／完成与原确认流程。按用户要求只构建 arm64 Release，未运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-dialogs-controls-cds-20261017-025905.app 。记录：.tmp/dialogs-controls-cds/。




- 2026-10-17 02:48：四个监控页与三张设置页已统一 CDS 桌面样式并备份覆盖安装，待用户自行验收。用量分析／成本估算／动态中心／会话管理共用暖中性表面、陶土强调、胶囊周期选择、图表／进度配色、轻量按钮与焦点反馈，弹层和侧栏一并统一。设置样板令牌收敛到 MonitorDesktopTheme，复用实际 CDS 弹簧参数；保留成功／警告／错误与事件类别语义颜色。未修改统计、计价、来源证据、归属、筛选及导入导出／恢复／删除的操作与确认逻辑；实际岛体和菜单栏面板材质保留。按用户要求只构建 arm64 Release，不运行测试或界面验收；未提交／发布。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-monitor-center-cds-20261017-024839.app 。记录：.tmp/monitor-center-cds/。


- 2026-10-16 21:41：统一玻璃外观与选择控件已安装，预览浅／深／经典回退及鼠标选择通过；真实岛体独立画面、实际系统浅深切换、动画中间帧未完成验收。选择面板 Down＋Return 未观察到值变化，键盘路径待核对，不宣称通过。偏好解析测试覆盖系统浅深及减少透明度，未修改系统外观。证据：build/glass-appearance-verified/。



- 2026-10-16 20:17：轻量刷新按钮已安装，默认外观和真实点击已实机检查；服务在 AX 采样前返回，加载文案／禁用状态／旋转未捕获，悬停／按压中间帧未录制，不宣称动态验收通过。证据：build/quiet-refresh-verified/。


- 2026-10-16 20:00：四处设置改造已安装并完成静态／滑杆实机检查；会话筛选菜单能展开，但选“已归档”时工具报告用户切换界面，已停止输入，筛选结果与逐帧动效未宣称通过。原透明度 50% 已恢复，会话仍为全部／139 条。证据：build/settings-controls-verified/。


- 2026-10-16 18:51：曲线／7 日柱形及周期边缘改造已实现并安装：单调三次曲线保留真实数据点和范围、共享面积路径；7 日 24 pt 细竖柱＋140 pt 高度＋逐日日期，月／小时更密；专用周期按钮去掉行样式额外内边距。完整测试与 arm64 Release／签名通过；已观察真实成本月视图平滑曲线。截图期间用户切页，停止自动操作，7 日柱形及按钮悬停边缘尚待实机补验，旧逐帧动画仍按此前选择延后。证据：build/chart-refinement-verified/。

- 2026-10-16 18:36：用量／成本分析页视觉与动效改造已实现并安装：紧凑范围工具栏、滑移周期底板、白色主指标、主次卡片边框、真实折线／面积插值、柱高／热图数据过渡与项目行反馈。完整测试及最终 arm64 Release／签名通过。实机确认用量周／月／三月和范围说明；用户明确选择“先看新版，动画稍后验收”，已停止界面操作。逐帧动效、成本页及项目展开／详情交互仍待验收，不移入最近完成。证据：build/analysis-polish-verified/。






- 复现菜单栏窄候选丢百分比、多项目 Token 页缺数量、纯图标后容量无法恢复三个边界，详见 Handoff。
- 已实机确认单会话的当前工具摘要、工作／思考状态切换、整卡效果、隐私遮挡及设置导航；真实等待批准、完成／取消的全过程仍待验收，自动回归不能替代该部分。
- 无 Hook 只读任务监控已接入并完成本机连接、工具／思考及已有完成状态验收；真实待批准／取消、睡眠重连和当前真实任务从活动到结束的完整过程仍待验收。桌面 IPC 为版本相关协议，不提供批准／回答；Hook 已移除，断线回退本地日志。证据：build/native-activity-20261016-031116/。
- 多屏切换、ControlCenter 系统拦截和真实多项目悬停验收未闭环；历史 design-qa.md 混有已撤回 Prompt 导航实验记录，不把旧 blocked 当作当前全部界面的状态。
- 设置页整理已实现并安装，完整测试与 arm64 Release／签名通过；实机确认阅读区遮蔽、中文导航、周月联动与默认菜单设置。独立活动范围与成本单日已在后续柱状图验收完成；项目详情跳转与 Hook 折叠交互仍待验收。旧 detailed 偏好仅映射为自动显示，原始值未改写。证据：build/settings-review-verified/。

## 最近完成

- 2026-10-29 03:05：v1.11.0（Build 33）双架构 DMG 已构建、校验，arm64 已备份覆盖安装。累计包含 Claude 流程／命令与公开摘要、Fast、岛内交互、渲染和日志降耗、重置卡到期提醒；本轮套餐显示更新为 Go／Plus／Pro100／Pro200／Pro500，修复官方价格表列顺序及 30m／12h 拆列导致的同步失败，统一“重置卡”文案。源码已推送 origin/main（7ae5ca1），远端提交核对一致；未创建 tag 或 GitHub Release。产物：build/CodexNotchMonitor-v1.11.0-arm64.dmg、build/CodexNotchMonitor-v1.11.0-x86_64.dmg；校验值：build/SHA256SUMS-v1.11.0.txt。

- 2026-10-29 02:36：Claude Bash 流程节点补上命令摘要并备份覆盖安装。Hook／转录均读取 description，节点显示“运行命令 · 描述”，缺少公开进展时动作行也使用命令摘要；无描述重复事件不覆盖，终态保留、换轮清空、长标题悬停查看；不展示原始命令参数。证据：.tmp/claude-command-summary/summary.json。未改 Hook 配置，未提交／推送。

- 2026-10-29 00:22：新增重置卡到期前 24／12／6 小时系统＋灵动岛提醒，已备份覆盖安装。按账号／卡片／到期时间持久化去重，重开只补当前最紧迫阶段；仅处理成功额度刷新中的可用卡，账号变化丢弃在途结果。“安装与权限”新增默认开启的开关。应用运行时复用每分钟刷新，不做退出后的系统定时投递。说明：docs/system-notifications.md；证据：.tmp/credit-expiry/summary.json。未提交／推送。

- 2026-10-28 22:47：蓝灯方框根因修复与 Claude 运行摘要合并安装。蓝灯 14 pt 灯芯保留，22 pt 圆环在 28 pt 绘制区域内呼吸，修复设置／真实卡片共用组件的裁切；Claude 复用当前轮公开文字作为摘要，工具事件不覆盖，审批优先，换轮清空。此前仅移除阴影未解决裁切，本条替代旧修复结论。证据：.tmp/pulse-clip/summary.json。未提交／推送。

- 2026-10-28 22:15：移除运行步骤蓝灯外层模糊阴影，保留圆形灯芯、半透明圆环与 1.2 秒呼吸；顶部状态灯原有光晕不变。已备份覆盖安装并启动，证据：.tmp/pulse-edge/summary.json。未提交／推送。

- 2026-10-28 22:02：按用户选定的 Playground C 方案移除任务卡片附加黑色渐变遮罩，保留原有玻璃材质、运行／完成特效及画质参数；已备份覆盖安装。仅修改 ActivityIslandFocusCard 背景叠层；证据：.tmp/remove-effect-shade/summary.json。未提交／推送。

- 2026-10-28 20:42：Codex／Claude 灵动岛状态与步骤语义统一并备份覆盖安装：共用三节点选择、顶部状态和节点渲染；保留已知成功／失败，未决调用在整轮结束后显示灰色；Codex 增加结构化工具失败证据，重复事件不重开，迟到结果不延长回执。无新增轮询／逐帧刷新。说明：docs/island-focus-stage.md；证据：.tmp/island-state-parity/summary.json。未提交／推送。

- 2026-10-28 19:45：Claude 工具步骤时间线已实现并备份安装，复用现有任务卡。按调用 ID 合并 Hook／日志，最多三个节点、运行／等待优先；独立失败／中性结束、换轮与迟到事件隔离、子 Agent 排除、重启补回有证据的步骤。终态迟到结果不重开任务或回执，未新增轮询与动画时钟。完整测试及 arm64 Release 通过，原生运行／等待／失败并行／取消静态图已检查；本机五个 Claude 会话均空闲，真实新任务显示待下次事件观察。证据：.tmp/claude-steps/summary.json；说明：docs/claude-code-integration.md。未提交／推送／发布。

- 2026-10-28 10:11：会话页派生结果复用、盘点进度合并与正文缓存裁减完成并备份安装。库存只保留元数据和 60 字回退标题，完整读取／导出仍读原始日志；进度中间更新约 100 ms 合并、首尾保留，查询／筛选／归属／路径／删除变化正确失效。464 文件独立探针保留文本 32.3 MiB→27 KiB，物理占用 67.4→35.5 MiB；1200 次派生读取含一次归属变化，重算 1200→2，结果一致。实机静止页平均 CPU 3.33%→3.37%，未证明下降；内存 363→316 MB 含重启影响，不全归因。完整测试、连续性 40／40、arm64 Release 与搜索／归档／恢复全部实机验证通过，测试窗口已关闭。证据：.tmp/session-page-perf/summary.json。未提交／推送／发布。

- 2026-10-28 00:38：修复监控重启后漏掉正在运行的 Claude 会话。启动时只读本地会话登记，校验 PID／UID／启动时间及 Claude 可执行身份，仅恢复 interactive busy；idle 不加入，恢复期间跟踪空闲／退出，新 Hook 接管后停止额外登记跟踪，不重建审批能力。真实登记 1 busy／4 idle，安装后 AX 确认 Claude 自动恢复为“正在继续执行”，随后 Bash Hook 接管，与 Codex 共 2 个活动会话。完整测试及 arm64 Release 通过，已备份安装，无需重启 Claude。证据：.tmp/claude-restart-recovery/summary.json；说明：docs/claude-code-integration.md。未提交／推送／发布。

- 2026-10-27 23:09：修复任务卡循环脉动带动 SwiftUI 更新及收起后展开宿主仅透明的问题；状态点／步骤节点改用原生图层动画，保留 1.2 秒节奏及原幅度，淡出后真正隐藏宿主，代次保护反向展开并保留草稿。完整测试、arm64 Release、347 项可见窗口回归通过，已备份安装。量子噪点／560 pt 同类场景 CPU 平均：流畅 61.1%→4.1%、均衡 44.4%→10.2%、省电 42.9%→9.4%；收起首测 10.0%（捕获 Claude 扫描）、后续复测 2.0%，原 40.9%。真实后台未冻结，不作档位排名或严格单因果收益结论。画质／Clawd／礼花源码保持，流畅与非置顶及设置页已恢复。证据：.tmp/island-refresh-fix/summary.json；说明：docs/island-focus-stage.md。未提交／推送／发布。

- 2026-10-27 19:46：修复 One／Codex Fast 识别并备份安装。根因为漏解析日志 event_msg.thread_settings_applied，纠正此前“日志无 Fast／需另接运行时”的判断；只接受归属当前 thread_id 的设置 checkpoint，跨轮保留、明确清除关闭，外来／无归属记录忽略。保持仅开启时显示 Fast。真实会话生产解析 fast=true，安装后 AX 确认「6 Astra · Medium · Fast」。报告：.tmp/one-fast-runtime/REPORT.md。未修改 One 或客户端配置，未提交／推送／发布。

- 2026-10-27 19:35：按用户要求，Fast 标签改为仅明确开启时显示「Fast」，关闭／未知／隐私均不显示，模型及辅助功能文本不留分隔符；完整测试、arm64 Release 和备份安装通过，实机 AX 确认未知标签消失。One 实际模式识别由上方后续修复完成。证据：.tmp/island-fast-label/REPORT.md。

- 2026-10-27 13:35：修复监控中心高 CPU 的无效 UI 更新链路并备份安装。审批 UI 改为独立 PassthroughSubject，逐次通知与 handle 校验不变；连接状态仅变化时发布。柱状图按输入等值跳过重建，日期／提示／柱高统一预计算，数字样式、locale／calendar／时区及真实数据变化仍更新。项目目录读取移到会话后台队列，缓存按大小／修改时间／inode 失效。固定 120 次上层更新含一次数据变化，三轮图表 CPU 中位 1.7175→0.3544 秒、重建 122→4 次，最终 PNG 哈希一致。新版实际周视图均值约 18.97%、月视图约 12.05%；实时前后视图／负载未严格一致，不据此宣称整应用降幅。保留动效帧率与实时监控，剩余开销以角色绘制为主。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-cpu-fix-20261027-012943.app 。未提交／推送／发布。

- 2026-10-26 16:53：高优先级性能优化已验证并备份安装。预览图片按 2560 px 上限即时解码并复用，设置预览外层不再重复订阅全 Store，内部实时面板保留订阅；历史统计按文件释放临时对象并复用日期解析器，流式读取按读取／解压块释放，会话目录按文件释放。关键 GB 级峰值定位到活动日志拆行：保留 Data 切片时逐行删除前缀造成整段缓冲反复 COW，改为单次遍历和独立行字节，保留半行、丢弃超长行及精确轮次／Token 规则。6,000 行与半行续写回归通过。60 次图片重绘三轮中位 5.7726→0.4051 秒；1,500 行固定日志峰值 400.39→6.86 MiB、状态与 Token 一致。最终 App 启动约 76 秒系统历史峰值 410.50 MiB、结束 219.75 MiB，未复现中间版 9–10 GiB 峰值；长期泄漏尚未做长时验证。回滚至本轮开始前：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-performance-opt-20261026-042050.app 。未提交／推送／发布。

- 2026-10-26 15:45：修复提醒岛体固定 380 pt 收窄及正文／按钮留白失衡：沿用配置的展开宽度，生产 SwiftUI 卡片测量自然高度并计入刘海避让；左右留白 28 pt，顶部 20 pt、底部 16 pt，内容间距 12 pt，按钮空间不足时竖排。保留配色、光效、图标、文案、操作路由与提醒调度。已备份覆盖安装 arm64 App 并启动；回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-alert-layout-20261026-034452.app 。README 中英文及提醒规格同步，未提交／推送／发布。

- 2026-10-26 01:19：Claude AskUserQuestion 新增 PreToolUse 接收、最多 4 题的单选／多选勾选／自定义回答、选项说明、按请求保留草稿及失效请求拦截。多选按原选项顺序以逗号分隔，回传保留完整原输入，PermissionRequest 与 PreToolUse 使用各自协议；超时／失联交回原客户端，不自动批准。已完整备份并覆盖安装 arm64 App，进程启动确认；回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-claude-island-choices-20261025-131911.app 。中英文 README 与接入说明同步，未提交／推送／发布。

- 2026-10-24 03:54：修复已结束轮次的异步回答误用 steer-turn：活动轮次继续 steer，已结束轮次采用受限 start v2，并由 owner 继承原设置；补全 restoreMessage，只有回执对应轮次的实际回答内容匹配才确认成功。旧夹具加入真实拒绝规则后稳定复现 outcomeUnknown；新投递探针及隔离完整测试通过。已完整备份并安装 arm64 修复版，进程已确认。回滚 App：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-async-reply-delivery-20261023-155439.app 。说明：docs/island-async-question-fix.md。

- 2026-10-24 03:23：v1.10.0 正式发布为 Latest。46 个相关文件已提交，main 与附注标签已推送，Apple Silicon／Intel DMG 和校验清单已上传；发布后重新下载三个附件，哈希与 GitHub digest 均一致，线上 README 与本地一致，发布标签的 133 个构建输入与打包快照一致。未安装。Release：https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.10.0 。

- 2026-10-24 03:23：v1.10.0（Build 32）发行准备完成。纳入当前灵动岛提醒、文字回答／中文组字、跨轮次请求保留、三档礼花／提示音、通知与设置改进；中英文 README、版本和下载链接同步。双架构 DMG 与 SHA256SUMS-v1.10.0.txt 已生成。

## 最近验证

- 2026-10-29 03:06：v1.11.0 源码提交 7ae5ca1b8b42141531726e32f681a09719fb326b 已成功推送 origin/main，git ls-remote 与本地 HEAD 一致；打包后全部源码／资源输入哈希未变化。双 DMG 保留本机 build/，未上传 Release；本机交接笔记、design-qa.md、缓存及发布素材目录未提交。

- 2026-10-29 03:05：最终完整 scripts/test.sh 通过；新旧官方价格表、按列名读取／列重排／异常数值及真实 HTTPS 更新验证通过，安装后的界面确认官方费率成功同步、“重置卡到期提醒”及 v1.11.0／Build 33。实际 Claude 任务已显示公开进展与命令描述。双架构 DMG 校验、只读挂载、主程序／Helper 架构、严格签名、逐文件 SHA-256 比对通过；未做 Intel 真机运行。证据：.tmp/release-1.11.0/artifacts.json、.tmp/plans-pricing/tests-final.log、.tmp/plans-pricing/live.log。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-v1.11.0-20261029-030215.app。

- 2026-10-29 02:36：命令摘要账本定向检查、完整 scripts/test.sh、arm64 Release、签名／备份及安装哈希通过。覆盖 Hook／日志补全、重复／终态、无效／空／长描述、运行态兜底与隐私；原生合成渲染确认节点及动作行显示命令描述。12 份近期日志尾部结构统计中 151 次 Bash 均有 description；安装后的真实 Claude 下一次命令尚未观察。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-claude-command-summary-20261029-023629.app。

- 2026-10-29 00:22：重置卡提醒定向测试、完整 scripts/test.sh、最终 arm64 Release、严格签名／备份及安装哈希通过。覆盖阈值、重启、补发、账号隔离、重复卡、已用／过期／未知、到期时间变更及队列开关；安装后设置实机确认开关开启、系统通知已允许。未等待真实卡片未来到期节点。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-credit-expiry-20261029-002132.app。

- 2026-10-28 22:47：完整 scripts/test.sh、最终 arm64 Release、安装哈希／严格签名通过；面板 337／337、Claude 新增公开摘要／工具回调／审批／换轮／旧文本／thinking／sidechain／隐私回归通过。设置普通预览实机确认圆环无方形裁切；放大预览安装后复核因窗口不可用未完成，真实 Claude 摘要待下一次公开进展观察。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-pulse-clip-summary-20261028-224529.app。

- 2026-10-28 22:15：蓝灯边界修复的隔离原生像素检查通过：圆环外采样区域无阴影残留，灯芯颜色与修改前一致；面板 336／336、完整 scripts/test.sh、arm64 Release、备份／安装哈希及签名通过。未录制真实任务连续动画。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-pulse-edge-20261028-221453.app。

- 2026-10-28 22:02：去遮罩版本完整 scripts/test.sh 与 arm64 Release 通过；面板 334／334、状态 187／187、连续性 40／40、Claude Runtime 及审批 350 项通过。运行／完成态合成原生静态图已检查，安装后真实会话恢复、展开布局已验收；未测动态性能。备份及安装哈希、严格签名通过。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-remove-effect-shade-20261028-220121.app。

- 2026-10-28 20:42：状态对齐完整 scripts/test.sh 与 arm64 Release 通过：状态 187／187、面板 334／334、连续性 40／40、审批 350 项及 Claude Runtime 通过；8 张生产视图合成原生对照图已检查。备份及安装文件哈希、签名通过，启动后真实 Codex 当前步骤／Fast 可见；真实 Claude 本轮状态转换未现场覆盖。回滚包：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-island-state-parity-20261028-204205.app。

- 2026-10-28 19:45：最终 scripts/test.sh 退出 0，含步骤去重／并行／等待／失败／取消／旧轮与子 Agent 排除／延迟匹配／终态不重开／重启日志恢复及原有审批 350 项；独立步骤回归通过。arm64 Release、架构与 deep／strict 签名、备份与原包及安装与构建哈希通过，输入未变。四张生产组件原生静态图已检查；未触发真实 Claude 任务或审批，安装启动已确认。以 .tmp/claude-steps/full-tests-final.log、build-final.log、summary.json 为准。

- 2026-10-28 10:11：scripts/test.sh 与定向连续性均退出 0（40／40）；新增缓存失效、原始／压缩正文读取保真、冷暖盘点、错误文件进度与原文件不变检查通过。arm64 Release、架构／签名、安装及备份哈希通过，源测试输入未变。实机 174 条会话→搜索 12→归档 29→恢复 174，折叠状态恢复；同页各 60 秒 CPU 后接独立采样，平均基本不变，单轮峰值 26.6%→13.7% 仅作观察。943 MB 历史峰值未完整归因。证据：.tmp/session-page-perf/。

- 2026-10-28 00:38：重启恢复 scripts/test.sh 退出 0，Claude 核心 112 项、启动恢复 Runtime（busy／idle、PID 生命周期、无审批、真实 Hook 接管）、连续性及审批 350 与既有 Runtime 均通过；独立恢复回归退出 0。arm64 Release／架构／签名、备份与旧包及安装与构建全文件哈希通过。实机重启监控后已有 Claude 任务立即恢复，随后正常收到 Bash；未重启 Claude、未发送测试任务或处理真实审批。首轮专项因补充进程复核时源码修改中止，以 full-tests.log 和 runtime-registry.log 为准。证据：.tmp/claude-restart-recovery/。

- 2026-10-27 23:09：scripts/test.sh 退出 0，含面板常规 325、连续性 37、审批 350 与 Claude Runtime；最终可见面板专项 347／347，覆盖异步隐藏通知、减少动态、快速反向、原宿主复用、隐藏时 Metal 时钟和原生脉动停止、再次展开恢复。更新旧全卡渲染不适用的进度前沿断言，改验真实绘制时钟。arm64 Release、版本／架构／签名、安装与构建及备份与旧包哈希通过，源码输入未变。三档各 60 秒 CPU 后接 5 秒采样、不重叠；收起两次 30 秒均保留。单轮真实工作负载，未直接测 GPU／能耗。日志：.tmp/island-refresh-fix/。

- 2026-10-27 19:46：One Fast 新回归旧代码失败 7 项，修复后会话状态 173／173；完整 scripts/test.sh、arm64 Release 退出 0，含 Native 76、面板 311、连续性 37、审批 350 与 Claude Runtime。真实日志 checkpoint priority 经生产解析得到 Fast，实机 AX 确认当前会话显示 Fast；关闭／再开启／跨轮／归属／非法值在隔离夹具验证。架构、签名、安装／备份全文件哈希与构建输入通过。证据：.tmp/one-fast-runtime/。

- 2026-10-27 19:35：Fast 标签 scripts/test.sh 退出 0（会话状态 163、Native 76、面板 311、连续性 37、审批 350 与 Claude Runtime），arm64 Release、架构／签名、安装与备份逐文件哈希通过；实机 AX 当前会话模型文本不含 Fast 未知／关。One 源码与本机协议只读核对，未测试真实 Fast 开关识别。证据：.tmp/island-fast-label/。

- 2026-10-27 19:25：Fast 显示最终 scripts/test.sh 退出 0（会话状态 163、Native 76、面板 311、连续性 37、审批 350 与 Claude Runtime），实际 Helper 合成状态栏开关、异常类型与跨会话测试通过；arm64 Release、架构、签名、安装／构建及备份／旧包逐文件哈希通过，源码输入未变。实机 AX 确认 Fast 未知；截图仅捕获收起状态，真实 Claude 开关与展开排版未验收。首轮脚本因编辑时编译中止，以 tests-final.log 为准。证据：.tmp/island-fast-mode/。

- 2026-10-27 15:56：SwiftUI 刷新修复 scripts/test.sh 唯一一次退出 0（Tibo 68、额度恢复 18／18、连续性 37／37、面板 311／311、审批 350）；唯一一次 arm64 Release、源包／安装包签名与逐文件哈希通过，备份与原包一致。启动满 137.6 秒后完成一次 top／6 秒 sample；记录定位与场景限制，未追加界面 QA。证据：.tmp/swiftui-frame-loop/REPORT.md。

- 2026-10-27 15:31：Clawd 岛内版 scripts/test.sh 完整一次退出 0（角色 541、面板 311、硬件黑 50、预览 59、连续性 37、审批 350），build-app.sh arm64 一次退出 0；主程序／Helper arm64、deep／strict 签名、完整备份与安装哈希均通过，git diff --check 通过。启动 129 秒后完成 13 次 top／6 秒 sample，帧表 8 张＋静态 7 张导出；单次 screencapture 失败，严格空闲对比与实机显示未验证。证据：.tmp/clawd-in-island/。

- 2026-10-27 14:55：动效降耗 A：scripts/test.sh 完整退出 0，含面板 311、预览 59、连续性 37、Claude 核心 95、审批 350 与 Runtime；最终 arm64 Release、主程序／Helper 架构、deep／strict 签名通过，备份与旧包、安装与构建逐文件哈希一致，启动进程已确认。截图失败，锁屏／睡眠／低电量／过热切换未实机验收，受控性能未验证。证据：.tmp/island-effect-perf-a/REPORT.md、tests.log、build-final.log、install.json。

- 2026-10-27 13:35：scripts/test.sh 完整退出 0，新增图表日期／时区／样式／空值与缓存重复读取／同大小同日期原子替换／归属更新／非法 JSON／恢复／删除检查通过；连续性 37、Native Activity 76、审批 350、Claude 核心 95 及 Runtime 通过。arm64 Debug／Release、主程序与 Helper 架构、deep／strict 签名、安装／构建及备份／原包哈希通过，验证输入未变。离屏前后 PNG 逐字节一致，独立样式切换触发重建并渲染为 K 单位；实机 AX 验证周／月切换及 7／30 根柱的数据和标签。首轮完整脚本因旧探针仍使用双参数回调编译失败，已适配新增后台目录返回值，以 full-tests-final.log 为准。证据：.tmp/cpu-fix-20261027/summary.json、chart-benchmark.json、chart-style-probe.log、full-tests-final.log、release-build.log、actual-after.log、actual-after-month.log、sample-after.txt、install.json。

- 2026-10-26 16:53：scripts/test.sh 完整退出 0；流式读取 20、模型 128、桌面预览 59、面板 311、连续性 37、Claude 核心 95、审批 350 与 Runtime 通过；成本冒烟通过。arm64 Release／主程序与 Helper 架构、deep／strict 签名、安装／构建与备份／原包逐文件哈希通过，验证输入哈希未变。预览前后离屏图已检查；固定压缩输入首尾摘要 SHA-256 一致。旧真实历史探针两次超过 1.5 GiB 诊断上限，新版文件作用域完整扫描 90,914 条事件峰值 306 MiB；旧活动探针约 0.87 秒超过上限，拆行修复后完整活动扫描约 141 MiB。早期仅修复统计／共享读取的安装版仍有多 GiB 峰值，均未算验收通过；启动期完整采样和独立活动复现最终定位 COW。Allocations 录制未导出有效报告，已停止，不作为结论依据。最终证据：.tmp/performance-opt/performance-summary.json、full-tests-verified.log、release-build-verified.log、line-benchmark-summary.json、startup-summary-verified.json、install-verified.json。

## 验证与产物入口

- v1.8.4：build/releases/v1.8.4/；构建／镜像／公开附件证据：.tmp/release-v1.8.4/；安装前备份：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-v1.8.4-20261017-210741.app 。

- v1.8.3：build/releases/v1.8.3/；构建／镜像／公开附件证据：.tmp/release-v1.8.3/；安装前备份：build/backups/CodexNotchMonitor-before-v1.8.3-20261017-182142.app。

- v1.8.1：build/releases/v1.8.1/；构建／镜像／公开附件证据：.tmp/repo-rename/；安装前备份：build/backups/CodexNotchMonitor-before-v1.8.1-20261017-123214.app。

- v1.8.0：build/releases/v1.8.0/；构建／镜像／公开附件验证：.tmp/release-v1.8.0/；本机安装前完整备份：build/backups/CodexNotchMonitor-before-v1.8.0-20261017-121825.app。

- 常驻额度／空闲横幅：build/persistent-idle-20261016-110820/；回滚：build/backups/CodexNotchMonitor-before-persistent-idle-20261016-110820.app。新标准实机连续 5 分钟验收已通过：build/persistent-idle-verified/。

- 全阶段 Hook 准入修复：build/hook-admission-all-20261016-104002/；回滚备份：build/backups/CodexNotchMonitor-before-hook-admission-all-20261016-104002.app。

- Hook 准入／完成 Token／礼花证据：build/hook-identity-completion-20261016-032844/；本轮前完整回滚：build/backups/CodexNotchMonitor-before-hook-identity-20261016-032457.app。

- 无 Hook 只读监控最终证据：build/native-activity-20261016-031116/；安装前完整回滚：build/backups/CodexNotchMonitor-before-hookless-20261016-031116.app。

- C 额度胶囊证据与无 Hook 调研：build/island-usage-capsule-20261016-024632/；回滚备份：build/backups/CodexNotchMonitor-before-usage-capsule-20261016-024632.app。

- 完成态／材质修复证据：build/completion-glass-parity-20261016-023914/；回滚备份：build/backups/CodexNotchMonitor-before-completion-glass-20261016-023914.app。

- 紧凑态／Token／内容／自动收起最终证据：build/island-compact-parity-20261016-021858/；包含完整测试、Release 构建、旧状态机复现、结构化审查、安装与启动清单。本轮开始前完整回滚备份：build/backups/CodexNotchMonitor-before-compact-parity-20261016-020604.app。
- B2 逻辑清理与差异修复最终测试、构建、结构化审查及安装证据：build/island-parity-review-20261016-012953/。本轮开始前完整回滚备份：build/backups/CodexNotchMonitor-before-parity-review-20261016-012618.app。
- B2 最终完整测试、arm64 构建、源码来源与资产哈希、实际 UI 观察及安装证据：build/activity-island-b2-20261016-010500/。
- B2 开始前完整回滚备份（B 阶段）：build/backups/CodexNotchMonitor-before-b2-20261016-004844.app。最终设置修正前的中间开发包另存于 build/backups/CodexNotchMonitor-before-b2-20261016-010500.app。
- B 完整测试、arm64 构建、可见面板 QA、原生样例截图、源码复用记录及安装证据：build/activity-island-b-20261016-000740/。
- B 安装前完整备份（A 阶段）：build/backups/CodexNotchMonitor-before-activity-island-b-20261016-000740.app。
- A 完整测试、arm64 构建、安装前后哈希及启动证据：build/activity-session-a-20261015-233744/。
- A 安装前完整备份：build/backups/CodexNotchMonitor-before-activity-session-a-20261015-233744.app。
- v1.6.10 发布测试：build/v1.6.10-full-tests.log；构建日志：build/v1.6.10-arm64-build.log、build/v1.6.10-x86_64-build.log；发布说明：build/release-notes-v1.6.10.md；校验文件：build/SHA256SUMS-v1.6.10.txt。
- v1.6.10 安装前备份：build/backups/CodexNotchMonitor-before-v1.6.10-20261002-114340.app。
- 社区格式适配测试：build/community-schema-tests-20261002.log；arm64 Release 构建：build/community-schema-arm64-build-20261002.log。
- 社区格式适配安装前备份：build/backups/CodexNotchMonitor-before-community-schema-20261002-113545.app。
- v1.6.9 发布测试：build/v1.6.9-full-tests.log；构建日志：build/v1.6.9-arm64-build.log、build/v1.6.9-x86_64-build.log；发布说明：build/release-notes-v1.6.9.md；校验文件：build/SHA256SUMS-v1.6.9.txt。
- v1.6.9 安装前备份：build/backups/CodexNotchMonitor-before-v1.6.9-20260930-153715.app。
- GPT-6 计费适配测试：build/gpt-6-pricing-tests-20260930.log；arm64 Release 构建：build/gpt-6-pricing-arm64-build-20260930.log。
- GPT-6 计费适配安装前备份：build/backups/CodexNotchMonitor-before-gpt6-pricing-20260930-150347.app。
- v1.6.8 发布测试：build/v1.6.8-full-tests.log。
- v1.6.8 构建日志：build/v1.6.8-arm64-build.log、build/v1.6.8-x86_64-build.log；发布说明：build/release-notes-v1.6.8.md；校验文件：build/SHA256SUMS-v1.6.8.txt。
- v1.6.8 安装前备份：build/backups/CodexNotchMonitor-before-v1.6.8-20260928-210459.app。
- CLI 路径修复测试：build/cli-path-fix-full-tests-20260928.log；Debug／Release 构建日志：build/cli-path-fix-debug-build-20260928.log、build/cli-path-fix-release-build-20260928.log。
- CLI 路径修复安装前备份：build/backups/CodexNotchMonitor-before-cli-path-fix-20260928-185332.app。
- 本次发布测试：build/v1.6.7-full-tests-20260911.log；构建日志：build/v1.6.7-arm64-build-20260911.log、build/v1.6.7-x86_64-build-20260911.log。
- arm64／x86_64 DMG：build/CodexNotchMonitor-v1.6.7-arm64.dmg、build/CodexNotchMonitor-v1.6.7-x86_64.dmg。
- 本次发布说明：build/release-notes-v1.6.7-20260911.md；校验文件：build/SHA256SUMS-v1.6.7.txt。
- 安装前备份：build/backups/CodexNotchMonitor-before-v1.6.7-20260909-153000.app。
- 完整哈希和源码风险定位见 NEXT_CHAT_HANDOFF.md；不重复维护历史版本列表。