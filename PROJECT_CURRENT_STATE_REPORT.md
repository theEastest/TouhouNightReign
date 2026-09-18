# TouHouNightReign 当前开发现状报告

日期：2026-08-30  
审计范围：`E:\gemesmods\stg\TouHouNightReign` 当前工作区、LuaSTG Sub 原生桥接、纯 Lua 测试、运行日志与 Git 状态。  
审计原则：以当前代码的入口、调用链和实际测试输出为准；任务书或旧报告中“计划实现”的内容不计为已完成。

## 1. 结论摘要

当前项目是一个已经能够启动并进入菜单、地图和部分原生战斗房间的架构原型。稳定完成的部分集中在：

- LuaSTG Sub 入口与 TNR Bootstrap 状态机。
- 基于种子的左到右地图图生成、相邻节点选择和节点访问记录。
- `GameSession`、`PlayerState`、`PartyState`、`BattleResult`、奖励和基础金钱/分数数据。
- Reimu 的原生 THlib 单人玩家、原始敌人/符卡对象池和导入资源的加载路径。
- Phase 1/2 的角色、装备、背包、配装、容量和 Ready 纯数据流程。
- LAN TCP 传输、输入包、命令/事件、快照和原生联机房间的桥接代码。

但下列边界必须明确标记为“部分完成”或“高风险”：

- 原生战斗由两台机器分别运行，完整弹幕/粒子池没有被网络同步；快照只在有限周期用于纠偏。
- 远端自机、远端射击/追踪弹、Bomb、敌人状态、死亡/复活和房间切换都依赖 `legacy_native_main.lua` 的适配分支，过去运行中出现过显示、输入、Bomb、敌怪状态和房间启动不同步问题。
- `Shop`、`Event`、追击/腐化、完整奖励界面、通用装备战斗运行时和原生 `lstg.var`/TNR 状态统一尚未完成。
- `engine.log` 中仍有历史运行错误，包括缺少资源、Shader 编译失败和从错误工作目录启动导致的 `main script not found`。纯 Lua 测试通过不等于原生引擎联机稳定。

因此当前实际阶段为：**Phase 2（地图整备/背包/配装/Ready）已实现；Phase 3 及更后的内容尚未开始验收，不应按完整产品发布。**

## 2. 实际架构与代码归属

### 2.1 分层

| 层 | 主要入口/文件 | 当前实际职责 | 归属判断 |
|---|---|---|---|
| 引擎入口 | `game/scripts/main.lua` | 读取环境变量、创建 Bootstrap、初始化 LuaSTG/资源、注册 `FrameFunc` | TNR 入口代码 + LuaSTG API |
| 游戏状态机 | `game/scripts/tnr/bootstrap.lua` | MENU、MAP、MAP_PREPARATION、训练、ENCOUNTER、失败/通关状态切换 | TNR 自有 |
| 会话状态 | `game/scripts/tnr/core/game_session.lua` | 种子、地图、玩家、队伍、节点、准备、奖励、命令分发 | TNR 自有 |
| 地图 | `game/scripts/tnr/map/*.lua` | 生成图、节点链接、访问和选择、地图视图 | TNR 自有 |
| 遭遇/战斗适配 | `game/scripts/tnr/encounter/*`、`battle/stage_adapter.lua` | 将节点/训练项目映射为原生房间或 TNR fallback | TNR 适配层 |
| 原生运行时 | `game/scripts/legacy_native_main.lua`、`LegacyTHlib/`、`THlib.lua`、`game/legacy/` | 原始 THlib 对象池、敌人、Boss、符卡、Reimu、背景、弹幕、特效 | 直接导入的 Legacy runtime |
| 角色/装备数据 | `character/`、`equipment/`、`preparation/` | 定义、实例、库存、配装、冲突、容量和 Ready | TNR 自有数据层，目前不是原生战斗运行时 |
| 网络 | `multiplayer/lan_transport.lua`、`battle_sync.lua`、`aggro.lua` | TCP 帧、输入、事件、快照、时钟、锁步/纠偏、仇恨数据 | TNR 自有桥接 |
| UI | `ui/map_renderer.lua`、Bootstrap UI 分支 | 菜单、地图、准备、训练、失败、网络输入界面 | TNR 自有菜单式 UI |
| 调试 | `debug/debug_command.lua`、`debug/console.lua` | 文本命令解析和会话/战斗调试入口 | TNR 自有 |

