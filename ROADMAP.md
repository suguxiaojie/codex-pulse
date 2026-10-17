# Codex Pulse Roadmap

## 项目目标

原生 macOS 应用，集中展示 Codex 官方额度、本地 Token／成本、任务状态、社区信号与会话管理；保持不同数据来源和账号归属的证据边界。

## 当前阶段

GitHub 仓库为 suguxiaojie/codex-pulse，v1.8.3（Build 29）已正式发布，源码提交为 dfe6fe07ed1a08fe1e4ca78b9025ad575c1d2371，已推送 main。待回复视觉与单次提示动效已由用户实测确认：首次提醒后静态等待，回答后提示淡出并恢复运行。arm64／Intel 独立 DMG、签名、CRC、镜像内容及公开附件下载哈希核对通过，本机已备份安装 arm64 版。按用户要求未运行自动化测试或额外 UI 验收，Intel 无真机验收；工作区 AnalysisPresentation.swift 的另有界面改动保持未提交，未混入发行包。

当前本地开发包展示名称为 Codex Pulse，配套原创“脉点”品牌；Bundle ID、可执行文件、安装路径、偏好键与数据目录沿用 CodexNotchMonitor，不迁移现有配置和数据。

本地开发交接笔记不随公开发行包上传；历史版本变化以 Git 历史为准。

## 进行中与待办

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

- 2026-10-17 18:23：发布 v1.8.3（Build 29）待回复视觉与单次提醒，源码提交 dfe6fe07ed1a08fe1e4ca78b9025ad575c1d2371 已推送 main，远端 tag 指向同一提交，GitHub 为最新正式 Release。按结构化问题标识在紧凑／展开界面共用去重，首次可见时轻提示，持续等待为静态图标及细轮廓，回答后恢复原运行效果；保留隐私、减少动态、玻璃及原交互。用户已实测确认核心动效流程；两架构包及三份公开附件下载校验通过，本机已完整备份安装。未运行自动化测试或额外 UI 验收，Intel 无真机验收，工作区无关界面改动排除。发布页：https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.8.3 。证据：.tmp/release-v1.8.3/；产物：build/releases/v1.8.3/；回滚 App：build/backups/CodexNotchMonitor-before-v1.8.3-20261017-182142.app。

- 2026-10-17 18:05：v1.8.2（Build 28）已提交推送并发布双架构 Release，源码提交 f094ef28b37861fdc567b90424d6f995001a8bc3。发布内容为用户已确认的“待回复”识别与回答后恢复修正，不含后续动效调整；arm64／x86_64 DMG 和 SHA256SUMS.txt 已上传，公开下载与本地产物／GitHub digest 相同，本机已备份安装。未运行自动化测试或额外 UI 验收，Intel 无真机验收。发布页：https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.8.2 。证据：.tmp/release-v1.8.2/；产物：build/releases/v1.8.2/；安装前备份：build/backups/CodexNotchMonitor-before-v1.8.2-20261017-175402.app。

- 2026-10-17 12:33：GitHub 仓库更名为 suguxiaojie/codex-pulse，简介与 origin 同步，原 Release／附件保留；v1.8.1（Build 27）双架构修正版已发布，源码提交 7bf4a6cce19c3aaa3b9990b4c0669595afe791e7 已推送并作为远端 tag。修正 AppUpdateService 指定仓库常量，保留严格校验，README 与测试夹具 URL 同步；旧 v1.8.0 需手动安装一次。发行包从独立快照构建，仅包含本轮指定源码改动，未包含工作区界面变化；本机已完整备份安装并确认进程。未运行测试或 UI 验收，配置与数据标识不改。发布页：https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.8.1 。回滚 App：build/backups/CodexNotchMonitor-before-v1.8.1-20261017-123214.app。证据：.tmp/repo-rename/；产物：build/releases/v1.8.1/。

- 2026-10-17 12:20：发布 Codex Pulse v1.8.0（Build 26），源码提交 f7ec22a9dd047abe25705f906dc822709585fa09 已推送 main，tag 指向同一提交，GitHub Release 为最新正式版本。汇总品牌／原生 CDS 界面／灵动岛／概览／项目摘要与完整移除 Hook；中英文 README 各 128 行，采用用户提供的 9 张截图并保留安装、数据边界与源码构建入口。双架构独立 DMG、SHA256SUMS.txt 已上传并下载复核一致；DMG 显式 HFS+／UDZO，两架构包检查通过。本机已备份覆盖安装 arm64 新版并确认启动；未运行测试或 UI 验收。发布页：https://github.com/suguxiaojie/codex-notch-monitor/releases/tag/v1.8.0 。证据：.tmp/release-v1.8.0/；产物：build/releases/v1.8.0/。

