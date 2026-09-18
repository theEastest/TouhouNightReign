# Phase 1 Report: Character / Loadout Data Skeleton

Date: 2026-08-30

## 1. Completed

Implemented the Phase 1 pure-data layer without taking over the native Reimu
runtime:

- `CharacterDefinition` with dynamic weapon, support, modifier and inventory
  slot counts.
- Immutable `ReimuDefinition` (`high=3`, `low=3`, `support=1`, self modifiers
  `=2`, support modifiers `=2`, inventory `=6`).
- `CharacterRegistry` for registered character definitions.
- `PlayerLoadout` with dynamic arrays and `get_total_weight()`.
- `EquipmentDefinition` and immutable specialized definitions for weapons,
  supports and modifiers.
- `EquipmentInstance` with unique instance IDs, owner, runtime data and
  reserved random affixes.
- `EquipmentRegistry` and a small Phase 1 definition catalog.
- `Inventory` with explicit `INVENTORY_FULL` failure and no silent overwrite.
- `RelicDefinition`, kept outside equipment slots and inventory.
- `ModifierDefinition.is_conflicting()` for pure conflict-group checks.
- `PlayerState` fields for loadout, capacity, respawn and map readiness, plus
  pure-Lua serialization helpers. The legacy `life` field remains marked as
  compatibility data.
- `PartyState.team_life`, `life_fragments`, fragment conversion and readiness
  checks, plus serialization helpers.
- Debug summaries for loadout slot occupancy and inventory occupancy.

## 2. New Files

```text
game/scripts/tnr/core/immutable.lua
game/scripts/tnr/character/character_definition.lua
game/scripts/tnr/character/character_registry.lua
game/scripts/tnr/character/reimu_definition.lua
game/scripts/tnr/character/loadout.lua
game/scripts/tnr/equipment/equipment_definition.lua
game/scripts/tnr/equipment/equipment_instance.lua
game/scripts/tnr/equipment/equipment_registry.lua
game/scripts/tnr/equipment/weapon_definition.lua
game/scripts/tnr/equipment/support_definition.lua
game/scripts/tnr/equipment/modifier_definition.lua
game/scripts/tnr/equipment/relic_definition.lua
game/scripts/tnr/equipment/inventory.lua
game/scripts/tnr/equipment/phase1_catalog.lua
tests/character_loadout_spec.lua
PHASE_1_REPORT.md
```

## 3. Modified Files

```text
game/scripts/tnr/core/player_state.lua
game/scripts/tnr/core/party_state.lua
game/scripts/tnr/init.lua
tests/run.lua
```

The state changes add only serializable Phase 1 fields and methods. The test
runner now loads `tests/character_loadout_spec.lua`. No native THlib player,
Bomb, projectile, enemy, stage or multiplayer bridge file was changed for this
phase.

## 4. Data Relationships

```text
PartyState
├─ player_ids[]
├─ current_node_id
├─ team_life
└─ life_fragments

PlayerState (one per player)
├─ character_id -> CharacterDefinition.character_id
├─ money / score / graze / bomb
├─ base_capacity / current_capacity / capacity_level
├─ map_ready / respawning / respawn_timer
└─ loadout -> PlayerLoadout
   ├─ high_weapons[] / low_weapons[]
   ├─ supports[]
   ├─ self_modifiers[] / support_modifiers[]
   ├─ inventory -> Inventory
   └─ relics[] / character_relic

PlayerLoadout slot entries -> EquipmentInstance
EquipmentInstance.definition_id -> EquipmentDefinition
EquipmentDefinition specializations:
  WeaponDefinition / SupportDefinition / ModifierDefinition
RelicDefinition is separate and never enters Inventory.
```

## 5. Tests

All of the following are covered by `tests/character_loadout_spec.lua`:

```text
PASS  ReimuDefinition slot counts
PASS  Dynamic PlayerLoadout slot creation
PASS  Unique EquipmentInstance IDs
PASS  Duplicate definition instances allowed
PASS  Inventory capacity and INVENTORY_FULL result
PASS  Weight includes weapons/supports only
PASS  Modifier conflict groups
PASS  Party life-fragment conversion (3 -> 1 team life)
PASS  PlayerState uses PartyState for the formal team-life boundary
PASS  Two-player map readiness
PASS  Player/Party/Loadout/Inventory serialization round trip
PASS  Definition immutability
```

Commands run:

```text
..\LuaSTG-Sub-master\tool\lua\lua54.exe tests\run.lua
  -> TouHouNightReign core tests passed

Explicit loadfile syntax checks for all new character/equipment/core modules
  -> passed
```

## 6. Legacy Regression

```text
Reimu runtime untouched: YES
Legacy Power behavior untouched: YES
Native Bomb/death/stage bridge untouched: YES
Existing deterministic/native regression suite: PASS
```

The new `PlayerState` defaults create empty data-only loadouts and inventories;
they do not route native projectiles or supports through the new definitions.

## 7. Known Limitations

These are intentionally deferred by the Phase 1 task book:

- No equipment UI, drag/drop or inventory overflow UI.
- No runtime weapon firing or Support spawning from definitions.
- No Modifier hooks, relic events, status effects, weight-speed behavior,
  score-capacity progression or Bomb componentization.
- `PlayerState.life` remains as legacy compatibility data; formal shared life
  is `PartyState.team_life`.
- Loadout serialization stores plain Lua instance-shaped tables. A later battle
  adapter will rehydrate them into runtime objects when Phase 4/6 begins.

## 8. Git

The worktree already contained earlier project changes and untracked imported
assets. No unrelated changes were reverted and no new commit was created in
this phase. Base repository HEAD at inspection: `c85a88d`.

## 9. User Verification

Please verify the following before authorizing Phase 2:

1. The test command prints `TouHouNightReign core tests passed`.
2. Reimu's native single-player, practice and co-op rooms still use the
   original THlib player and projectile path.
3. The data-only debug summary reports the configured dynamic slot counts.
4. No UI or in-battle equipment behavior is expected yet.

Per the task book, development stops here until Phase 1 is explicitly approved.