`StageAdapter` 同时包含三种路径：原生桥接路径、TNR 纯 Lua fallback 路径和训练路径。代码中存在的 fallback 不能视为参考项目的原始弹幕实现。

### 2.2 启动调用链

```text
LuaSTGSub.exe (工作目录必须为 game)
  -> game/scripts/main.lua
  -> legacy_native_main.lua / TNRNativeLegacy 注册
  -> Bootstrap.create()/init()
  -> FrameFunc
  -> Bootstrap:update()
       -> 输入轮询 / LANTransport:update()
       -> MENU / MAP / MAP_PREPARATION / training / ENCOUNTER 分支
       -> StageAdapter:update()
            -> TNRNativeLegacy.update()/update_remote()
            -> 或 TNR fallback battle tick
  -> Bootstrap:render()
       -> MapRenderer 或原生桥接 render()
```

`main.lua` 在 `TNR_NETWORK_MODE=host/client` 时创建 `LANTransport`，设置本地玩家 ID、地址、端口和种子；单人模式设置 `player_count=1`，联机模式设置 `player_count=2`。单人模式当前跳过 Phase 2 的强制整备，联机模式也通过 `preparation_required=false` 保留已有网络流程。

## 3. 实际游戏流程

### 3.1 单人流程

```text
MENU
  -> 开始游戏
  -> GameSession:start_new(seed)
  -> MAP
  -> 点击/键盘选择相邻节点
  -> 战斗节点：ENCOUNTER（网络关闭时会经过 MAP_PREPARATION 的单人 Ready 流程）
  -> StageAdapter:start(encounter)
  -> 原生房间或 fallback
  -> BattleResult
  -> BATTLE_CLEARED -> 奖励 -> MAP，或 BOSS -> RUN_CLEAR
  -> 失败 -> RUN_FAILED / 训练失败界面
```

### 3.2 联机流程

```text
主机监听 TCP / 客机连接 TCP
  -> 两端各自 start_new(相同 run seed)
  -> MAP 中分别提交 VOTE_NODE
  -> 两票相同且合法后进入相同 encounter
  -> ENCOUNTER_READY / START_ENCOUNTER_AT 时钟屏障
  -> 两端各自启动原生对象池
  -> 双向发送本地玩家输入，周期发送 snapshot/peer_snapshot
  -> 各端本地计算弹幕、碰撞和特效，有限状态快照尝试纠偏
```

事件匹配依赖 `node_id`、`encounter` 和启动时间；当前没有独立 Lobby、重连、协议版本协商或可靠的房间生命周期服务。两端同时进入、同一房间和退出菜单虽然有代码屏障，但仍属于需要实体机复测的部分完成项。

## 4. 地图系统

| 能力 | 状态 | 代码证据/说明 |
|---|---|---|
| 随机地图 | **IMPLEMENTED** | `map_generator.lua:generate()` 使用 `RNG.new(seed)` 生成节点和链接 |
| 固定种子复现 | **IMPLEMENTED** | `GameSession:start_new()` 保存 `run_seed`，节点另存 `content_seed` |
| 左到右分层 graph | **IMPLEMENTED** | `make_layout()`、`connect_layers()` 只连接相邻层，按垂直序连接以避免交叉 |
| START/ENEMY/ELITE/BOSS/SHOP/EVENT | **IMPLEMENTED/PARTIAL** | 类型和布局已生成；Boss 终点固定，普通/精英内容有映射 |
| 相邻节点选择 | **IMPLEMENTED** | `MapState:is_adjacent()`、`select_node()`、`MapScene` 键盘/鼠标选择 |
| 节点访问记录 | **IMPLEMENTED** | `MapNode.visited` 与 `MapState:select_node()` 更新 |
| 全图显示/可达高亮 | **IMPLEMENTED** | `MapRenderer:render_map()` 绘制节点、线和 selectable 状态 |
| 回退/回溯 | **PARTIAL** | `find_path()` 存在，但选择规则只允许当前节点的相邻链接，未形成完整回溯机制 |
| 追击/腐化/地图压力 | **NOT IMPLEMENTED** | 无对应状态机或地图字段逻辑；`MapNode.corrupted` 只是数据字段 |
| 多人地图票 | **PARTIAL** | `VOTE_NODE` 和 `MAP_VOTE_CHANGED` 有实现；依赖 TCP 命令转发，断线/超时处理不足 |
| 多人地图状态权威 | **PARTIAL** | 两端各自持有 `GameSession`，没有独立地图快照/版本号和冲突恢复 |