- 2026-10-17 11:42：用户反馈本轮面板精简效果不佳，已撤回页头合并／原生周期菜单／底部入口及菜单跟踪保护，恢复上一版阅读衬底、Token 前置／并列、成本空状态和动态高度。三份源码按本轮精确反向补丁回滚，与改动前快照逐文件一致；中英文 README 撤回对应描述，保留其他未提交改动。当前 App 与 build App 从既有上一版完整备份恢复并启动，未重新构建、测试或界面验收。恢复来源：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-glance-chrome-controls-cds-20261017-113949.app 。被撤回版本完整备份：/Users/zuxinchen/Documents/ChatGPT/Codex额度监控macbook插件。/build/backups/CodexNotchMonitor-before-rollback-glance-chrome-20261017-114200.app 。证据：.tmp/rollback-glance-chrome/install.json、source-change.patch。

- 2026-10-16 23:08：设置工作台按最新要求改造：菜单栏嵌入真实 GlanceView／MonitorStore 与原生玻璃，只读预览随开关联动；灵动岛完整场景在顶部独占一行，下方自适应双列控制，保留放大预览。移除其他模型额度展示／开关及高度分支，内容共 7 项；Credits 按原始十进制字符串分组去尾零并保留有效小数。中英文 README 同步，完整测试与 arm64 Release 通过，备份覆盖安装并实机检查，未提交／发布。

- 2026-10-16 22:12：精简安装与权限页，移除独立“环境与连接”卡片与“重新运行引导”入口及无引用重置调用；首次引导继续保留。CLI 路径／连接回退与验证说明收进原生任务监控行的连接诊断信息弹层，“刷新状态”移入同一行。中英文 README 同步，未改客户端配置或账号／会话数据；未提交或发布。

- 2026-10-16 21:58：用户确认原生监控试用正常，完整移除生命周期 Hook：事件模型／映射／收件箱／定时器／任务合并与结束回退、安装审核服务／界面、Helper target、安装卸载脚本和打包入口；引导收敛为欢迎／环境／通知三步。备份后移除本机 9 个插件处理器、独立 Helper、events、审核启动器／偏好和旧 setup-backups；其他 17 个处理器保留，本插件命令为 0。两级 App／配置备份保留，README 中英文、AGENTS 与本地说明同步；未提交／发布。

- 2026-10-16 21:41：复用 QuotaView 0.8.3 scoped 浅／深／自动外观、公开 AppKit KVO、前景对比和共用 clear 玻璃；底栏／胶囊／预览统一，顶部与内容卡片仍深色，重置主卡纯黑保留。旧胶囊配色值保留但不读取，经典／减少透明度回退深色实体。记录类型／停留时间换为统一细描边选择入口及焦点可见的弹出选项；权限页三个轻量文字按钮，通知／更新状态提亮并增加状态图标。完整测试与 arm64 Release 后备份覆盖；Hook 保持屏蔽，未提交或发布。

- 2026-10-16 20:40：v1.7.0（Build 25）正式发布：中英文 README、必要源码／测试／依赖许可已提交并推送 main，标签指向 0f84eff；两个独立架构 DMG 与 SHA-256 清单已上传正式 Release。轻量按钮圆角同步为用户选择的 14 pt。本地交接笔记、验收日志、缓存和发布物料未上传。发布：https://github.com/suguxiaojie/codex-notch-monitor/releases/tag/v1.7.0 。

- 2026-10-16 20:17：按用户选定“轻量文字”统一四个监控页标题栏的刷新／重新检查：默认无底色、悬停轻底色、按压轻收缩；加载跟随真实服务状态，旋转图标＋状态文字替代额外进度圈，固定文案占位避免宽度跳动，禁用重复点击，减少动态效果下停止旋转。未改刷新与会话检查逻辑，Hook 继续屏蔽。完整测试／arm64 Release／签名通过并备份覆盖安装。

- 2026-10-16 20:00：移除菜单栏任务、密度及内容选择入口，运行时固定圆环＋百分比，旧偏好保留但不再生效；透明度复用灵动岛连续拖动／松手回稳滑杆并增加拖动期间滚动互斥；内容／外观复用滑移导航；会话搜索、状态菜单与导入／导出／详情使用统一轻描边控件。未改会话读取、导入导出和归属逻辑，Hook 仍屏蔽。完整测试与 arm64 Release 后备份覆盖安装。

