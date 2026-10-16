# Codex Notch Monitor Roadmap

## 项目目标

原生 macOS 应用，集中展示 Codex 官方额度、本地 Token／成本、任务状态、社区信号与会话管理；保持不同数据来源和账号归属的证据边界。

## 当前阶段

已发布基线为 v1.6.10（Build 24），当前正在构建正式 v1.7.0（Build 25），本地 HEAD 为 95b3d5b04615c953829303aa16d8d94643da9d84。工作区已完成 A、B、B2、C 悬浮用量胶囊及其旧配置逻辑清理和 QuotaView 差异修复，存在未提交改动；同版本号的 arm64 本机开发构建已备份覆盖安装，未提交、推送或发布。总设置保留原监控中心结构，灵动岛是其中一个子页面；菜单栏设置独立归属面板设置。

本地开发交接笔记不随公开发行包上传；历史版本变化以 Git 历史为准。

## 进行中与待办

- 2026-10-16 20:39：v1.7.0（Build 25）源码与双架构 DMG 发布准备：中英文 README、Hook 暂停／图像导出／计价说明已同步；等待最终附件内容核验、提交、推送和 GitHub Release。

- 2026-10-16 20:17：轻量刷新按钮已安装，默认外观和真实点击已实机检查；服务在 AX 采样前返回，加载文案／禁用状态／旋转未捕获，悬停／按压中间帧未录制，不宣称动态验收通过。证据：build/quiet-refresh-verified/。


- 2026-10-16 20:00：四处设置改造已安装并完成静态／滑杆实机检查；会话筛选菜单能展开，但选“已归档”时工具报告用户切换界面，已停止输入，筛选结果与逐帧动效未宣称通过。原透明度 50% 已恢复，会话仍为全部／139 条。证据：build/settings-controls-verified/。


- 2026-10-16 18:51：曲线／7 日柱形及周期边缘改造已实现并安装：单调三次曲线保留真实数据点和范围、共享面积路径；7 日 24 pt 细竖柱＋140 pt 高度＋逐日日期，月／小时更密；专用周期按钮去掉行样式额外内边距。完整测试与 arm64 Release／签名通过；已观察真实成本月视图平滑曲线。截图期间用户切页，停止自动操作，7 日柱形及按钮悬停边缘尚待实机补验，旧逐帧动画仍按此前选择延后。证据：build/chart-refinement-verified/。

- 2026-10-16 18:36：用量／成本分析页视觉与动效改造已实现并安装：紧凑范围工具栏、滑移周期底板、白色主指标、主次卡片边框、真实折线／面积插值、柱高／热图数据过渡与项目行反馈。完整测试及最终 arm64 Release／签名通过。实机确认用量周／月／三月和范围说明；用户明确选择“先看新版，动画稍后验收”，已停止界面操作。逐帧动效、成本页及项目展开／详情交互仍待验收，不移入最近完成。证据：build/analysis-polish-verified/。



- 当前无 Hook 试用：MonitorStore.hookDataEnabled=false，收件箱轮询与消费入口均关闭；保留 IPC＋本地日志，非纯 IPC。Hook 配置与事件文件未改动；长期运行／完成／等待／断线表现由实际试用继续验证。恢复接入前检查积压事件时效，避免回放旧状态。



- 复现菜单栏窄候选丢百分比、多项目 Token 页缺数量、纯图标后容量无法恢复三个边界，详见 Handoff。
- 已实机确认单会话的当前工具摘要、工作／思考状态切换、整卡效果、隐私遮挡及设置导航；真实等待批准、完成／取消的全过程仍待验收，自动回归不能替代该部分。
- 无 Hook 只读任务监控已接入并完成本机连接、工具／思考及已有完成状态验收；真实待批准／取消、睡眠重连和当前真实任务从活动到结束的完整过程仍待验收。桌面 IPC 为版本相关协议，不提供批准／回答；现有 Hook 保留，断线回退本地日志。证据：build/native-activity-20261016-031116/。
- 多屏切换、ControlCenter 系统拦截和真实多项目悬停验收未闭环；历史 design-qa.md 混有已撤回 Prompt 导航实验记录，不把旧 blocked 当作当前全部界面的状态。
- 设置页整理已实现并安装，完整测试与 arm64 Release／签名通过；实机确认阅读区遮蔽、中文导航、周月联动与默认菜单设置。独立活动范围与成本单日已在后续柱状图验收完成；项目详情跳转与 Hook 折叠交互仍待验收。旧 detailed 偏好仅映射为自动显示，原始值未改写。证据：build/settings-review-verified/。

