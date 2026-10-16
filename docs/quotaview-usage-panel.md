# 灵动岛用量页适配

上游：Duoasa/QuotaView，固定提交 f7795311bf06c2a54c9b9756da375c50d0f4930e（MIT）。

- UI：Sources/QuotaView/IslandConceptBoard.swift 中 IslandUsageBento（2604 行起），玻璃卡片、左右账户布局、额度条、Token 三卡、成本柱图与活动热图。
- 触发：IslandBoardState.openUsage / closeUsage、header 中额度按钮。手动进入页面，返回任务；固定／收起继续由同一窗口状态机管理。
- 动效：同文件固定画布与展示层几何续接，usageFlow 淡入淡出；沿用本项目已移植的 ActivityIslandSurfaceMotion 与玻璃几何，增加页内过渡，不创建第二个浮窗。
- 数据：上游 CurrentCodexPresentation／IslandUsagePresentation，CodexAppServerClient.fetchPayload 读取 account/rateLimits/read 与可选 account/usage/read；CurrentCodexPresentationProjector 投影 lifetimeTokens、dailyUsageBuckets 和最新日数据；Codex 汇总成本按每百万 Token 0.50 美元统一折算（Claude 可用模型细分）；Claude 单独依赖已接入的 ClaudeUsage，原项目商品图为示例数据。重置页为演示，不应据此模拟真实余额和次数。
- 本项目适配：额度继续 QuotaService；Token 优先沿用 account/usage/read 的 summary／dailyUsageBuckets，忽略 threadUsage 原文；每次额度刷新独立异步请求，失败退本地汇总，账号变更立即清空并以 request ID 拒绝旧响应。用量页成本使用 IslandDashboardCost 对齐官方 Token 统一折算，只有回退及独立 Cost 页继续使用 CostService；累计回退补齐完整本地历史扫描，保留账号归属边界；不迁移上游凭据或连接配置。仅显示已实现的 Codex 数据源。重置详情在灵动岛内打开，复用上游票卡锚点与可逆 3D 转场；真实操作使用既有接口和独立二次确认。
- 验收：页面打开／返回／收起／固定；屏幕高度约束及滚动；加载／缺失／隐私状态；日／周／累计热图，成本选择；数据回归与完整测试、arm64 Release、本机安装验收。Hook 数据接入保持暂停。

本机只读探测确认 account/usage/read 可用，仅记录响应字段名，未存储线程内容。用量页帮助文本注明统一折算口径及本地回退范围。

## 实机截图对齐与成本差异（2026-10-16）

- 上游 `QuotaViewFigmaMenu.swift` 的 `EstimatedCostChartMetrics.cachedInputUSDPerMillionTokens = 0.50`；`EstimatedCostChartModel` 对无模型细分的官方每日 Token 使用该统一折算，按 UTC 最近 30 个自然日汇总，最近一天取最后一个有数据的日期。不是模型真实计费，也不是账单。
- 本机只读官方响应计算 30 天为 2187.921964 美元，最近已知日为 72.97905 美元；四舍五入与用户实机截图完全一致。旧面板采用本机全部账号日志及模型输入／输出／缓存费率，既不同账号范围，也不同算法／日期边界。
- 本次灵动岛用量页使用上游同口径模型；官方接口不可用时明确通过帮助与辅助功能说明回退本地模型计价。原 Cost 页不改变算法。
- 复用 macOS 27 深色底色分离（用量卡按参考图将底色调为 white=0.025／alpha=0.90，并保留细描边）、内容高度测量、常驻横向滚动条与最近数据定位、悬停锚点提示、重置卡 SVG／倾斜／扫光；Asta Sans、账户栏尺寸、标题和重置倒计时按上游恢复。没有 Claude 数据时不显示数据源切换行。
- 新页面按内容测量外壳高度，固定画布不随页面改变；内容视图裁切避免旧用量内容淡出时溢出缩小后的外壳。Hook 接入保持暂停。重置卡现打开灵动岛内详情；进入页面不消费次数，只有二次确认触发既有真实接口。

## 缩略态宽度只读对比

本机 Built-in Retina Display：1728×1117 pt，safe top 32 pt；左辅助区 maxX=771.5，右辅助区 minX=956.5，刘海宽度 185 pt。两边运行态均使用 cameraWidth + 280 = 465 pt。

同屏 WindowServer 原始 PNG（2×）测量 alpha > 0.5：第 0／20／40／55 行两边分别为 932／898／896／882 像素，完全一致。第 40 行可见屏幕横向边界均约 640～1088 pt。不同的是透明画布：本项目 580 pt、QuotaView 740 pt，不能当成可见横幅宽度。未修改 compactWidth；该结果仅证明本轮同屏运行态，不能据此排除用户在其他状态／显示器观察到差异。

成本柱宽遵循上游独立的 max(8, viewport-derived cell size)，不使用热图的最小 10 pt 方块宽度；两者共享 3 pt 间距，但滚动内容宽度分别计算。

重置页确认捕获账号指纹和次数快照，提交前重新检查；账号正在切换／盘点、次数变化或请求中时拒绝提交。确认框与请求期间暂停自动收起；本机验收仅进入、返回及取消确认，不消耗重置次数。

重置详情采用紧凑横向票卡（112×67 pt）＋次数／有效期摘要、额度条、短说明与右下操作。正文与重置页外壳均为完全不透明纯黑，不使用玻璃渐变；返回用量页恢复原材质，不改全局玻璃程度偏好。二次确认在可见详情内容内居中，替代会按透明宿主画布居中的系统 alert；不绑定危险操作的回车默认提交。

二次确认采用 320 pt 黑色卡片：标题／短说明、次数前后对照、右对齐的弱取消与紧凑红色确认按钮，不使用大警告图标或两块等宽按钮。

重置交互控件复用 IslandApprovalActionStyle 的原生玻璃、语义红色、悬停亮度和按压反馈；确认层保留纯黑背景，使用小票卡标识和 Asta Sans 信息层级，使用 0.26 秒统一缓动及轻微背景失焦。非原项目已有真实确认操作的完整移植，提交行为仍由本项目确认和校验负责。
