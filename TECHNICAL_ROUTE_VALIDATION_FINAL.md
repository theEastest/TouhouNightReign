# TouHouNightReign Technical Route Validation Final

Date: 2026-08-30  
Validation seed: `20260830` (`Constants.validation_run_seed`)  
Baseline HEAD: `edb8ecc` (`feat: integrate modular player runtime loadouts`)

## Scope

This report covers Debug Task 3: the minimum two-player LAN Roguelike run
vertical slice. It separates code-level and pure-Lua evidence from native
LuaSTG window evidence. Native gameplay is not inferred from unit tests.

## Validation 1

| Area | Result | Evidence |
|---|---|---|
| Generation-bearing packet rejection | PASS | `tests/native_sync_protocol_spec.lua` |
| One-shot disconnect callback | PASS | `tests/native_sync_protocol_spec.lua` |
| Room generation cleanup after Boss clear | PASS | `tests/gate0_validation_spec.lua` |
| Single-player native movement/shoot/Bomb/clear | FAIL: native gate pending | Requires LuaSTG window |
| Native Host/Client same-room start and HP convergence | FAIL: native gate pending | Requires two processes |
| Native respawn/team-life/Bomb behavior | FAIL: native gate pending | Requires two processes |

The native cases cannot be certified from the available headless execution
environment. No native case is claimed as a pass without a real window run.

## Validation 2

| Area | Result | Evidence |
|---|---|---|
| Loadout descriptor/runtime data path | PASS | Existing loadout/runtime specs |
| Different weapon/support/modifier/weight data | PASS | Existing runtime specs |
| Native two-player runtime rebuild | FAIL: native gate pending | Requires two processes |
| Native Boss HP/Bomb/death/respawn convergence | FAIL: native gate pending | Requires two processes |

## Full Run Vertical Slice

| Step | Result | Evidence |
|---|---|---|
| New Run and deterministic map | PASS | `run_lifecycle_spec.lua`, seed `20260830` |
| Enemy node and room generation | PASS | `GameSession:select_node` |
| Enemy clear reward | PASS | `reward_runtime_spec.lua` |
| EquipmentInstance to Inventory | PASS | `EquipmentRewardService` + AcquisitionService |
| Inventory overflow pending/reject path | PASS | AcquisitionService contract |
| Score to Capacity progression | PASS | `capacity_progression_spec.lua` |
| Shop with three deterministic slots | PASS | `shop_spec.lua` |
| Private Shop Money/equipment/Bomb | PASS | `shop_spec.lua` |
| Shared Life Fragment purchase | PASS | ShopService party path |
| Boss clear and room invalidation | PASS | `gate0_validation_spec.lua` |
| Independent Boss Relic choices | PASS | `relic_runtime_spec.lua` |
| Run Clear only after relic choice | PASS | `gate0_validation_spec.lua` |
| Cross-room native runtime cleanup | PASS: code path | Bootstrap and StageAdapter cleanup hooks |
| Full two-process native run | FAIL: native gate pending | Requires manual execution |

## Player State Contract

`PlayerState` keeps `Money`, `Score`, `Capacity`, `Bomb`, `Loadout`,
`Inventory`, and `Relics` private to each player. `PartyState` keeps Team Life
and Life Fragments shared. Stage snapshots no longer overwrite private Money,
Score, Bomb, or loadout fields.

The Boss relic pool contains three choices, including
`reimu_initial_relic_plus`; choosing it replaces the character relic. Ordinary
relics are appended to the permanent relic list and do not consume weight or
inventory slots. Reimu's no-hit battle hook grants one shared Life Fragment.

## Network / Room Safety

- Commands, inputs, snapshots, peer snapshots, and events carry
  `room_generation` once a room is active.
- Stale generations are dropped before dispatch.
- Disconnect invokes the callback once, stops the run, resets native state,
  clears the active room generation, and returns to the menu with an error.
- Boss clear invalidates the current encounter before any later transition.
- `RUN_CLEARED` is emitted only after all party members complete relic choice.

## Automated Verification

Command:

```powershell
& 'E:\gemesmods\stg\LuaSTG-Sub-master\tool\luajit\luajit.exe' tests\run.lua
```

Result: `TouHouNightReign core tests passed`.

## Native/LAN Manual Gate

Run two independent executables from the project game directory. Use
`validation_run` from the debug console to start the fixed seed, then execute
the 11 Validation 1 and 10 Validation 2 cases. Record `net_status`, room
generation, Boss HP, Team Life, Bomb edge count, and disconnect behavior.

The current report deliberately leaves this gate as **FAIL: native gate
pending** until those observations are supplied. This is the only blocker to a
technical-route PASS.

## Known Issues

- CRITICAL: native two-window gate has not been executed in this environment.
- HIGH: Legacy resource/shader logs still contain historical missing-asset
  entries; they require native resource preflight during manual validation.
- VISUAL: Shop and Relic screens are functional validation UI, not final art.

## Git Snapshot

- HEAD: `edb8ecc`
- Worktree: intentionally contains the imported Legacy/runtime assets and
  validation reports; unrelated pre-existing changes were preserved.
- New/changed vertical-slice systems: `game/scripts/tnr/shop/`,
  `game/scripts/tnr/relic/`, `game/scripts/tnr/reward/`, capacity progression,
  Bootstrap state transitions, and protocol cleanup.

## Final Technical Route Decision

**TECHNICAL ROUTE: FAIL (native/LAN gate pending)**

The pure-Lua vertical slice is complete and passing. The route becomes PASS
only after the required native single-player and two-process LAN runs pass on
the built LuaSTG executable.
