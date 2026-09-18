# Debug Task 3 Validation Report

Date: 2026-08-30
Baseline HEAD: `edb8ecc` (working tree contains the imported Legacy/runtime files)

## Implemented in this pass

- Gate 0 protocol hardening: generation-bearing commands, inputs, snapshots and
  events are rejected when stale or when no matching room is active.
- LAN disconnect callback and Bootstrap cleanup: a peer disconnect stops the
  active room, clears the native runtime and returns to MENU with an error.
- Boss clear invalidates `current_encounter` and `room_generation` before the
  terminal transition.
- Score-to-Capacity progression is a data-driven service with immediate player
  state updates.
- Enemy clear reward path creates an `EquipmentInstance` and routes it through
  `AcquisitionService`; full inventory remains Pending Acquisition.
- Deterministic three-slot per-player Shop with private Money, Equipment,
  Bomb, and shared Life Fragment handling.
- Permanent RelicRuntime with Reimu no-hit fragment hook, ordinary relics,
  character relic replacement, and independent Boss relic choices.
- Functional keyboard and mouse-facing Shop/Relic selection states.

## Automated result

Command:

```powershell
& 'E:\gemesmods\stg\LuaSTG-Sub-master\tool\luajit\luajit.exe' tests\run.lua
```

Result: `TouHouNightReign core tests passed`.

Covered by the current suite:

- Gate 0 stale room command rejection and one-shot disconnect callback.
- Terminal Boss clear room cleanup.
- Enemy reward to Inventory without auto-equip.
- Capacity threshold progression without consuming Score.
- Deterministic Shop offers and private purchase state.
- Reimu Relic no-hit/hit behavior and permanent Relic selection.
- Minimal Enemy → Shop → Boss → Relic → Run Clear lifecycle.

## Native/LAN gate status

The required 11 Validation 1 cases and 10 Validation 2 cases still require a
real LuaSTG executable and two independent windows. They are not claimed as
PASS by this report. Until those runs are executed, the task-book Gate 0
remains **PENDING MANUAL EXECUTION** and the final Run cannot be certified.

Manual evidence must record at least: input/shoot/Bomb, same-room start,
private Bomb and Money, enemy/Boss HP convergence, respawn/team-life behavior,
stale packet rejection, loadout runtime rebuild, and disconnect cleanup.
