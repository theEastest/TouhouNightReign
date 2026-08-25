# Milestone 0: 工程调查

## 结论

本项目采用以下边界：

- 引擎基础：`../LuaSTG-Sub-master`，版本 `0.21.129`。
- 游戏框架参考：`vendor/Bundle-After-Ex-Plus`。
- 游戏自有逻辑：`game/scripts/tnr`。
- 运行入口：`game/scripts/main.lua`。
- 单机传输：`LocalTransport`。
- 未来联网：保留 `LANTransport` 接口，不实现 socket。

## 当前工程结构

### LuaSTG Sub

`LuaSTG-Sub-master` 是 C++ 引擎和 Lua API 源码。引擎的自定义脚本入口在 `LuaSTG/LuaSTG/Custom/AppFrameLuaEx.cpp`，按 `main.lua`、`src/main.lua` 的顺序查找入口脚本。Lua 生命周期在 `LuaSTG/doc/luastg/lstg.lua` 中约定为：

```text
GameInit -> FrameFunc -> RenderFunc -> GameExit
```

本项目的 `game/scripts/main.lua` 遵循这个入口契约，只负责调用游戏层 Bootstrap。

### THlib / aex+ 框架

官方整合框架的 `game/packages/thlib-scripts` 提供两套可复用层：

- `foundation.SceneManager`：高层场景管理。
- `THlib/ext/ext.lua`：将 `GameScene` 与传统 `stage.current_stage` 连接。
- `THlib/ext/ext_stage_group.lua`：传统 `stage.New`、`stage.Set`、Stage Group 生命周期。
- `THlib/player`、`THlib/enemy`、`THlib/bullet`、`THlib/item`：STG 基础对象。

本项目的地图场景不直接调用 Stage；后续由 `EncounterManager` 将 encounter definition 转换为 `stage.Set` 请求。

## Player / Score / P / Life / Bomb

在整合框架中，传统战斗状态仍主要保存在 `lstg.var`：

- `lstg.var.score`：传统累计分数。
- `lstg.var.power`：传统 P 点对应的 Power 状态。
- `lstg.var.lifeleft`：残机。
- `lstg.var.bomb`：Bomb 数量。
- `lstg.var.faith`、`lstg.var.pointrate`：传统资源/得分辅助字段。

`THlib/item/item.lua` 中的 `GetPower`、`item.PlayerInit`、`item.PlayerMiss` 和 `item.PlayerSpell` 直接读写这些字段。任务书要求的 Money、Battle Score、Total Score 不适合继续塞进这些传统字段，因此新代码以 `GameSession` / `PlayerState` 为权威，并在 STG adapter 中做有限同步。

## Stage 切换机制

当前可用两层机制：

1. 高层 `SceneManager.setNext` 切换 `GameScene` 等 Lua 场景。
2. 低层 `stage.Set(stage_name, ...)` 切换 THlib Stage 或 Stage Group。

计划中的流程是：

```text
MapNode
  -> EncounterManager
  -> STG Adapter
  -> stage.Set(test_enemy_stage/test_boss_stage)
  -> BattleResult
  -> GameSession
  -> MapScene
```

## 最适合加入 Roguelike Map Scene 的位置

地图属于游戏层，放在 `game/scripts/tnr/map`，并由 `tnr.bootstrap` 驱动。它不应加入 THlib 原有 `THlib/ext` 或 `THlib/UI`。这样地图状态可以保持纯 Lua table，后续可用于存档、快照和网络同步。

## 必须修改的 THlib 文件

当前阶段没有必须修改的 THlib 文件。后续接入战斗时，优先增加以下适配层：

- `tnr/battle/luastg_adapter.lua`：读取 Stage 生命周期和击杀/结算信号。
- `tnr/battle/item_adapter.lua`：将 Power item 的拾取转换为 `ADD_MONEY`，避免直接改写 THlib 的基础类。
- `tnr/battle/player_adapter.lua`：把生命、Bomb、命中和 Bomb 使用同步到 PlayerState。

只有当某个旧接口无法通过 wrapper 捕获时，才在 THlib 中增加最小 hook，并记录原因。

## 可以完全通过新增模块完成的部分

- GameSession、PlayerState、PartyState、PlayerManager。
- RNG 和确定性地图生成。
- MapNode、MapState、MapScene。
- Command/Event 入口。
- LocalTransport、LANTransport stub、InputProvider。
- EncounterDefinition、EncounterManager。
- BattleResult、RewardService。
- DebugConsole 和 DebugCommand（下一阶段）。

## 已知冲突和风险

1. 当前本机 CMake 为 `3.20.0-rc1`，而 LuaSTG Sub 工程要求 CMake `3.31+`，因此现有 Preset 无法解析。
2. 当前 PowerShell 环境没有发现 Visual Studio/MSBuild；源码构建还需要 VS2022 和 Windows SDK。
3. 本地最初的 `lstgx_THlib-master` 面向 LuaSTG-x；已获取官方 `Bundle-After-Ex-Plus` 作为更适配 Sub 的参考，但其若干历史资源子模块仓库已不存在，不能假设其资源子模块完整可用。
4. 现阶段可以对游戏层做纯 Lua 确定性测试，但尚未声称原引擎已成功启动。引擎启动验证需要补齐 CMake/Visual Studio 工具链或提供预编译 LuaSTGSub.exe。

## Milestone 1 实施方案

Milestone 1 先完成并测试以下闭环：

```text
New Game
  -> GameSession:start_new(run_seed)
  -> MapGenerator.generate(run_seed)
  -> MapScene view
  -> SELECT_NODE command
  -> MapState.select_node
  -> ENCOUNTER_STARTED / PLACEHOLDER_ENTERED event
```

已实现的文件位于 `game/scripts/tnr`，测试位于 `tests/run.lua`。战斗 Stage 适配、Money item 替换和 Debug Console 留在后续 Milestone，避免在引擎尚未能构建时把核心状态和 THlib 全局变量耦合起来。

