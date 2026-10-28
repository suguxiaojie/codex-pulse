# 灵动岛角色「Clawd 岛内版」

Clawd 位于紧凑灵动岛左翼，硬件刘海左侧，后接额度；右翼显示任务状态，多个活动任务时显示 ×N。关闭角色后恢复原紧凑内容布局。焦点沿用 `ActivitySessionSnapshot.compactFocus`，额度页为空闲状态。视线固定为 0，不启用鼠标跟随。

## 实现与边界

- `IslandClawdBadge.swift`：缓存预渲染帧、Core Animation 离散播放、隐藏／遮挡暂停和 Reduce Motion 回退；八种片段为 idle、start、think、tool、approve、reply、done、fail。
- `IslandClawd.swift`：保留共享的 `IslandClawdPose` 与 `IslandClawdSprite`；挂岛舞台、运动模型、同伴、粒子和定时器已移除。
- `ActivityIslandMascot.swift`：紧凑额度角色与原生描边接线；卡片角色包装仅呈现 `IslandClawdStill`，没有逐帧时钟或视线订阅。
- `ActivityIslandView.swift`：任务态接线；角色尺寸为 `min(clawdSize.pixel, (compactHeight - 4) / 12)`，完整图格上下各留至少 2 pt。32 pt 岛高时三档为 1.6／2.2／2.3333 pt；40 pt 岛高时为 1.6／2.2／2.8 pt。
- 紧凑态只保留 `IslandClawdGlow` 描边，等待时呼吸、终态闪一次后透明；Reduce Motion 按 `restingOpacity` 静态显示。展开态原有边缘光、任务卡 Metal、材质与布局保持。
- 不再安装挂岛绘制层或岛边凹陷遮罩。用量胶囊紧凑偏移固定 24 pt；固定画布和原有硬件阴影边距保持，不为 Clawd 增加区域。

## 设置

| 设置 | 偏好键 | 行为 |
|---|---|---|
| 显示桌宠 | `activityIsland.clawdEnabled` | 控制紧凑角色，卡片保留静态头像 |
| 桌宠大小 | `activityIsland.clawdSize` | 原始三档 1.6／2.2／2.8 pt，按岛高限制 |
| 旧岛边互动 | `activityIsland.clawdEdgeReaction` | 保留键与存储兼容，隐藏控件，不再驱动变形 |

验证入口为 `scripts/test.sh`；本轮状态与证据见项目 `ROADMAP.md`。