地图内容的随机选择是“节点 encounter ID + content seed”级别；不是对所有原生敌人对象逐个序列化的关卡存档。

## 5. 战斗和遭遇

### 5.1 房间类型

| 房间/功能 | 当前路径 | 真实性和状态 |
|---|---|---|
| 普通敌怪房 | `start_room("enemy", seed)` | **PARTIAL**。使用导入的原生 enemy wave，并在适配层判断波次/Boss 非符；过去有波次不完整、位置/资源/结束转换问题 |
| 精英房 | `start_room("elite", seed)` | **PARTIAL/HIGH RISK**。映射到 `elite_stage_01`，依赖原生 Boss 类的少面内容；历史上出现过 invalid lstg object |
| Boss 房 | `start_room("boss", seed)` | **PARTIAL/HIGH RISK**。原生 Boss/card 列表可启动，但资源缺失、特效、计时和桥接同步需实体机验证 |
| 符卡练习 | `start_training(card_id)` | **PARTIAL**。有原生 card slot 入口，非原生条目会明确报错；不是所有导入资源均可运行 |
| 非符练习 | `start_training`/原生非符入口 | **PARTIAL**。目录来源于原始导出，但需配套阶段前置和资源；部分运行错误曾出现在日志 |
| 小怪练习 | `start_enemy_training(enemy_id)` | **PARTIAL**。`legacy_enemy_waves.lua` 按面前/道中 Boss 后分组，原始构造记录保留，但波次运行仍有已知风险 |
| TNR fallback | `StageAdapter:_create_runtime()` | **IMPLEMENTED AS FALLBACK**。可用于纯 Lua/无原生内容，但不等同原版弹幕逻辑 |

### 5.2 原生与 fallback 边界

原生房间由 `legacy_native_main.lua` 负责重置对象池、设置 world、创建 `reimu_player`、加载原始 stage/card；`StageAdapter:update()` 只提供输入、远端代理和状态读取。Fallback 则在 `stage_adapter.lua` 中维护自己的 enemy、bullet、boss、bomb 和 `BattleTick`，其 pattern 分支不能当作参考工程算法。

### 5.3 结束/失败

`StageAdapter` 将原生 `state()` 映射为 `complete(true/false)`；`GameSession:complete_battle()` 生成 `BattleResult`，普通/精英返回地图，Boss 进入 `RUN_CLEAR`，失败进入 `RUN_FAILED`。原生房间的生命/复活仍在桥接层维护，与 TNR `PlayerState.life` 并非同一权威字段。

## 6. 自机、角色和装备

### 6.1 实际战斗自机

真实原生战斗玩家是导入的 `reimu_player`/`player_class`，不是 `tnr.character` 或 `PlayerState` 的通用运行时实例。原生路径使用 `lstg.var`、全局 `player`/`lstg.player`、原始 `reimu.lua` 的支持物、射击、碰撞、死亡和 Bomb。

已确认的原生 Reimu 基础行为：

