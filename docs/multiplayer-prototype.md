# 双人联机技术验证进度

## 2026-11-04 更新：旧作重演入口

主菜单“开设局域网服务器”可以在“玩法”字段用左右键选择“旧作重演”，再开始监听。另一台电脑从“加入局域网服务器”输入房主地址与相同端口。房主选择关卡及经典或现代规则，玩家各自选择自机。双方按 Enter 准备后共同开始。战斗中任意一方按 Esc 回到选关，再按 Esc 退出连接。

重演采用团队生命、十秒单人复活、死亡仇恨转移和个人掉落，两人共用 Bomb 库存。共同掉命并消耗一条团队生命时，经典模式恢复到 3 枚，现代模式补足到 3 枚。现代通关后玩家轮流领取奖励，可以在选关时按 Tab 配装。

经典 Normal 已在本机两个独立 LuaSTG 进程上用真实 TCP 连续通过六面，每面结算摘要一致。房主提前选关、客户端入房、双方准备和六面慢速结尾也分别复测通过。实测环境为同一台电脑。阶段记录及现代模式进度见 [th15-reference-audit.md](th15-reference-audit.md)。

下列内容为较早的原型里程碑记录；其中独立 Life 等说明不能覆盖目前采用的团队生命规则。

## 已完成的代码闭环

- 两个 PlayerState / Runtime Player 实例，独立 Life、Bomb、Score、Graze 与输入。
- 敌弹使用 `grazed_by[player_id]`，命中、擦弹和敌人接触逐玩家判定。
- Boss 自机狙通过 Boss RNG 确定性选择存活玩家。
- BattleTick 与 battle/enemy/boss/pattern/reward/visual 独立 RNG 流。
- Pattern 明确记录 `pattern_id`、`pattern_seed`、`pattern_start_tick` 和确定性相位。
- 完整 Gameplay Snapshot 可恢复 BattleTick、RNG、玩家、敌人、敌弹和玩家弹。
- FakeTransport 支持 Host、Client A/B、Command、Event、Input、Snapshot 与 Ping/Pong。
- LANTransport 使用 TCP 长度帧，支持包含换行的 payload、非阻塞分片接收和直接 IP 连接。
- 空房间采用最小锁步：Host 收齐同 Tick 的 P1/P2 输入后才推进，并广播输入包。
- Snapshot 携带 World Hash；Client 记录首个不一致 Tick，并用 Host Snapshot 修复。
- 主菜单可选择开服或加入：开服仅填写端口；加入填写 IP/主机名和端口，支持
  `localhost`。输入框使用 LuaSTG TextInputExtension 接收真实键盘文本。
- 联机成功后双方进入同一张确定性地图。P1/P2 的节点票会同步显示；两票不一致时
  保持在地图上，任一方可以改票，只有两人选择同一个相邻节点才会进入该节点。

纯 Lua 测试覆盖地图单票等待、分歧与改票共识、Host/Client 同节点推进，900 Tick
双 Pattern 实例无漂移、Snapshot 完整恢复、120 Tick 双端空房间锁步，以及人为制造
不同步后的首 Tick 定位和修复。

## 当前边界

自动化测试验证了 Milestone 1-7 所需的游戏层数据链路，但尚未把“两台实体电脑
实测通过”当作已完成。Milestone 8（LAN 小怪关）和 Milestone 9（LAN Boss 关）
仍需在实际 LuaSTG + LuaSocket 环境依次验证，特别是断帧、Bomb 事件、玩家本地
受击权威与 Host 敌人 HP 裁定。

当前没有 Lobby、匹配、NAT 穿透、断线重连、预测、Rollback、Steam 或反作弊。

## 验证命令

```powershell
..\LuaSTG-Sub-master\tool\lua\lua54.exe tests\run.lua
```

实体机空房间测试使用 README 中的 `TNR_NETWORK_MODE`、`TNR_HOST`、
`TNR_PLAYER_ID`、`TNR_RUN_SEED` 和 `TNR_EMPTY_ROOM` 环境变量。两端应能看到 P1/P2
移动一致，HUD 显示 `SYNC OK`；若发生差异则显示首个 mismatch tick。

引擎应以 `LUASTG_LINK_LUASOCKET=ON` 构建。当前使用的 CMake 位于
`D:\cmake\CMAKE\bin\cmake.exe`，版本 3.31.12；VS2022 工具链位于 `D:\vs`。