## 最近完成

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

- 2026-10-16 15:02：可读导出展示进一步按用户提供的 ChatGPT 共享页对齐：实测正文 16/26 px、阅读栏 736 px，统一深色中性阅读样式；用户问题靠右、精简重复摘要与角色标题，过程入口改为细线／箭头，收起说明与会话元数据。HTML 目录、代码栏、表格进一步精简，保留嵌套列表与 Markdown 软换行；Markdown 目录默认折叠、过程引用及简洁角色分隔，重新生成独立渲染预览。未改脱敏、读取及备份链，Hook 仍屏蔽；已备份覆盖 arm64 安装版。

- 2026-10-16 14:37：可读 Markdown／HTML 导出参考 Codex 调整为问题与回复分层；Markdown 使用用户引用块、过程 details 折叠和次要会话信息。共享按 commentary／final_answer 分组，旧日志保留末条回复兼容，明确进度不再误标最终回复。HTML 使用克制深色阅读版式，补上表格、长代码围栏、转义字符／粗体内代码、上一问／下一问、顶部与代码复制（本地文件回退），保留原搜索／目录。原脱敏与备份链未改，Hook 仍暂停。实机验收修复窄屏目录自动滚动将正文拉回上方的问题，目录高亮只滚动自身容器；完整测试、构建与真实导出交互通过，已备份覆盖 arm64 安装版。

- 2026-10-16 14:09：修复会话管理／恢复核验的 App Server 列表漏分页：服务端将 limit=1000 截为每页 100 条，19 条较早会话均在第二页，之前误标“待恢复”且恢复核验为 0/19。活动与归档列表统一追踪 nextCursor、合并去重；分页失败或重复游标返回错误而非不完整成功。无需修复会话数据；Hook 仍屏蔽。已备份安装 arm64 开发包。

- 2026-10-16 13:58：支持 .jsonl.zst 压缩会话，内置官方 Zstandard decoder-only 1.5.7，统一只读流式读取、有界头尾预览、会话／事件去重与缓存；本地详细成本合并压缩历史及普通续写。可读导出支持压缩来源，完整备份仅在导出暂存目录生成兼容 JSONL，导入冲突检查同步识别压缩会话。新发现压缩历史不作为当前账号新建证据，已有归属保留；Hook 仍屏蔽。已备份覆盖安装 arm64 开发包。说明：docs/compressed-rollouts.md。
- 2026-10-16 13:26：灵动岛重置入口改为面板内详情，不再打开动态中心；复用 QuotaView 票卡锚点、完整可逆 3D flight、扫光与 IslandApprovalActionStyle 原生按钮。按用户反馈改为纯黑不透明外壳、紧凑横向次数／有效期摘要、可见内容内居中的二次确认，统一字体、按钮与缓动／轻微背景失焦。接入既有真实接口，确认捕获账号与次数快照；账号变化、过期／未知额度、隐私、重复提交受阻。Hook 保持屏蔽。
- 2026-10-16 12:46：按 QuotaView 实机截图进一步对齐用量页：复用 macOS 27 深色玻璃分层、动态内容测量、常驻图表滚动条／最近定位／锚点提示、重置卡 SVG／倾斜／扫光；恢复 Asta Sans 数字、Pro 20x、小时倒计时与顶部“用量统计”。用量页成本改为上游官方 UTC 日 Token × $0.50／百万，真实计算得到 $2,187.92／$72.98，与参考截图一致；独立 Cost 页保留模型计价。修复缩页残影裁切与成本／热图单元宽度混用。Hook 继续屏蔽，已备份安装。
- 2026-10-16 12:24：适配 QuotaView f779531 用量页：灵动岛顶部额度按钮／悬浮胶囊进入，返回任务／固定／收起，原生玻璃额度与账户卡、Token 三卡、成本柱图、日／周／累计热图及同画布外壳／内容过渡。复用上游热图和展示结构；接入 account/usage/read 当前账号官方汇总，独立标注本机全部账号成本，官方不可用时退本地统计；后台全历史扫描补齐本地累计。修复余额小数换行、首次 baseline 覆盖手动展开。保留 Hook 暂停，重置入口跳转现有动态中心，无批准／重置写操作。实现说明：docs/quotaview-usage-panel.md。
- 2026-10-16 12:04：按用户要求暂时屏蔽 Hook 数据，停止 0.6 秒轮询并在 consumeHookEvents 读取前拦截，启动和手动刷新均不能接入 Hook；保留原安装配置及收件箱。安装与权限页标明暂停，IPC／本地日志保留。已备份覆盖安装 arm64 开发包。
- 2026-10-16 11:54：修复灵动岛滑杆拖动中间态：显示位置从取整后的 AppStorage 分离为本地连续进度，偏好／预览更新上限 20 Hz，重复值不写入，松手或离开时立即提交精确值；阻尼响应改为 0.24 秒。已备份安装并完成真实拖动、边界、回稳、配色切换验证，恢复原设置。证据：build/continuous-slider-verified/。
- 2026-10-16 11:32：灵动岛设置按现有面板设置统一卡片、字体、间距、分隔线与原生控件，分为外观预览、材质与尺寸、显示与隐私、任务特效、自动展开；保留全部偏好及 QuotaView 实时预览，移除本次替换产生的无引用旧设置组件。材质按钮补齐辅助功能角色；其他页面及任务状态逻辑未改。已备份安装 arm64 开发包，未提交或发布。

