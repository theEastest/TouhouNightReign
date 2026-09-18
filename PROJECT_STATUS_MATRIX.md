# TouHouNightReign 当前状态矩阵

日期：2026-08-30  
状态定义：

- **IMPLEMENTED**：代码闭环存在，纯 Lua/静态证据足够，且没有已知核心缺口。
- **PARTIAL**：代码路径存在，但只覆盖部分模式、依赖适配器，或已有运行风险。
- **STUB/PLACEHOLDER**：有入口或数据占位，但没有实际玩法闭环。
- **NOT IMPLEMENTED**：当前代码没有可执行功能。

## 总览

| 模块 | 状态 | 实际结论 | 关键证据 |
|---|---|---|---|
| LuaSTG 入口 | IMPLEMENTED | `main.lua` 创建并驱动 Bootstrap | `game/scripts/main.lua` |
| TNR 状态机 | IMPLEMENTED | 菜单、地图、训练、战斗、失败/通关状态存在 | `tnr/bootstrap.lua` |
| 单人菜单/地图 | IMPLEMENTED | 键盘和鼠标可选节点 | `tnr/ui/map_renderer.lua`、`map_scene.lua` |
| 随机种子地图 | IMPLEMENTED | 同 seed 生成同一分层 graph | `map_generator.lua`、`core/rng.lua` |
| 无交叉左到右连线 | IMPLEMENTED | 仅连接相邻层，保持垂直序 | `map_generator.lua:connect_layers` |
| 地图回溯 | PARTIAL | 有寻路函数，选择仍受相邻规则限制 | `map_state.lua` |
| 追击/腐化 | NOT IMPLEMENTED | 没有运行时系统 | 无对应状态机 |
| 普通敌怪房 | PARTIAL | 原生 wave 可映射，结束/位置/资源仍有风险 | `stage_adapter.lua`、`legacy_native_main.lua` |
| 精英房 | PARTIAL | 有 elite 映射，原生 Boss 对象生命周期未稳定验收 | `definitions.lua` |
| Boss 房 | PARTIAL | 原生 card 列表入口存在，资源/跨端风险高 | `start_room("boss")` |
| 符卡练习 | PARTIAL | 原始 card slot 可进入，非原生条目拒绝 | `StageAdapter:start_training` |
| 非符练习 | PARTIAL | 有目录和入口，依赖原生前置/资源 | training catalog + native bridge |
| 小怪练习 | PARTIAL | 52 个分组波次目录，需实体机逐项验收 | `legacy_enemy_waves.lua` |
| TNR fallback 战斗 | IMPLEMENTED AS FALLBACK | 纯 Lua enemy/bullet/boss 可运行，但不是原版逻辑 | `stage_adapter.lua` |
| Reimu 原生自机 | IMPLEMENTED | 原始 THlib 类、支持、射击、Bomb | `game/legacy`、`legacy_native_main.lua` |
| 通用 CharacterDefinition | IMPLEMENTED AS DATA | 定义/注册/序列化完成，未接战斗 | `tnr/character/*` |
| 武器/支持配装 | IMPLEMENTED AS DATA | 背包、槽位、重量和冲突可操作 | `tnr/equipment/*` |
| 装备影响原生火力 | NOT IMPLEMENTED | 原生仍直接使用 Reimu 类 | `reimu.lua`/`stage_adapter.lua` |
| 地图整备/Ready | IMPLEMENTED/PARTIAL | 单人可提交，网络不纳入新协议 | `PreparationState`、`LoadoutService` |
| Shop | IMPLEMENTED | 三槽确定性商品、私人购买与 Ready 状态 | `tnr/shop/shop_service.lua`、`GameSession` |
| Event | STUB/PLACEHOLDER | 仅进入占位状态 | `GameSession:select_node` |
| 金钱/分数 | IMPLEMENTED | 会话、战斗管理器、奖励阈值存在 | `BattleManager`、`RewardService` |
| 奖励/装备入库 | IMPLEMENTED | Enemy clear 创建 EquipmentInstance，经 AcquisitionService 入库 | `reward_service.lua`、`equipment_reward_service.lua` |
| Capacity progression | IMPLEMENTED | Score 阈值立即更新 Capacity/Level | `character/runtime/capacity_progression.lua` |
| Relic Runtime | IMPLEMENTED | 永久普通/角色遗物、Boss 三选一、Reimu 无伤碎片钩子 | `relic/relic_runtime.lua` |
| LAN TCP | IMPLEMENTED/PARTIAL | LuaSocket TCP 长度帧，host/client 菜单 | `lan_transport.lua` |
| LAN UDP/NAT/Lobby | NOT IMPLEMENTED | 没有对应服务 | 无 |
| 输入同步 | PARTIAL | 双向 input，边沿合并；原生房间不走完整锁步 | `LANTransport`、`BattleSync` |
| 远端玩家显示 | PARTIAL | proxy + snapshot，历史上有不可见/裁剪风险 | `native_remote_player` |
| 远端玩家射击 | PARTIAL | 本地重放 Reimu shoot，追踪弹/对象顺序有风险 | `update_remote` |
| Bomb 同步 | PARTIAL/HIGH RISK | event/sequence/清弹入口存在，特效和消耗需实体机验收 | `native_apply_remote_bomb_event` |
| 敌人状态同步 | PARTIAL | 周期 snapshot，非逐帧权威 | `native_capture_enemy_states` |
| Boss HP 同步 | PARTIAL | snapshot 传 HP/timer/card | `snapshot`/`apply_snapshot` |
| 完整弹幕/粒子同步 | NOT IMPLEMENTED | 不传对象池，依靠本地确定性 | `docs/multiplayer-prototype.md` |
| 确定性 RNG/Hash | PARTIAL | TNR BattleSync 有 hash；原生桥接没有完整 rollback | `battle_sync.lua` |
| 仇恨/索敌 | PARTIAL | 5 秒 damage window，未保证所有原生脚本消费 | `multiplayer/aggro.lua` |
| 团队生命/复活 | PARTIAL/HIGH RISK | 桥接字段和同时复活判断存在 | `native_resolve_team_wipe` |
| 本地独立掉落物 | PARTIAL | 设计为不互通，但原生数量一致性未证明 | native snapshot/drop handling |
| Debug Console | IMPLEMENTED | 调试命令解析和会话接线 | `debug_command.lua`、`console.lua` |
| Shader/资源完整性 | PARTIAL/HIGH RISK | 日志仍有缺失资源/编译失败 | `game/engine.log` |
| 纯 Lua 自动化测试 | IMPLEMENTED | 当前命令输出 `TouHouNightReign core tests passed` | `tests/run.lua` |
| 实体机 LAN 回归 | NOT VERIFIED | 本次没有将其标为通过 | 文档/日志边界 |