- 高速移动约 `4.5`，低速约 `2`，对角线按 `SQRT2_2` 修正。
- 普通射击为两发直线弹，原始脚本决定间隔、伤害和精灵。
- 支持物最多四个，位置和开火由原生 `slist`、`anglelist`、`support` 等字段驱动。
- 高速/低速支持物使用不同原生弹型。
- Bomb 由原生 `spell`/`PlayerSpell` 触发，高速与低速使用不同效果和保护时间。
- 原生玩家死亡、残机、擦弹、道具收集和碰撞在 THlib 中执行；联机时额外套有桥接的远端/团队复活逻辑。

### 6.2 TNR 数据层

`CharacterDefinition`、`ReimuDefinition`、`PlayerLoadout`、`EquipmentDefinition`、`EquipmentInstance`、`Inventory`、`PreparationState` 已完成纯数据操作和序列化。Reimu 初始高/低武器、支持和角色遗物已经进入数据配装。

当前明确不是战斗运行时的内容：

- 装备定义没有替换原生 `reimu_player` 的射击/支持生成。
- 容量/重量只影响数据校验和 UI，不改变原生移动或火力。
- Modifier、Relic、状态效果、掉落装备事件没有完整接入原生卡/敌人。
- `PlayerState.life/bomb/score/graze` 与原生 `lstg.var` 存在双层状态；`legacy_life_compat=true` 明确表示兼容边界。

## 7. 联机协议和同步模型

### 7.1 传输实现

`LANTransport` 使用 LuaSocket `socket` 或 `socket.core`，TCP 长度前缀帧（8 位十六进制长度）承载自定义序列化表。主机监听 `0.0.0.0:port`，客机连接配置的 IP/主机名和端口；没有 UDP、NAT 穿透、Lobby、重连或加密。

### 7.2 实际消息类型

| 类型/通道 | 发送方 -> 接收方 | 字段/内容 | 频率/用途 | 当前状态 |
|---|---|---|---|---|
| `command` | 客机/主机 -> 对端 | `type` 及命令字段（如 `VOTE_NODE`、`COMPLETE_BATTLE`、`START_ENCOUNTER_AT`） | 事件发生时；主机收到后转发 | **PARTIAL**，没有通用 ACK/去重 |
| `event` | 主机 -> 客机 | 会话事件或 `INPUT_BUNDLE` | 主机广播 | **PARTIAL**，依赖主机转发 |
| `input` | 双向 | `player_id`、`tick`、`move_x/y`、`shoot`、`focus`、Bomb/确认边沿 | 每次本地输入轮询/发送 | **IMPLEMENTED/PARTIAL**，边沿合并已有防重复逻辑 |
| `snapshot` | 主要主机 -> 客机 | room、frame、Boss HP/timer/card、敌人 alive/位置/HP、玩家状态、复活、team life、Bomb generation/events、aggro | 原生桥接周期性发布；通常 30 帧级别 | **PARTIAL**，快照覆盖有限且应用时会改本地状态 |
| `peer_snapshot` | 双向 | 本端玩家、敌人和 Boss 的轻量状态 | 周期性发布 | **PARTIAL**，用于修正/观察，不是完整世界同步 |
| `clock_ping/pong/ready` | 客机/主机 | nonce、client/host time、offset、RTT、error | 连接/启动屏障阶段 | **PARTIAL**，只做简单中位数估计 |
| `ping/pong` | 双向 | `sent_at` | 手工/基础连通性 | **IMPLEMENTED** |

项目命令常量还包含 `SELECT_NODE`、`ADD_MONEY/SCORE/LIFE/BOMB`、`BATTLE_FAILURE_VOTE`、`NATIVE_LEAVE_BATTLE`、装备/背包/Ready 和调试命令。没有单独命名的 `PLAYER_HIT`、`BOSS_HP`、`STAGE_CLEAR` 数据包；这些状态被塞进 snapshot、event 或会话命令中。

### 7.3 权威关系