## 最近验证

- 2026-10-16 20:39：正式 v1.7.0（Build 25）完整测试通过；arm64 与 x86_64 Release／DMG 构建退出码均为 0，镜像校验通过；arm64 正式包已备份覆盖本机并确认启动。Intel 无真机测试，既有部分动态验收边界保留。

- 2026-10-16 20:17：完整测试与 arm64 Release 退出码 0，签名／安装哈希通过；安装版确认重新检查默认无底色，实际点击检查并触发用量刷新，真实项目 Token 更新且活动整理启动。两次返回快于 AX 采样，加载／旋转与按压中间帧未捕获。返回会话页全部 139 条，未改账号／会话／Hook 数据。证据：build/quiet-refresh-verified/。

- 2026-10-16 20:00：完整测试与 arm64 Release 退出码 0（偏好测试 29、Continuity 37/37），安装前后签名与哈希通过。实机确认内容页已无菜单栏旧功能，内容／外观切换、新滑杆真实拖动 50%→69%→50% 与松手位置、会话工具栏和筛选菜单；用户切换中断筛选项选择，未进行导入／导出／恢复写操作。未记录动画中间帧。证据：build/settings-controls-verified/。

- 2026-10-16 19:03：日志卡／动态导航安装版实机通过：日／月数字与来源对齐、说明展开显示实际模型映射；实时筛选重置信号、切时间轴自动复位、切本机恢复均有效，未操作分类。恢复成本月／全部账号／说明折叠。完整测试与 Release 退出码 0，签名和安装哈希一致；逐帧动效依用户此前选择延后。证据：build/source-toolbar-verified/。

- 2026-10-16 18:51：完整 scripts/test.sh 退出 0，新展示回归覆盖插值中间坐标、Bezier 路径、真实锚点、逐段 101 点无过冲、峰顶／平段、重复 x／非数值和细柱宽度；既有 Quota reset 18、Continuity 37、Hooks 9 等通过。arm64 Release／严格签名／安装哈希一致。Cua 初始读取用量周数据；截图时用户切换成本月，实际图显示平滑曲线与密集竖柱，未将该图记为用量周验收。停止后续界面点击，7 日和周期悬停仍待验证。备份：build/backups/CodexNotchMonitor-before-chart-refinement-20261016-184802.app；证据：build/chart-refinement-verified/。

- 2026-10-16 18:36：完整 scripts/test.sh 退出 0，新增 9 项插值检查覆盖真实中间路径、线／面积同步、零／空序列及精确终点；既有 Quota reset 18、Continuity 37、Hooks 9 等通过。最终 arm64 Release／严格签名／安装哈希一致。CUA 检查用量页排版、7→30→90 日切换与范围弹出说明；两段录制分别因窗口选择错误和主窗口仅有静帧而排除，没有宣称动画通过。随后用户明确延后动画验收，成本和项目交互亦未继续操作。备份：build/backups/CodexNotchMonitor-before-analysis-polish-20261016-182958.app；证据：build/analysis-polish-verified/。

- 2026-10-16 18:04：完整 scripts/test.sh 退出 0（Quota reset 18/18、Continuity 37/37、Hooks 9/9），arm64 Release／严格签名／安装哈希一致。真实副本回放验证 5 条自动标记、2 条未明、持久化重载、幂等备份和零历史通知；原始字段及人工覆盖不变。安装版状态文件已保存 5 条关联，CUA 显示自动关联行及展开依据，不再要求确认；最后 Tibo 筛选点击遇用户操作信号，未记作实机通过，分类结果由回放覆盖。证据：build/reset-auto-tag-verified/；回滚 App：build/backups/CodexNotchMonitor-before-reset-auto-tag-20261016-180135.app；标记前数据：build/reset-auto-tag-verified/quota-reset-state-before.json。

