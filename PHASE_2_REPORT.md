# Phase 2 Report: Map Preparation / Inventory / Loadout / Ready

Date: 2026-08-30

## 1. Completed

Phase 2 turns the Phase 1 data model into a usable map-preparation flow:

- Added `MAP_PREPARATION` as an explicit run state.
- Added serializable `PreparationState` with selected node, per-player Ready
  and lock state, and pending acquisition state.
- Added `LoadoutService` for all equipment edits. UI code does not mutate slot
  or inventory arrays directly.
- Added `AcquisitionService`. New equipment always enters Inventory first;
  overflow is retained as `pending_acquisition` and blocks Ready until accepted
  or rejected.
- Implemented legal slot validation for High/Low weapons, Support, Self
  Modifier and Support Modifier.
- Implemented empty-slot equip, occupied-slot atomic swap, unequip with
  `INVENTORY_FULL`, compact inventory move/swap, and discard.
- Implemented single modifier conflict replacement. Multiple conflicts return
  `MULTIPLE_CONFLICTS` without mutating state.
- Initial Reimu High Weapon, Low Weapon and Support are real
  `EquipmentInstance` values in the loadout. The character relic remains a
  fixed read-only relic id.
- Added a menu-style preparation screen with capacity, total weight, equipped
  groups, inventory, item details, definition id, instance id and legal slots.
- Added two-stage Backspace discard confirmation in the preparation UI.
- Added debug commands: `give_equipment`, `inventory`, `loadout`, `discard`,
  `ready`, and `unready`.
- Added the required catalog coverage: 3 weapons, 2 supports, 2 self
  modifiers and 2 support modifiers. The two modifier pairs share conflict
  groups for replacement tests.

## 2. Files

New Phase 2 files:

```text
game/scripts/tnr/preparation/preparation_state.lua
game/scripts/tnr/equipment/loadout_service.lua
game/scripts/tnr/equipment/acquisition_service.lua
tests/loadout_operations_spec.lua
PHASE_2_REPORT.md
```

Phase 2 integration changes:

```text
game/scripts/tnr/core/constants.lua
game/scripts/tnr/core/command.lua
game/scripts/tnr/core/event.lua
game/scripts/tnr/core/game_session.lua
game/scripts/tnr/bootstrap.lua
game/scripts/tnr/ui/map_renderer.lua
game/scripts/tnr/debug/console.lua
game/scripts/tnr/debug/debug_command.lua
game/scripts/tnr/init.lua
game/scripts/main.lua
tests/run.lua
```

Phase 1 equipment definitions were extended with the test catalog entries and
`EquipmentInstance` now preserves its equipment type during serialization.

## 3. State and command flow

```text
MAP
  -> SELECT_NODE / VOTE_NODE
  -> MAP_PREPARATION
  -> EQUIP_ITEM / UNEQUIP_ITEM / MOVE_INVENTORY_ITEM / DISCARD_ITEM
  -> ACQUIRE_ITEM -> pending overflow resolution when full
  -> SET_READY / CANCEL_READY
  -> validate every player's final loadout
  -> ENCOUNTER
```

For the local single-player runtime, selecting an adjacent combat node opens
preparation and pressing Ready commits immediately. Multiplayer native rooms
keep their existing network protocol in this phase; no new network messages
were introduced by the task book.

## 4. Automated tests

Command:

```text
..\LuaSTG-Sub-master\tool\lua\lua54.exe tests\run.lua
```

Result:

```text
TouHouNightReign core tests passed
```

`tests/loadout_operations_spec.lua` covers empty equip, occupied swap,
unequip, full inventory, inventory move/swap, discard, acquisition overflow,
accept/reject pending, slot legality, relic rejection, modifier replacement,
multiple-conflict validation, Ready locking, Cancel Ready, single-player
preparation commit, two-player readiness, and catalog coverage.

The existing regression suite is loaded by the same command and remains green.

## 5. Manual verification

1. Start the normal local game and select an adjacent map node.
2. Confirm the preparation screen opens before the encounter.
3. Use `give_equipment test_dual_weapon` in the debug console; verify the item
   appears in Inventory rather than auto-equipping.
4. Select the inventory item and confirm it moves into a legal weapon slot.
5. Select the occupied slot with another legal weapon and verify the old item
   returns to Inventory atomically.
6. Fill Inventory, try to unequip, and verify `INVENTORY_FULL` is reported.
7. Press Backspace once on an inventory item and verify only a confirmation is
   shown; press it again to discard.
8. With an unresolved overflow item, verify Ready is rejected. Accept or
   reject it, then Ready and enter the selected node.
9. In a two-player data-session test, Ready P1 only and verify the node does
   not start until P2 is Ready.

## 6. Legacy compatibility

Phase 2 does not modify native Reimu firing, Support spawning, Bomb behavior,
enemy/boss logic, THlib projectile code, death/respawn logic or the existing
LAN transport protocol. The loadout and equipment data remain an explicit
pre-battle boundary and are not yet consumed by the native battle runtime.

## 7. Git status

The repository contains a large pre-existing dirty tree with imported assets,
legacy scripts and earlier phase changes. The Phase 1 report recorded base HEAD
`c85a88d`. Because the Phase 2 integration files overlap files already modified
by earlier work, creating a focused commit without accidentally including
unrelated changes is not safe in this workspace. No unrelated changes were
reverted; the intended Phase 2 file set is listed above for review/staging.

## 8. Known limitations

- The preparation UI is intentionally menu-based and does not implement drag
  and drop.
- Inventory move/equip target selection is exposed through services and debug
  commands; the first UI pass chooses the first legal slot automatically.
- Pending-overflow accept/reject is implemented in the service and command
  layer; a dedicated overflow modal can be added in a later UI pass.
- Native battle behavior still uses its existing Reimu runtime by design.

Per the task book, development stops at Phase 2.