- 本地玩家的键盘输入由本机 `LuaSTGInputProvider` 产生，再发送给对端。
- 远端玩家在另一端是 `native_remote_player` 代理，由收到的输入在本地积分移动，并由 `native_render_remote_player()` 绘制。
- 原生敌人/弹幕在两端各自对象池运行；主机具有 `set_authority(true)` 分支，会周期性提供敌人/Boss/团队状态，但不是逐帧权威模拟。
- 客机可应用主机 `snapshot`，但也会本地执行原生对象池和特效；因此是混合模型，不是纯主机权威或纯客户端权威。
- Bomb 通过输入边沿和 Bomb generation/event 转发，意图是清除对端敌弹并播放一次效果；视觉与伤害仍依赖每端各自对象池，存在不同步风险。
- 掉落物被设计为本地维护，不互相收集；这意味着数量/生成时序必须靠确定性或快照补救，不能通过共享对象解决。

### 7.4 同步风险

`BattleSync` 的纯 Lua 路径支持按 tick 收集输入、主机广播 `INPUT_BUNDLE`、30 tick 快照和 world hash 纠偏；但 Bootstrap 对原生房间明确绕过该锁步路径，因为原生 runtime 没有 TNR `BattleTick`。原生房间因此没有完整的输入锁步、Rollback 或可重放状态机。

弹幕没有作为网络对象传输。两端只有在脚本、seed、帧数、敌人状态和玩家目标完全一致时才可能显示一致；任何资源加载、对象创建顺序、随机分支或死亡/复活时序差异都会造成漂移。现有 `Aggro` 仅以 5 秒窗口汇总伤害并选择焦点，不能保证所有原生 Boss 脚本都使用该焦点。

## 8. 生命、复活、Bomb、掉落和经济

| 系统 | 当前实际行为 | 状态 |
|---|---|---|
| 单人生命/Bomb | 原生 `lstg.var`/THlib 为主，TNR 状态仅在非原生或会话层记录 | **PARTIAL** |
| 联机团队生命 | 桥接维护 `native_team_lives`，两人复活状态由 `native_resolve_team_wipe()` 处理 | **PARTIAL/HIGH RISK**，需实体机覆盖同时死亡、退出和跨房间 |
| 个人复活 | `native_respawn_frames[1/2]` 和远端 snapshot | **PARTIAL**，历史上出现过无敌、不可见和菜单不一致 |
| Bomb 清弹 | 本地原生 Bomb + 远端 Bomb event/clear | **PARTIAL/HIGH RISK**，已有重复、看不见、特效残留等历史问题 |
| 掉落物 | TNR fallback 可本地生成；原生掉落对象池各端独立 | **PARTIAL**，不共享交互是设计决定 |
| 金钱/分数 | `GameSession:add_money/add_score`、`BattleManager`、`RewardService` | **IMPLEMENTED**，但原生掉落映射不完整 |
| P/道具/能力 | 原生 item bar 有实现；TNR 新装备/容量不驱动原生 item | **PARTIAL** |
| 奖励 | 按 BattleResult 阈值给 money/life/bomb | **IMPLEMENTED/PARTIAL**，没有完整奖励选择 UI |

## 9. 数据流表

| 数据 | Data 层 | Map Runtime | Battle Runtime | Network |
|---|---|---|---|---|
| 角色 ID/定义 | `CharacterDefinition` | `PlayerState.character_id` | 原生 Reimu 类实际生效 | 只随玩家/快照间接出现 |
| 高/低武器 | `WeaponDefinition`、`Loadout` | 配装/容量校验 | **未接入原生射击** | 未发送完整配装 |
| 支持物 | `SupportDefinition`、`Loadout` | 配装/容量校验 | **未接入原生支持生成** | snapshot 仅有支持数量/布局等桥接字段 |
| Modifier/Relic | 定义、冲突组、固定角色遗物 | 数据/UI | 无通用运行时钩子 | 未作为协议对象 |
| 玩家位置/输入 | `PlayerInput` | 不存地图 | 原生本地/远端代理 | `input`、玩家快照 |
| 敌人/Boss | encounter/stage catalog | 节点 encounter/content seed | 原生对象池或 fallback | snapshot/peer_snapshot 的有限字段 |
| 弹幕/粒子 | 资源/脚本引用 | 无 | 本地原生对象池 | **不发送完整对象** |
| 金钱/分数/生命/Bomb | PlayerState/PartyState | 会话/奖励 | `lstg.var` + 桥接 | snapshot/命令部分同步 |