- 2026-10-16 17:46：完整 scripts/test.sh 退出 0（Quota reset 18/18、Continuity 37/37、Hooks 9/9 等），最终 arm64 Release／严格签名／安装哈希一致。18 条真实记录副本回放：7 条未确认中 5 条有社区线索、2 条仍未明，回放通知事件 0。安装版 CUA 核对日期、展开时间差异、左对齐／范围文案、来源链接目标、上下历史及分类菜单，取消而未提交分类；原始 18 条历史字段前后相同。真实账号切换未操作，仅有回归覆盖。证据：build/reset-association-verified/；回滚 App：build/backups/CodexNotchMonitor-before-reset-association-20261016-173402.app；数据原件备份：build/reset-association-verified/quota-reset-state-before.json。

- 2026-10-16 17:13：最终完整 scripts/test.sh 退出 0（含官方价格 Standard／Batch 隔离、字段／数值／长上下文边界、优先级、动态倍率、ETag／304／失败保留等），arm64 Release／严格签名／安装哈希通过。生产解析器真实官方 HTTPS 请求成功；独立断网注入确认有效价格、缓存与成功时间不变。安装版 CUA 观察从内置等待态变成官方同步 2026-10-16 05:12（纽约），补充目录保留 10-15 的实际同步时间，截图已存。证据：build/pricing-auto-verified/；回滚备份：build/backups/CodexNotchMonitor-before-pricing-auto-20261016-171121.app。

- 2026-10-16 17:00：完整 scripts/test.sh 退出 0（Continuity 37、Hooks 9 等），arm64 Release／严格签名／安装哈希一致。安装版真实数据验证 Token 柱／热力格和成本小时柱／热力格四种悬停、精确明细、细描边及移出峰值复位；完成 Token 周↔三月、成本跟随↔独立 90 日切换，恢复全部账号／Token 周／成本日。原生截图采样确认柱填充与最高档热格颜色相同；未做动画逐帧计时或系统减少动态开关实机切换。证据：build/chart-visuals-verified/；回滚备份：build/backups/CodexNotchMonitor-before-chart-visuals-20261016-165124.app。

- 2026-10-16 16:44：完整 scripts/test.sh 退出 0、arm64 Release／严格签名／安装哈希一致。CUA 使用真实安装版验证成本日小时柱、周／月日柱、独立 90 日热图及返回跟随；Token 周／月柱、三月／半年热图与独立 30 日柱。前台鼠标验证 Token 精确 287,436,632 和成本 $53.08／62,217,879 Token 明细，保存实际截图。成本半年最后菜单选择遇用户操作中断，未记通过；不包含逐帧动画验收。证据：build/activity-charts-verified/；回滚备份：build/backups/CodexNotchMonitor-before-activity-charts-20261016-163329.app。

- 2026-10-16 16:23：设置页整理完整 scripts/test.sh 退出 0（偏好 29、Continuity 37、Hooks 9 等），最终 arm64 Release 与严格签名通过，安装哈希一致。CUA 实机确认不透明主阅读区、七页导航、周 7 日→月 30 日的指标／热图联动和默认关闭任务时的菜单选项；独立范围选择连续提示用户操作，停止进一步点击，未将项目详情／成本单日／Hook 折叠记作通过。原 detailed 保存值保留，Hook 接入仍关闭。备份：build/backups/CodexNotchMonitor-before-settings-review-20261016-162007.app。

- 2026-10-16 15:55：完整 scripts/test.sh 与 arm64 Release、严格签名／安装哈希通过。安装版真实菜单栏日志 visible=true／occluded=false，按钮 66→50 pt、系统窗口 82→66 pt，实机截图核对仅圆环＋36%，未修改偏好或额度数据。已有状态布局／轮播／容量回归通过；其他极窄候选与多屏问题仍按原待办保留。证据：build/menu-bar-tight-verified/。

