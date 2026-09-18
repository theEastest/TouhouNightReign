# Phase 0 Report: Current Player and Resource Call Chain

Date: 2026-08-28

## Scope

This phase only audits the existing Reimu/player implementation, input path,
shots, supports, Bombs, death handling, persistent values, scene transitions,
and multiplayer interfaces. No character/loadout refactor was performed.

## Actual runtime entry points

The current native gameplay path is:

```text
scripts/main.lua
  -> legacy_native_main.lua
     -> load_legacy_content()
        -> THlib.lua and legacy THlib modules
        -> Thlib/player/reimu/reimu.lua
        -> _editor_output.lua (original bosses/cards/enemies)
     -> setup_native_stage()
  -> Bootstrap:update()
     -> StageAdapter:update()
        -> TNRNativeLegacy.update()
           -> DoFrame()
              -> stage.Update()
              -> ObjFrame()
              -> collision/bound checks
```

The project resource mounts in `game/config.json` expose `scripts/`, `assets/`,
the copied THlib data, and the original activity source. Native rooms are
created by `StageAdapter:start()` and direct practice rooms by
`StageAdapter:start_training()` or `start_enemy_training()`.

## Player implementation

The actual player is the original `reimu_player` class from
`game/legacy/source/data/Thlib/player/reimu/reimu.lua`, inheriting from the
original `player_class` in `Thlib/player/player.lua`. It is not the project
`PlayerProfile` runtime object.

Initialization order:

1. `setup_native_stage()` registers all legacy classes and calls
   `item.PlayerInit()`.
2. `native_stage:init()` creates `New(reimu_player)` after the stage has reset
   the object pool and world transform.
3. `player_class:init()` creates the grazer and item bar, initializes movement,
   death, Bomb cooldown, power, support and collision fields, and assigns the
   global `player`/`lstg.player` references.
4. `reimu_player:init()` loads the Reimu sprite sheet, support sprites, shot
   sprites, Bomb masks, particle systems and animation frames, then sets
   `hspeed=4.5` and the four-support layout tables.

The original `item.PlayerInit()` sets `power=100`, `lifeleft=2`, `bomb=3`,
`graze=0`, score fields and item-bar state. The native bridge subsequently
overlays the project team-life/respawn model for co-op rooms. This is an
intentional boundary that must be unified in a later character system phase.

## Input and movement

The project input path is:

```text
LuaSTG input polling
  -> PlayerInput.new()
  -> Bootstrap:update()
  -> StageAdapter:update()
  -> TNRNativeLegacy.update()
  -> native_virtual_keys / player.key
  -> legacy KeyIsDown()
  -> reimu_player:frame()
```

`reimu_player:frame()` uses the original 8-direction keyboard controls. Normal
movement uses `hspeed=4.5`; holding the focus/slow key switches to inherited
`lspeed=2`. Diagonal movement is multiplied by `SQRT2_2`, and the original
world play bounds are applied every frame. The modern input provider also
supports mouse/menu input, but mouse movement is not used for the native player
flight controller.

## Weapons and supports

The original Reimu normal shot always fires two red straight bullets from
`x-10` and `x+10`, speed 24, angle 90, damage 2, with a four-frame fire
interval.

At power level 1-4, the original support system interpolates up to four Yin-Yang
supports using `slist`, `anglelist`, `supportx/supporty` and `lh` animation
state:

- High-speed mode: active supports periodically fire blue homing/aimed bullets
  using `reimu_bullet_blue`.
- Low-speed mode: active supports fire paired orange straight bullets using
  `reimu_bullet_orange`.
- Support count is driven by `int(lstg.var.power / 100)` and the support
  positions are eased toward the player each frame.
- Support sprites and their firing logic are part of the original Reimu class;
  there is no reusable project `SupportDefinition` yet.

## Bombs

The original input key is `spell`. When available and not blocked,
`player_class`/`player_system` calls `item.PlayerSpell()`, decrements
`lstg.var.bomb`, then calls `reimu_player:spell()`.

Reimu's two original Bomb forms are selected by the current slow state:

- High speed: `player_spell_mask` plus eight rotating `reimu_sp_ef` effects,
  300-frame cooldown/protection.
- Low speed: `player_spell_mask` plus `reimu_kekkai`, screen shake and a
  240-frame cooldown/protection.

Both forms use the imported original image, particle and sound resources. The
current co-op bridge treats a remote Bomb as a shared enemy-bullet clear, while
the local player still executes the complete original Bomb effect.

## Hit and death flow