## 10. UI 完成度

| UI | 状态 | 说明 |
|---|---|---|
| 主菜单 | **IMPLEMENTED** | 单人、局域网主机/加入、三种练习入口、退出 |
| 地图 | **IMPLEMENTED** | 全图、节点图标、连线、当前节点、相邻高亮、票显示 |
| 地图整备 | **IMPLEMENTED/PARTIAL** | 配装、仓库、容量、Ready、丢弃确认；溢出物没有专用弹窗 |
| 战斗 HUD | **PARTIAL** | 原生 HUD + TNR 状态叠加；Boss 血条依赖原生/桥接状态 |
| 奖励界面 | **STUB/PARTIAL** | 奖励服务存在，独立选择/展示流程不完整 |
| 商店 | **PLACEHOLDER** | 节点会进入 `PLACEHOLDER`，没有实际购买流程 |
| 事件 | **PLACEHOLDER** | 节点会进入 `PLACEHOLDER`，没有事件内容系统 |
| 准备/背包 | **IMPLEMENTED** | 菜单式列表交互，支持鼠标命中和键盘 |
| 联机设置 | **IMPLEMENTED/PARTIAL** | 端口、地址、localhost、连接错误和时钟状态；无 Lobby/重连 |
| 调试控制台 | **IMPLEMENTED** | 命令解析存在，但是否可见取决于运行时接线 |

## 11. 调试命令

`DebugCommand` 当前支持：`god`、`kill_all`、`clear`、`clear_reward`、`money`、`score`、`life`、`bomb`、`goto`、`map_reveal`、`give_equipment`、`inventory`、`loadout`、`discard`、`ready`、`unready`、`help`。这些命令主要作用于 TNR 会话或当前已连接的 BattleManager；不能保证改变原生 THlib 的每个全局字段，也没有权限/网络审计。

## 12. 测试和实际证据

### 12.1 已执行并通过

```text
& '..\LuaSTG-Sub-master\tool\lua\lua54.exe' tests\run.lua
TouHouNightReign core tests passed
```

该测试覆盖地图、会话、节点票、奖励、Phase 1 角色/装备/背包、Phase 2 配装操作、Ready、序列化以及 FakeTransport/部分确定性同步场景。它不启动 LuaSTG 图形窗口，也不证明两台实体机 LAN 原生房间一致。

### 12.2 运行日志证据

当前 `game/engine.log` 中仍可见：

- `void_distortion_with_colorburn.fx`、`cameo.fx`、`er_desaturate.fx` Shader 编译失败。
- `Thlib/enemy/scname_sign.png`、`sc_his_stage.png`、`boss_cardleft.png`、`shockwave.png`、`Cherry.png`、`eff_cnlight.png`、`dialog_balloon.png` 等资源读取失败。
- `assets/olc/bullet/etbreak.png` 读取失败。
- 错误工作目录下出现 `main script not found`。

这些是运行环境/资源完整性风险，不应被纯 Lua 测试隐藏。日志包含多个历史会话，不能据此断言每一次当前构建都会复现，但它足以证明原生资源和启动路径尚未达到“零已知错误”。

### 12.3 覆盖缺口

- 未在本次审计中完成逐张原生符卡的实体机自动化回归。
- 未完成两台 LuaSTGSub 实例的长时间 LAN 测试、断帧、重连、跨房间和同时死亡测试。
- 未验证所有 32 个来源关卡、52 个分组小怪波次在当前资源目录中均可稳定运行。
- 没有 Rollback、录制/回放、协议 fuzz、网络丢包/延迟注入测试。

## 13. Git 实际状态

仓库：`E:\gemesmods\stg\TouHouNightReign`。  
HEAD：`c85a88d fix: align menu and map UI text`。  
近期历史包含地图连线、地图 UI、fallback STG、奖励/调试和初始 roguelike 提交。