- 2026-10-16 15:45：最终完整 scripts/test.sh、arm64 Release／严格签名／安装哈希通过。13 张真实内嵌图片逐张用浏览器原生滚轮、鼠标拖动与双击验收，全部通过；12 次从放大态切图均还原。首图鼠标锚点误差约 1.7e-8，缩放上限 8 倍，原生连续拖动到水平／垂直边缘，边界误差小于 0.1 px；390 px 重设窗口与双击还原、键盘 0、最小缩放通过。包含 108×66 小图回归；源日志校验不变。首次系统启动返回 -600，核对安装包一致与无运行进程后，以新实例正常启动并核对进程。浏览器任务已结束，保留可交互大图。证据：build/image-viewer-zoom-verified/。

- 2026-10-16 15:22：最新完整 scripts/test.sh 与 arm64 Release／签名／安装哈希通过。新增内嵌优先、纯图片提问、跨轮重复、缺 URL、缺失／损坏／远程源、正文脱敏、带空格素材路径、素材复用／冲突拒绝和原日志不变回归。真实压缩会话 13 张图片全部恢复，HTML 13 缩略图／0 缺失；Markdown 13 引用／13 素材，源 SHA-256 不变。浏览器实点大图、切换、键盘、Esc、焦点返回、390 px 无溢出；单独复制 HTML 到无素材目录仍 13/13 解码、远程请求 0；Markdown 13/13 相对素材加载。原 41 问恢复为 47 问，原因是保留不同轮的重复提问。证据：build/export-images-verified/。

- 2026-10-16 15:02：完整 scripts/test.sh、arm64 Release、签名／安装哈希通过。浏览器打开用户共享页并实测 16/26 px 与 736 px，真实普通／压缩会话重新导出 4 文件，源 SHA-256 不变；HTML 实点多行代码复制后 textarea 粘贴完全一致（5 行），搜索 36 问／182 高亮，过程展开、320 px 目录正文定位通过。Markdown 实点过程展开与第 41 问锚点通过；两种页面在 320/375/414/768 px 无整页横向溢出。设计扫描 P0=0，其余命中为标准引用及原会话正文，人工复核保留。原生 Codex 窗口被工具禁止访问，未绕过；本轮按共享网页实际展示验收。证据：build/export-polish-verified/。

- 2026-10-16 14:37：完整 scripts/test.sh／arm64 Release／严格签名／安装哈希通过。真实普通 10 轮与压缩历史 41 轮分别导出 MD／HTML，源文件 SHA-256 不变；Markdown marked 解析通过。浏览器实点代码复制并粘贴比对一致；搜索 8 问题／21 高亮、结果前后切换、无结果与清除恢复通过。首末问边界、41 轮跨组定位与过程展开、390 px 窄屏正文定位、1440 px 桌面无横向溢出及减少动态通过；非实体手机测试。窄屏目录拉回已复现修复并补回归。证据：build/export-reader-verified/。

- 2026-10-16 14:09：完整 scripts/test.sh（含新增分页、归档、失败与游标循环回归）及 arm64 Release 构建通过；严格签名、安装哈希一致。真实数据库只读备份至隔离目录后由本机官方 App Server 查询：活动 100+28、归档 28，第一页目标 0/19，完整分页目标 19/19。未重跑真实恢复，未改写原始会话数据。安装版界面导航被用户切换中断，最终 UI 数量尚未验收，不计通过。证据：build/thread-pagination-verified/。

- 2026-10-16 13:58：完整测试通过（流式读取 13、Continuity 37/37、会话／原生／面板／Hooks 等其余套件）；arm64 Release／严格签名／安装哈希通过，otool 确认无 Homebrew／外置 zstd 动态依赖。真实 234 个日志全部解析，去重 233 线程＝139 用户＋69 子代理＋25 系统，解析失败 0；安装版会话管理显示 27 项目／139 会话／28 归档，展开当前项目为 8 条。归属记录前后均 139、已知 ID 均 188，无新增／移除归属。19 条待恢复仅展示，未执行恢复。压缩损坏／截断／未知大小／多 frame／输出上限／长行及只读导出有回归。证据：build/compressed-rollouts-verified/。
- 2026-10-16 13:26：最终完整测试（原生面板 97、生命周期 35、Continuity 36、Hooks 9 等）和 arm64 Release／严格签名／安装哈希通过。实机验证票卡进入面板内详情、真实 2 次余额与有效期、返回用量、居中确认与取消，余额仍为 2 次；未执行真实消费。纯黑页及新版确认已展示，确认现已关闭。部分窗口录像未覆盖目标过渡，不将这些录像记作逐帧验收通过；动画采样端点有回归测试。证据：build/island-reset-verified/。

## 验证与产物入口

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