Original collision sets `player.death=100` after protection expires and deletes
the colliding enemy bullet. The legacy player frame then runs the death phases
(90, 84, 50 and below), creates death effects, hides/repositions the player,
and eventually consumes a life through `item.PlayerMiss()`.

For co-op native rooms, `legacy_native_main.lua` intercepts the death timer:

- The local or remote player is hidden and assigned a 600-frame respawn timer.
- Enemy bullets are cleared when a player is hit or uses a Bomb.
- The team loses a life only when both player respawn states are active.
- A team wipe ends the encounter; otherwise the dead player returns with
  temporary protection.

Single-player native rooms retain the original death/life path. This split must
be represented explicitly in the future generic character controller instead
of remaining an adapter-level branch.

## State storage

There are currently two state layers:

### Legacy native state

`lstg.var` stores power, life, Bomb, graze, score, item bars and legacy flags.
The native Boss/player/card code reads and mutates these globals directly.

### Project state

`tnr/core/player_state.lua` stores per-player money, score, graze, life, Bomb
and `character_id`. It is used by map/encounter services and non-native runtime
paths. It is not a live mirror of every native `lstg.var` field.

The multiplayer transport currently exchanges player input and host snapshots
for native Boss HP/timer/frame/team state. It does not serialize the full legacy
player object, support objects, player bullets, or visual effect objects.

## Scene and resource transitions

`StageAdapter:start()` selects the native room type and calls
`TNRNativeLegacy.start_room()`. The native bridge changes to `TNRLegacyCard`,
resets the object pool/world, registers the player/background, and constructs
the original enemy wave or Boss card list. `StageAdapter:complete()` returns
the project session to the map or failure state.

Direct practice uses the same native stage but supplies a selected original
combat card plus its required preceding movement/setup entries. Resource helper
functions are registered once after `_editor_output.lua` is loaded so direct
practice does not skip original image/audio initialization.

## Reuse and required changes

### Can be wrapped directly

- Original Reimu shot, support interpolation, focus movement and both Bomb
  implementations.
- Original player death effects, grazer, item collection and collision rules.
- Original THlib resource registration and native Boss/card object lifecycle.
- Project `PlayerState` methods for score, money, life, Bomb and graze mutation.
- `TNRNativeLegacy` input, snapshot and co-op respawn hooks as integration
  boundaries.

### Must change for the generic character/loadout system

- Replace direct `if character == reimu` assumptions with data-driven
  `CharacterDefinition`/weapon/support/Bomb references.
- Define a single authoritative state model or explicit synchronization between
  `lstg.var` and `PlayerState`.
- Move weapon and support slot ownership out of `reimu_player` fields (`sp`,
  `support`, `slist`, `anglelist`) into loadout-owned objects.
- Give co-op players independent native-compatible player state without
  violating legacy scripts' global `player` targeting assumption.
- Define capacity/weight, inventory and relic ownership before exposing
  equipment changes on the map.

### Must remain unchanged during Phase 1

- Original card/enemy logic and imported visual/audio resource names.
- Original Reimu projectile parameters and Bomb behavior until a wrapper has
  equivalent coverage.
- Native room stage ordering and Boss object lifecycle.

## Risks

- Legacy scripts assume a singleton global `player`; creating a second full
  legacy player can corrupt target selection and card scripts.
- `lstg.var` values are global in the legacy engine, so naive per-player
  equipment or Bomb state will leak between co-op players.
- Some cards use legacy world fields and resource helpers that are not part of
  the modern project API; direct-card setup must preserve their preamble.
- Native visual effects and random branches are locally simulated. Co-op frame
  and random-seed synchronization is required for matching presentation.
- The current project `PlayerProfile` values duplicate some Reimu numbers and
  can drift from the original source if edited independently.

## Tests

- PASS: `lua54 assert(loadfile('game/scripts/legacy_native_main.lua'))`
- PASS: `lua54 tests/run.lua` (`TouHouNightReign core tests passed`)
- PASS: isolated native spell/non-spell launch audit covering 355 spell and
  321 non-spell catalog entries, including regression cases for missing helper
  images, world-center initialization and card setup preambles.
- NOT TESTED in this phase: new character/loadout behavior, because Phase 1 has
  not started.

## Proposed Phase 1 file tree

The next phase should add data-only character/loadout modules without touching
the native Reimu behavior:

```text
game/scripts/tnr/character/
  character_definition.lua
  character_registry.lua
  loadout.lua
  reimu_definition.lua
game/scripts/tnr/equipment/
  weapon_definition.lua
  support_definition.lua
  modifier_definition.lua
  relic_definition.lua
tests/
  character_loadout_spec.lua
```

Phase 0 is complete. Development stops here pending user verification.