- 2026-10-16 19:03：日志来源重排为并列 Token／API 等价成本，独立对齐官方与补充目录同步行，模型映射收进计价说明，未定价提示保持可见。动态中心复用滑移导航与悬停样式，移除原生灰色分段／筛选样式，来源降为辅助信息。未改统计、价格、关联或 Hook 数据；完整测试／arm64 Release 通过并备份覆盖安装。

- 2026-10-16 18:04：按用户要求将历史社区线索直接自动标记：匹配后备份并保存 communityAssociation，自动显示 Tibo 重置、进入 Tibo 分类并退出待确认列表，无需逐条操作；重启保留，重复刷新不重复标记／备份。原始 reason／ID／额度变化／来源与既有人工分类保留，人工显示分类优先，来源时间差异留在可展开依据中；不补发旧通知。实际 18 条中自动标记 5 条，2 条保留未明；Hook 继续屏蔽，已备份覆盖 arm64 安装版。


- 2026-10-16 17:13：日志来源接入官方费率自动更新：每 24 小时只读取 OpenAI pricing.md 的 Standard 支持模型表，线上官方费率优先于内置快照与社区目录，解析长短上下文倍率后重算实际成本。分开显示官方同步时间与补充目录同步时间；网络／schema 异常保留最后有效价格与日期，6 小时后重试，304 需可用缓存，服务器取消 ETag 时清除旧标签。缓存仅在 Library/Caches，未改账号／会话／Hook，Hook 继续屏蔽；已备份覆盖安装 arm64 开发版。

- 2026-10-16 17:00：成本与 Token 活动统一青蓝色视觉与交互：柱子和热力格复用同一填充／3 pt 圆角／0.7 pt 描边组件，零值中性暗灰；详情栏共用右上方排版与数字字体，热图取消半秒延迟、黑胶囊及虚线占位。悬停统一轻微提亮／细描边，成本热图补对应 Token，按有效范围触发共同淡入过渡并尊重减少动态效果。计价、账号与日志链未变，Hook 继续屏蔽；完整测试／arm64 Release 后备份覆盖安装。

- 2026-10-16 16:44：成本与 Token 活动改为短周期柱状图、长周期热力图：成本日视图复用真实小时序列，周／月及独立 30 日按天，90 日／半年保持热力图；未来小时留空、零值不抬高，悬停显示精确值及成本对应 Token。两页共用柱状图，移除常驻悬停提示；未改计价、账号归属或日志扫描，Hook 继续屏蔽。完整测试／arm64 Release 通过并备份覆盖安装。

- 2026-10-16 15:55：去掉菜单栏多余宽度占位：先更新圆环、字体和标题，再以 AppKit cellSize 测量真实内容宽度，不将候选预算或轮播预算作为可见槽宽。当前圆环＋36% 的按钮从 66 pt 收紧到 50 pt；同时修正无任务时紧凑模式丢掉额度候选。保留现有任务显示选项与其他设置，Hook 仍屏蔽；已备份覆盖 arm64 安装版。

- 2026-10-16 15:45：HTML 大图加入鼠标锚点滚轮缩放、指针捕获拖动、双击／按钮／0 还原、+/− 键盘缩放及实际像素比例显示；切图与重开清除偏移，窗口变化重新适配并限制边界。实测发现 108×66 小图放大后仍小于画布而被锁住，修正为小图可在画布内移动、大图按边缘限位。未改图片恢复、脱敏或备份链，Hook 保持屏蔽；完整备份后覆盖 arm64 安装版并确认运行。

- 2026-10-16 15:22：补齐可读导出用户引用图片链：结构化内嵌图片优先，支持现存本地图片及文本图片信封回退；静态 PNG 重编码不复制 EXIF／GPS，像素不自动遮盖。HTML 单文件内嵌缩略图与原生 dialog 大图，前后／方向键／Esc／焦点返回；Markdown 生成同名 .assets 相对素材，按内容复用，冲突拒绝覆盖，失败只清理本次新建素材。缺失／损坏／远程引用／超限明确提示。修正全局文字去重造成跨轮图片与重复问题合并，改为仅相邻双格式镜像去重；清除图片闭合信封。保留正文脱敏与备份链，Hook 仍屏蔽；已备份覆盖 arm64 安装版。