## 联机消息矩阵

| 消息 | 实际发送 | 核心字段 | 主要用途 | 结论 |
|---|---|---|---|---|
| `command` | 双向，主机转发 | `type` + 命令参数 | 地图票、准备、失败、开始屏障 | 有实现，无 ACK/重连 |
| `event` | 主机广播 | 会话事件或 `INPUT_BUNDLE` | 事件通知/输入包 | 部分使用 |
| `input` | 双向 | player、tick、move、shoot、focus、bomb edge | 远端玩家控制 | 有实现，原生仍可能漂移 |
| `snapshot` | 主机 -> 客机为主 | frame、players、enemies、Boss、life、Bomb、team | 房间纠偏 | 有实现，非完整世界 |
| `peer_snapshot` | 双向 | 本端玩家/敌怪/Boss | 观察和补救 | 有实现，职责不完全清晰 |
| `clock_ping/pong/ready` | 客机/主机 | nonce、时间、RTT/error | 启动时间估计 | 部分实现 |
| `ping/pong` | 双向 | 时间戳 | 基础连通性 | 实现 |

## 数据层矩阵

| 数据对象 | 可创建/编辑 | 被地图使用 | 被原生战斗使用 | 被网络传输 |
|---|---:|---:|---:|---:|
| `CharacterDefinition` | 是 | 是 | 否 | 间接 |
| `WeaponDefinition` | 是 | 是 | 否 | 否 |
| `SupportDefinition` | 是 | 是 | 否 | 布局摘要 |
| `ModifierDefinition` | 是 | 是 | 否 | 否 |
| `RelicDefinition` | 是 | 固定角色遗物 | 否 | 否 |
| `Inventory/Loadout` | 是 | 整备 | 否 | 未纳入新联机协议 |
| `PlayerState` | 是 | HUD/奖励 | 与 `lstg.var` 双轨 | 部分快照 |
| 原生 `lstg.var` | 原生修改 | 否 | 是 | 部分映射 |
| 原生敌怪/弹幕对象 | 原生创建 | encounter seed | 是 | 不完整 |

## Git / 测试矩阵

| 项目 | 当前结果 |
|---|---|
| HEAD | `edb8ecc feat: integrate modular player runtime loadouts` |
| 工作区 | 脏，26 个跟踪文件修改，另有大量未跟踪资源/脚本/报告 |
| 纯 Lua 测试 | PASS：`TouHouNightReign core tests passed` |
| Lua 语法/模块加载 | 已有 Phase 报告记录通过；当前审计未将原生启动视为通过 |
| 原生单人房间 | 可进入部分房间，但日志和历史问题要求逐房间验证 |
| 双实例 LAN | 代码入口存在，未达到稳定验收标准 |
| 资源完整性 | FAIL/PARTIAL：日志含缺失纹理、音频/特效依赖和 Shader 编译错误 |

## 当前阶段判定

**Phase 2 数据/地图整备已完成代码闭环；原生战斗和 LAN 联机仍为部分完成、高风险验证区。**  
本矩阵只记录现状，不授权或实现下一阶段开发。
