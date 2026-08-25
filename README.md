# TouHouNightReign

The first playable architecture prototype for a roguelike STG built on LuaSTG Sub.

## Layout

- `game/scripts/tnr`: game-owned Lua modules.
- `game/config.json`: LuaSTG Sub runtime configuration.
- `tests`: headless deterministic tests for the game-owned modules.
- `vendor/Bundle-After-Ex-Plus`: reference copy of the official LuaSTG Sub + THlib bundle.

The engine source remains outside this project in `../LuaSTG-Sub-master`. The game code is kept separate from engine and THlib code so the engine can be updated without rewriting the run state model.

## Current status

Milestone 1 is implemented: deterministic map generation, GameSession, player/party state, map selection, command/event entry points, and transport/input abstractions.

Run the headless tests with:

```powershell
..\LuaSTG-Sub-master\tool\lua\lua54.exe tests\run.lua
```

The LuaSTG Sub executable is not included in the source checkout. Building it requires the toolchain documented by the engine (`CMake 3.31+` and Visual Studio 2022).

