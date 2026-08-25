# TouHouNightReign

The first playable architecture prototype for a roguelike STG built on LuaSTG Sub.

## Layout

- `game/scripts/tnr`: game-owned Lua modules.
- `game/config.json`: LuaSTG Sub runtime configuration.
- `tests`: headless deterministic tests for the game-owned modules.
- `vendor/Bundle-After-Ex-Plus`: reference copy of the official LuaSTG Sub + THlib bundle.

The engine source remains outside this project in `../LuaSTG-Sub-master`. The game code is kept separate from engine and THlib code so the engine can be updated without rewriting the run state model.

## Current status

Milestones 1-3 are implemented as a playable prototype: deterministic map generation, GameSession, player/party state, map selection, enemy and boss encounters, fallback STG battle runtime, BattleResult, Money/Score tracking, and configurable rewards. The THlib `stage.Set` adapter remains available for replacing the fallback runtime when the complete THlib resource set is installed.

Run the headless tests with:

```powershell
..\LuaSTG-Sub-master\tool\lua\lua54.exe tests\run.lua
```

The LuaSTG Sub executable is not included in the source checkout. Building it requires the toolchain documented by the engine (`CMake 3.31+` and Visual Studio 2022).

Run the project from the engine build with the working directory set to `game`:

```powershell
& "..\LuaSTG-Sub-master\build\amd64\LuaSTG\Release\LuaSTGSub.exe"
```

The first prototype uses the arrow keys to select map nodes, `Enter` or `Space`
to confirm, and the mouse to click adjacent nodes. During a battle, use the
arrow keys to move, `Z` to shoot, `X` to use Bomb, and `LeftShift` to focus.
