# Validation 2 Report

Date: 2026-08-30
Scope: modular player runtime, loadout commit, and LAN preparation gate.

## 1. Validation 1 Entry Gate

The existing `VALIDATION_1_REPORT.md` lists the 11 Native/LAN cases as NOT VERIFIED. No claim of native or two-window gameplay verification is made in this report. Pure Lua core regression remains passing.

## 2. Runtime Architecture

```text
PlayerState
  -> Loadout
  -> CharacterRuntimeBridge
  -> WeaponRuntimeManager / SupportRuntimeManager / ModifierRuntime
  -> native bridge descriptors
  -> Legacy THlib player and local projectile simulation
```

`StageAdapter` creates a runtime bridge for every encounter and sends the local and remote descriptors to `TNRNativeLegacy` after the native room and co-op proxy exist.

## 3. Weight

For Reimu (`base_high_speed=4.5`, `base_low_speed=2.0`, `capacity=100`):

| Weight | Class | High speed | Low speed |
| ---: | --- | ---: | ---: |
| 40 | ULTRALIGHT | 9.0 | 2.0 |
| 75 | NORMAL | 4.5 | 2.0 |
| 200 | OVERLOAD | 2.25 | 2.0 |

The policy is centralized in `tnr/character/runtime/weight_speed_policy.lua` and is used by the bridge descriptor.

## 4. Weapon Runtime

`WeaponRuntimeManager` activates every equipped weapon allowed by the current speed mode. Multiple active weapons fire in the same update. The catalog includes:

* `test_high_weapon`: two straight projectiles in HIGH mode.
* `test_low_weapon`: three spread projectiles in LOW mode.
* `test_dual_weapon`: distinct `dual_high` and `dual_low` forms.

Modifier hooks can add volley shots and projectile scale without changing the definition objects.

## 5. Support Runtime

Support entity counts come from SupportDefinition. Reimu Yin-Yang support is four entities. `SupportRuntimeManager` sums multiple support slots and never reads `lstg.var.power`.

## 6. Modifier Runtime

Implemented pure runtime hooks include:

* Self: `projectile_scale`, `volley`.
* Support: `front_concentration`, `periodic_bullet_clear`.

The hook pipeline covers weapon fire, projectile creation, support formation/update, and leaves bomb hooks available for the native adapter.

## 7. LAN Loadout Commit

`LOADOUT_COMMIT` is now a session command. A descriptor contains player/character identity, capacity, weight, speed policy, slot descriptors, modifier descriptors, version, and content hash. The network encounter barrier will not schedule `START_ENCOUNTER_AT` until both players have committed.

The hash excludes process-local equipment instance IDs, so equivalent loadouts on separate processes hash identically while different definitions or slot layouts do not.

## 8. Automated Tests

Command:

```powershell
& 'E:\gemesmods\stg\LuaSTG-Sub-master\tool\luajit\luajit.exe' tests\run.lua
```

Result: `TouHouNightReign core tests passed`.

Added coverage:

* `tests/weight_runtime_spec.lua`
* `tests/weapon_runtime_spec.lua`
* `tests/support_runtime_spec.lua`
* `tests/modifier_runtime_spec.lua`
* `tests/loadout_commit_spec.lua`

## 9. Native/LAN Status

Native GUI, two-process LAN, Boss HP convergence, and performance stress cases remain NOT TESTED in this environment. The report intentionally does not mark them PASS without a real LuaSTG window run.

## 10. Regression

Pure Lua map, encounter, preparation, ready, authority, aggro, and native protocol tests pass. Existing native Bomb, death, respawn, Team Life, and Legacy card behavior were left on the original adapter path; descriptor application is additive.

## 11. Remaining Blockers

Before declaring Validation 2 complete, run the 11 Validation 1 native/LAN cases, then the 10 LAN loadout cases from `调试任务书2`, using two LuaSTG processes with LuaSocket enabled. Any mismatch in Bomb, respawn, enemy authority, or room generation must be fixed before proceeding to task book 3.

## 12. Debug Commands

The debug console now accepts:

```text
runtime_loadout
runtime_weapon
runtime_support
runtime_modifiers
weight_debug
loadout_hash
```

