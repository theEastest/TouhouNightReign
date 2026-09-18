# TouHouNightReign

## Portable Windows release

Existing folders and ZIPs under `releases/` are frozen snapshots. Apply routine
fixes to the development game under `game/`; only create another release when
explicitly requested.

Share the entire folder (or ZIP) generated under `releases/`. After extracting
the ZIP, players double-click `StartGame.bat` or `TouHouNightReign.exe`.
The Windows x64 package includes the Release engine, runtime DLLs, game assets,
Chinese fonts, and a player README. It starts with a fresh `userdata` folder.

To rebuild and package the current working copy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\package_release.ps1 -CMake 'D:\cmake\CMAKE\bin\cmake.exe'
```

Use `-SkipBuild` only when the engine's `build/amd64/bin` already contains a
current Release build. Output names default to a timestamp; existing releases
are never overwritten. Each package includes `SHA256SUMS.txt`, and the ZIP has
a companion `.sha256` file. Player saves, logs and development junctions are
excluded. The package uses the current files, including uncommitted game work.

The first playable architecture prototype for a roguelike STG built on LuaSTG Sub.

## Layout

- `game/scripts/tnr`: game-owned Lua modules.
- `game/config.json`: LuaSTG Sub runtime configuration.
- `game/legacy`: curated THlib/activity source, sprites, backgrounds, effects,
  and the project-owned legacy manifest.
- `game/assets/players/reimu`: replacement slots for the playable Reimu art.
- `tests`: headless deterministic tests for the game-owned modules.
- `vendor/Bundle-After-Ex-Plus`: reference copy of the official LuaSTG Sub + THlib bundle.

The engine source remains outside this project in `../LuaSTG-Sub-master`. The game code is kept separate from engine and THlib code so the engine can be updated without rewriting the run state model.

## Current status

Milestones 1-3 are implemented as a playable prototype: deterministic map generation, GameSession, player/party state, map selection, native THlib enemy/card encounters, BattleResult, Money/Score tracking, and configurable rewards. The map contains ordinary, elite, and boss rooms. Room content is selected from the run seed and the original object/card classes execute through the native LuaSTG object pool.

Run the headless tests with:

```powershell
..\LuaSTG-Sub-master\tool\lua\lua54.exe tests\run.lua
```

The LuaSTG Sub executable is not included in the source checkout. Building it requires the toolchain documented by the engine (`CMake 3.31+` and Visual Studio 2022).

Run the project from the engine build with the working directory set to `game`:

```powershell
& "..\..\LuaSTG-Sub-master\build\amd64\bin\LuaSTGSub.exe"
```

The first prototype uses the arrow keys to select map nodes, `Enter` or `Space`
to confirm, and the mouse to click adjacent nodes. The first menu entry is
single-player: P1 uses the arrow keys, `Z` to shoot, `X` to use Bomb, and
`LeftShift` to focus. LAN host/client entries create the two-player session and
use the same controls on both computers. Same-machine co-op can still be
created programmatically with `player_count = 2` and custom P2 bindings.
Reimu's normal/focused shot profiles and Bomb behavior are defined in
`game/scripts/tnr/player/player_profile.lua`. The replacement art filenames and
reference dimensions are documented in
`game/assets/players/reimu/README.md`.

The main menu also provides `符卡训练`. Select a card with the keyboard or
mouse, then practice it directly. A training death opens a restart/return
choice; training does not modify the active map run.

The main menu includes `Music Player`, which opens the reference music player. Use Up/Down to select a track, Enter to play it, and Esc to return. The menu, player, and native stage bridge share one audio coordinator, so at most one BGM is active; a reference stage without a startup music command keeps the current track.

The native THlib bridge is loaded by default. `TNR_NATIVE_AUTO_CARD=1` starts
the first imported card immediately for a smoke test; normal play starts in the
menu and enters native rooms from the map.

For room smoke tests, set `TNR_NATIVE_AUTO_ROOM=ENEMY`, `ELITE`, or `BOSS`.
This generates the configured seed and jumps directly into that native room.

## Native reference-card verification

The native adapter executes the generated reference card code through
the copied THlib object, task, collision, background, and boss systems. It is
useful for checking an individual original card while the regular menu remains
the default:

```powershell
$env:TNR_NATIVE_LEGACY = "1"
$env:TNR_LEGACY_BOSS = "reimu"       # reimu, marisa, sanae, mystia, larva, cirno, junko ...
$env:TNR_LEGACY_CARD_INDEX = "4"      # index in that boss class' original card list
# Alternatively select by the exact card name in the generated source:
# $env:TNR_LEGACY_CARD_NAME = "..."
& "..\..\LuaSTG-Sub-master\build\amd64\bin\LuaSTGSub.exe"
```

The native adapter keeps the reference card algorithms and timing intact. The
activity export is missing several optional THlib HUD sheets and legacy HLSL
effects, so those resources use project fallbacks; this does not alter bullet
generation or card state logic.

To run the native input self-test inside the real LuaSTG engine, set
`TNR_NATIVE_INPUT_SELFTEST=1`. It verifies local movement, shooting, Bomb
consumption, and remote-player movement, then exits with a failure dialog if
any assertion fails (a successful check continues into the game):

```powershell
$env:TNR_NATIVE_INPUT_SELFTEST = "1"
Set-Location "E:\gemesmods\stg\TouHouNightReign\game"
& "E:\gemesmods\stg\LuaSTG-Sub-master\build\amd64\bin\LuaSTGSub.exe"
```

## Practice modes and randomized encounters

The menu has three independent practice entries:

- Card practice uses `game/scripts/tnr/training/card_training_catalog.lua`.
- Non-spell practice uses `game/scripts/tnr/training/nonspell_training_catalog.lua`.
- Enemy practice uses `game/scripts/tnr/training/enemy_training_catalog.lua`.

Every combat node stores a content seed. Ordinary rooms create original
activity small-enemy classes plus one original non-spell; elite rooms choose a
reference boss class with fewer than three cards; boss rooms run a complete
reference boss card list. The same run seed reproduces the same room choices.

Imported visual and audio assets are active in native rooms. Night-road
background layers are in `game/assets/backgrounds/night_road`, character and
boss art is in `game/assets/players` and `game/assets/bosses`, and reused WAV/OGG
files are in `game/assets/audio`. Loader registrations are grouped in
`game/scripts/main.lua`; playback is centralized in
`game/scripts/tnr/audio/audio_manager.lua`.

## LAN empty-room prototype

LAN battles use the same TCP transport as map voting. Each endpoint owns one
local Reimu and one translucent remote proxy, and both endpoints exchange the
input state for their locally controlled player (movement, shooting, focus and
Bomb edge). Native rooms run the original enemy/card object pool independently
on both machines. Every 30 battle frames each side sends a compact peer
snapshot (enemy alive/position/HP plus Boss HP/timer) to correct drift; full
bullet and particle pools are never serialized. Bombs are transmitted as small
sequence-numbered events so the peer clears its local enemy bullets and plays
the original Bomb effect once. Drops remain process-local by design.

The main menu now contains `开设局域网服务器` and `加入局域网服务器`:

- Hosting asks only for a TCP port and listens on all local interfaces.
- Joining asks for the server address and port. Both `localhost` and LAN IPv4
  addresses such as `192.168.1.100` are accepted.
- Type directly into the selected field, use Up/Down or Tab to switch fields,
  Enter to continue/connect, and Escape to return.
- After connecting, both peers open the same deterministic map. P1 and P2 may
  vote for different reachable nodes; the party advances only when both votes
  point to the same node. Each vote is shown above its node, and confirming a
  different node replaces the local player's previous vote.

The environment-variable launch below remains available as a development and
two-machine automation shortcut.

Start the host first:

```powershell
$env:TNR_NETWORK_MODE = "host"
$env:TNR_PLAYER_ID = "1"
$env:TNR_EMPTY_ROOM = "1"
$env:TNR_RUN_SEED = "20260826"
& "..\..\LuaSTG-Sub-master\build\amd64\bin\LuaSTGSub.exe"
```

For two windows on the same PC, use the same commands but set the client
environment to localhost:

```powershell
$env:TNR_NETWORK_MODE = "client"
$env:TNR_PLAYER_ID = "2"
$env:TNR_HOST = "127.0.0.1"
$env:TNR_EMPTY_ROOM = "1"
$env:TNR_RUN_SEED = "20260826"
& "..\..\LuaSTG-Sub-master\build\amd64\bin\LuaSTGSub.exe"
```

On another computer, set `TNR_HOST` to the host's LAN IPv4 address:

```powershell
$env:TNR_NETWORK_MODE = "client"
$env:TNR_PLAYER_ID = "2"
$env:TNR_HOST = "192.168.1.100"
$env:TNR_EMPTY_ROOM = "1"
$env:TNR_RUN_SEED = "20260826"
& "..\..\LuaSTG-Sub-master\build\amd64\bin\LuaSTGSub.exe"
```

The default TCP port is `27123` and can be overridden with `TNR_PORT`. The
engine must expose LuaSocket; otherwise the HUD reports a network error. See
[`docs/multiplayer-prototype.md`](docs/multiplayer-prototype.md) for the current
verification boundary and remaining LAN battle work.
