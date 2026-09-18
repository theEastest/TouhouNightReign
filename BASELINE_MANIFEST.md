# Baseline Manifest

日期：2026-08-30  
用途：记录当前工作区中未跟踪目录、项目代码和第三方/原始资源的边界。该清单不改变 Git 索引。

## 项目代码

- `game/scripts/main.lua`：LuaSTG 入口和环境变量配置。
- `game/scripts/tnr/`：TNR 会话、地图、战斗适配、角色/装备、训练、UI、调试和联机代码。
- `tests/`：纯 Lua 测试和本阶段原生验证目录。
- `tools/`：资源清单和 Legacy 波次生成工具。
- `docs/`：技术说明、阶段报告和基线记录。

## 原生运行时和参考内容

- `game/scripts/legacy_native_main.lua`：原生 Legacy 桥接，直接被入口加载。
- `game/scripts/LegacyTHlib/`：复制的 THlib 模块，作为原生运行时使用。
- `game/scripts/THlib.lua`：Legacy THlib 总入口。
- `game/legacy/source/`：参考工程导出的 Lua/活动源代码。
- `game/legacy/assets/`：参考工程图片、音频、字体、特效和其它原始资源。

## 项目运行资源

- `game/assets/players/`：Reimu 运行资源和替换美术槽位。
- `game/assets/backgrounds/`：背景层。
- `game/assets/bosses/`：Boss 立绘/符卡背景。
- `game/assets/audio/`：项目可直接加载的音效和音乐。
- `game/assets/reference/`：Legacy 资源索引和哈希清单。
- `game/assets/texture/`：白色 UI/fallback 纹理等基础资源。

## 生成/诊断产物

- `game/engine.log`：引擎历史运行日志，不应作为源码基线。
- `game/network_trace_*.log`：联机诊断输出。
- `game/native_input_selftest.result`：原生输入自检结果。

## 提交边界

建议先提交基线文档、TNR 自有代码和验证测试，再提交经预检确认的代表房间资源。不要在没有确认来源、大小和用途前把完整 `game/legacy/assets/` 作为一个不可审查的大提交；它保留在工作区并由资源索引追踪。