当前工作区不是干净工作区：

- 多个核心文件处于已跟踪修改状态，包括 `main.lua`、`bootstrap.lua`、`game_session.lua`、`stage_adapter.lua`、`lan_transport.lua`、地图、UI、输入和测试。
- 大量原生脚本、LegacyTHlib、背景/角色/音频/参考资源、训练目录和报告处于未跟踪状态。
- `git diff --stat` 显示 26 个已跟踪文件约 4667 行新增、210 行删除，另有大量未跟踪文件未计入该统计。
- 现状无法通过单个提交区分每个阶段；Phase 1/2 报告也记录了没有为该阶段创建独立提交。

这意味着后续任何修复前都应先建立基线提交或至少保存完整差异清单；本报告没有修改或清理既有工作区变化。

## 14. 超前、死代码和占位内容

### 已超前于最初可玩原型

- 原始 Legacy 资源/脚本导入和原生卡/敌人目录。
- LAN TCP 菜单、端口/IP 输入、时钟启动屏障和有限快照。
- 远端玩家代理、Bomb event、敌人快照、Aggro 五秒窗口。
- Phase 1/2 角色装备数据、背包、容量和地图整备 UI。

### 设计存在但实际未消费

- `CharacterDefinition`/`WeaponDefinition`/`SupportDefinition` 不驱动原生 Reimu 火力。
- `Loadout` 的重量/容量不改变原生移动、射击或支持数量。
- TNR `BattleSync` 对原生房间不生效；原生路径由 Bootstrap 特判绕过。
- `Shop`、`Event`、追击/腐化和完整奖励选择仍通过 Placeholder/服务占位。
- 许多旧的兼容字段和测试资源仍存在，不能当成生产内容。

## 15. 技术债和阻塞项

| 严重度 | 问题 | 影响 |
|---|---|---|
| **CRITICAL** | 原生 `lstg.var`、全局 `player` 与 TNR per-player 状态双轨 | 生命、Bomb、装备和多人状态可能互相覆盖 |
| **CRITICAL** | 原生联机没有逐帧权威模拟/完整弹幕同步 | 敌人、追踪弹、Bomb、特效和玩家显示可能漂移 |
| **HIGH** | 资源清单仍有读取失败，Shader 不兼容 | 某些符卡/特效/音效/结束流程可能直接报错 |
| **HIGH** | 房间启动/退出/同时复活的协议缺少可靠 ACK、版本和重连 | 客机等待、提前退回菜单、跨房间状态残留 |
| **HIGH** | 原生敌人波次和 Boss 过渡依赖适配器状态猜测 | 小怪房清空后非符/Boss 不出现或计时异常 |
| **MEDIUM** | 地图 Shop/Event/追击腐化未实现 | Roguelike 路线内容不完整 |
| **MEDIUM** | 装备数据层尚未接入战斗 | 整备 UI 的实际战斗收益为零 |
| **LOW** | Git 阶段边界不清、未跟踪资源过多 | 难以复现和回滚，审计成本高 |

## 16. 当前阶段和建议

当前阶段应记录为：**Phase 2 已完成代码闭环但尚未完成原生联机验收；项目处于“可审计的架构原型”，不是稳定发行候选。**

在进入任何下一阶段前，建议先完成以下验收顺序：

1. 建立干净 Git 基线，固定 LuaSTG Sub 构建版本、工作目录和资源清单。
2. 用同一份种子逐房间记录两端的 `room_generation`、frame、玩家、敌怪数量、Boss HP、Bomb generation 和离开原因。
3. 对原生单人逐个验证符卡/非符/小怪波次，先解决资源缺失和对象失效，再讨论联机。
4. 对 LAN 做输入边沿、玩家可见性、远端射击/Bomb、敌怪状态、同时死亡、复活、跨房间和断线测试。
5. 明确下一阶段只选一个权威模型；在此之前不要继续扩展装备和地图内容。

本报告到此为止，不启动下一阶段开发。