## 最近验证

- 2026-10-17 18:23：v1.8.3 公开发布核对：latest API 为 v1.8.3 正式版，main 与远端 tag 的源码提交均为 dfe6fe07ed1a08fe1e4ca78b9025ad575c1d2371；两份 DMG 与 SHA256SUMS.txt 公开下载后的 SHA-256 和 GitHub digest 逐一等于本地产物。独立快照的 Sources／Resources／Package 与打包脚本逐文件等于发行提交，未混入工作区界面改动。用户已确认单次提醒、静态等待及回答后恢复；未运行自动化测试或额外 UI 验收。证据：.tmp/release-v1.8.3/public-release.json、public-download-review.json、source-scope-review.json。

- 2026-10-17 18:22：v1.8.3 发行包检查通过：两架构均为 1.8.3 Build 29，arm64／x86_64 精确匹配，签名有效、DMG CRC 有效，镜像 App 与对应构建快照逐文件 SHA-256 一致，Applications 链接正确，SHA256SUMS.txt 已生成。本机覆盖前完整备份与目标一致，安装与 arm64 源包一致，启动进程已确认。八份动效相关源码与用户验收版本相同，仅追加版本元数据；现有界面改动未混入。README 九张图片与本地链接有效；未运行自动化测试或额外 UI 验收，Intel 无真机验收。证据：.tmp/release-v1.8.3/package-review.json、install.json、source-scope-review.json、arm64-build.log、x86_64-build.log。

- 2026-10-17 18:13：待回复动效 arm64 Release 构建退出 0；源包、安装 App 和完整备份均为 Codex Pulse／1.8.2 Build 28／arm64，签名有效，备份全包哈希与覆盖前目标一致、安装全包哈希与源包一致，启动进程已确认。八份变更源码与独立构建快照 SHA-256 一致，其他编译输入来自发布提交，既有工作区界面改动未混入。编译警告 18 条，与上次相同，无新警告；git diff --check 通过。按用户要求未运行测试或实机动效检查，未提交／发布。证据：.tmp/reply-attention-install/release-build.log、build-review.json、source-scope.json、install.json。

- 2026-10-17 17:56：v1.8.2 双架构包检查通过：1.8.2 Build 28／Codex Pulse，arm64 与 x86_64 架构准确、签名有效，DMG CRC 有效，镜像 App 与对应构建快照逐文件 SHA-256 相同，Applications 链接正确，SHA256SUMS.txt 已生成。本机完整备份与覆盖前目标一致，安装与 arm64 源包一致，进程确认。用户已实测确认“待回复”出现与回答后恢复；未运行自动化测试或额外 UI 验收，新增回归用例待执行。源码范围已核对，工作区另有界面改动未混入，README 图片与本地链接有效。证据：.tmp/release-v1.8.2/package-review.json、source-scope-review.json、install.json、arm64-build.log、x86_64-build.log。

- 2026-10-17 17:37：待回复识别修正 arm64 Release 最终构建退出 0；首轮后补齐“明确接受回答可解除对应等待”的边界并再次构建通过。源包、安装包和备份为 1.8.1 Build 27／arm64，签名有效；完整备份与覆盖前目标一致，安装全包哈希与修正源包一致，启动进程确认。本轮五份源码与独立构建快照逐字节相同，既有 AnalysisPresentation.swift 界面改动未混入。按持续要求未运行测试或 UI 验收；回归用例已补充但待执行，真实问题弹出／部分回答／全部回答／隐私／自动弹出开关由用户自行验证。证据：.tmp/island-user-input/release-build-final.log、release-build-first.log、source-scope.json、change.diff、install.json。

- 2026-10-17 12:33：v1.8.1 发布后复核：latest API 为新仓库正式版；main 与 tag 均指向源码提交 7bf4a6cce19c3aaa3b9990b4c0669595afe791e7，公开三份附件下载 SHA-256 及 GitHub digest 与本地产物一致，元数据地址满足源码的严格新仓库前缀。独立快照全部 Sources／Resources／Package 与打包脚本均与发行提交一致，未混入工作区 AnalysisPresentation.swift 改动。未运行应用测试或 UI 验收。证据：.tmp/repo-rename/public-release.json、public-download-review.json、source-scope-review.json。

- 2026-10-17 12:32：v1.8.1 改名修正版包检查通过：arm64／x86_64 为 1.8.1 Build 27，签名有效、DMG CRC 有效，镜像 App 与各自快照逐文件 SHA-256 相同，Applications 链接正确，SHA256SUMS.txt 已生成。发行快照的可执行源码相较 v1.8.0 仅更新仓库常量，另变更版本元数据；界面源码与已发布版本一致，工作区界面改动排除。本机完整备份及安装包比对一致，进程已确认；新仓库 Release 元数据 URL 与修正后的严格前缀一致。README 链接与 9 张图片引用有效；未运行测试或 UI 验收。证据：.tmp/repo-rename/package-review.json、source-scope-review.json、install.json、arm64-isolated-build.log、x86_64-isolated-build.log。

- 2026-10-17 12:20：v1.8.0 公开发布复核：GitHub latest API 确认为 v1.8.0 正式版，main 与远端 tag 均为源码提交 f7ec22a9dd047abe25705f906dc822709585fa09；arm64／x86_64 DMG 与 SHA256SUMS.txt 三份公开附件下载后 SHA-256 与本地产物逐一一致，GitHub 资产 digest 亦一致。未运行应用测试或 UI 验收。证据：.tmp/release-v1.8.0/public-release.json、public-download-review.json。

- 2026-10-17 12:18：v1.8.0 双架构发行包检查完成：arm64 与 x86_64 均为 1.8.0 Build 26／Codex Pulse，单架构准确、ad-hoc 签名有效，DMG CRC 有效；只读挂载后的 App 与对应构建快照逐文件 SHA-256 一致，Applications 链接正确。已生成 SHA256SUMS.txt。本机覆盖前 App 备份与目标一致，新安装与 arm64 源包一致，启动进程确认。README 各 9 张图片及本地链接核对通过，git diff --check 通过；未运行自动化测试或 UI 验收。证据：.tmp/release-v1.8.0/package-review.json、install.json、readme-review.json、arm64-build-final.log、x86_64-build.log；产物：build/releases/v1.8.0/。

- 2026-10-17 12:07：项目行会话摘要 arm64 Release App 构建退出 0；源包、覆盖前 App、完整备份和安装包均为 Codex Pulse／1.7.0 Build 25／arm64，签名有效；备份全包哈希与覆盖前目标一致、安装全包哈希与源包一致，启动进程已确认。现有源码差异限于会话列表表头、项目／会话行及列宽，新增只读展示模型；归属／连续性服务、Store、数据路径与打包配置源码哈希未变，项目操作函数未改。按用户要求未运行测试或截图／交互验收；单／多账号、部分／全部未知、混合异常、搜索与筛选、长名称及键盘由用户自行验收。证据：.tmp/session-project-summary/release-build.log、install.json、scope-review.json、change.diff。

- 2026-10-17 12:00：概览卡精简 arm64 Release App 构建退出 0；源包、覆盖前 App、完整备份与安装包均为 Codex Pulse／1.7.0 Build 25／arm64，签名有效；备份全包哈希与覆盖前目标一致，安装全包哈希与源包一致，启动进程已确认。本轮源码差异仅限 costOverviewCard、usageOverviewCard 与 UsageCountMetric，图表和服务实现不变；受保护源码哈希一致。按用户要求未运行测试、截图或交互验收。证据：.tmp/overview-card-simplify/release-build.log、install.json、scope-review.json、change.diff。

- 2026-10-17 11:55：Codex Pulse 命名迭代 arm64 Release App 构建退出 0；源包／安装包 CFBundleDisplayName 与 CFBundleName 均为 Codex Pulse，Bundle ID／可执行文件与覆盖前一致。源包、旧包与完整备份均为 1.7.0 Build 25／arm64，签名有效；备份全包文件哈希与覆盖前目标一致，安装全包文件哈希与源包一致，启动进程已确认。数据路径／偏好／Store／打包脚本等受保护源码哈希不变。未运行测试或 UI 验收，配置沿用与界面显示由用户自行确认；构建保留既有 Swift 并发警告。证据：.tmp/pulse-name/release-build.log、install.json、change.diff、protected-sha256.json。

- 2026-10-17 11:52：品牌 Logo 替换 arm64 Release App 构建退出 0；已核对构建包中的 SVG、ICNS 与 Resources 正式素材逐字节一致、CFBundleIconFile 指向正确且显示名称仍为 Codex Monitor。源 App、安装 App 与备份均为 1.7.0 Build 25／arm64，签名有效，备份全包文件哈希与覆盖前目标一致、安装全包文件哈希与源包一致，启动进程已确认。未运行应用测试或界面验收；各尺寸显示及系统图标缓存呈现由用户自行查看。证据：.tmp/pulse-logo-replace/release-build.log、install.json。

- 2026-10-17 11:48：品牌静态素材导出检查：6 份 SVG 经 XML 解析；使用 macOS sips 导出 5 份 1024×1024 图形与 1600×1080 方案板，已目视检查最终方案板和主标预览。修正 Quick Look 方形缩略图裁切后改用按原画幅导出，并使用明确中性色描边避免 SVG 透明描边渲染差异。未构建应用、运行应用测试或覆盖安装。证据：docs/brand/codex-pulse-concept/、.tmp/pulse-brand/render-report.json。

- 2026-10-17 11:42：本轮面板版本回滚完成：恢复来源、安装 App 与 build App 全包文件哈希一致，arm64／1.7.0 Build 25 签名有效，恢复后二进制 SHA-256 为 808e5cb6eaac040e81410101905c80b21796f79b8f007c1c9d94805d2aa09c17；撤回前 App 完整备份校验一致，三份源码与上轮改动前快照一致，启动进程已确认。未重新构建、运行测试或界面验收。证据：.tmp/rollback-glance-chrome/install.json。

- 2026-10-17 11:40：面板页头／周期／底栏改造 arm64 Release App 最终构建退出 0；首轮构建通过后补充原生菜单跟踪保护，再次构建通过。源 App、安装 App 与备份均为 1.7.0 Build 25／arm64，签名有效，备份全包文件哈希与覆盖前目标一致，安装全包文件哈希与源包一致，启动进程已确认。按用户要求未运行测试、截图或界面交互检查；账号长文案、更多菜单／退出、独立周期菜单与键盘、菜单防误收起、底栏跳转／刷新及高度由用户自行验收。证据：.tmp/glance-chrome-controls-cds/release-build.log、release-build-attempt1.log、change.diff、install.json。

- 2026-10-17 11:32：Glance 阅读层／成本状态／Token／高度改造 arm64 Release App 构建退出 0；源 App、安装 App 与备份均为 1.7.0 Build 25／arm64，签名有效，备份全包文件哈希与覆盖前目标一致，安装全包文件哈希与源包一致，启动进程已确认。按用户要求未运行测试、截图或界面交互检查；玻璃可读性／透明度、加载／缺失／零值／未计价、周期与开关组合、测量高度／小屏滚动及真实设置预览由用户自行验收。证据：.tmp/glance-reading-cost-cds/release-build.log、change.diff、install.json。

- 2026-10-17 11:25：灵动岛可见性／语义色／文案改造 arm64 Release App 构建退出 0；源 App、安装 App 与备份均为 1.7.0 Build 25／arm64，签名有效，备份全包文件哈希与覆盖前目标一致，安装全包文件哈希与源包一致，启动进程已确认。按用户要求未运行测试、截图或界面交互检查；不可见时完成后恢复可见、已开始回执不重启、语义色／宽度降级、长标题／隐私与横幅操作由用户自行验收。证据：.tmp/island-visibility-copy-cds/release-build.log、change.diff、install.json。

- 2026-10-17 11:19：紧凑完成回执 arm64 Release App 构建退出 0；首次安装后补充到期回调可见性保护，再次构建与覆盖通过。源 App、安装 App、两次备份均为 1.7.0 Build 25／arm64，签名有效，每次备份全包文件哈希与对应覆盖前目标一致，最终安装全包文件哈希与源包一致，启动进程已确认。按用户要求未运行测试、截图或界面交互检查；自动弹出开／关、最终与混合完成、待批准／新轮次抢占、遮挡／展开／重复刷新由用户自行验收。证据：.tmp/final-compact-receipt-cds/release-build.log、release-build-attempt1.log、change.diff、install.json、install-attempt1.json。

- 2026-10-17 11:13：灵动岛选中／摘要／隐私／入口精简 arm64 Release App 构建退出 0；源 App、安装 App 与备份均为 1.7.0 Build 25／arm64，签名有效，备份全包文件哈希与覆盖前目标一致、安装全包文件哈希与源包一致，启动进程已确认。按用户要求未运行测试、截图或界面交互检查；结果卡片选中、混合状态计数／窄宽度摘要、隐私与辅助功能、额度入口及原功能由用户自行验收。证据：.tmp/island-summary-selection-cds/release-build.log、change.diff、install.json。

## 验证与产物入口

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
