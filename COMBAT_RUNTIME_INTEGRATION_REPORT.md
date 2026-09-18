# Combat Runtime Integration Report

Date: 2026-08-31

## Scope

This pass connects the modular `PlayerLoadout` runtime to both the fallback
battle adapter and the native THlib player path. The implementation keeps the
legacy projectile classes for collision, rendering, and lifecycle, while the
runtime owns weapon/support selection, cadence, damage, and modifiers.

## Before / After

Before:

```text
Shoot -> reimu_player.shoot() -> fixed Reimu volley
```

After:

```text
Shoot -> CharacterRuntimeBridge
      -> WeaponRuntime / SupportRuntime
      -> ProjectileDescriptor / ProjectileFactory
      -> native legacy projectile class or fallback projectile state
```

In a formal TNR room `reimu_player.shoot` is bypassed. The wrapper remains
available for legacy training/reference paths. Native debug state exposes
`legacy_shot_calls` and `runtime_shot_calls`.

## Implemented

- `ProjectileFactory` normalizes the shared descriptor fields: owner, source
  instance, projectile type, position, angle, speed, damage, scale,
  penetration, targeting, and metadata.
- `WeaponRuntime` reads definition speed/count/pattern aliases, maintains an
  independent cooldown, supports High/Low activation and dual-mode weapons.
- `SupportRuntime` emits runtime-owned support projectiles with independent
  cadence and High/Low weapon definitions; support count is not derived from
  `lstg.var.power`.
- Formation, projectile-scale, volley, and periodic-clear modifier hooks now
  affect the actual fallback/native creation path.
- Remote committed descriptors can rebuild a runtime without using the local
  player's equipment instances.
- Empty weapons produce no main shots; empty supports produce zero entities.
- Runtime maps and native drivers are cleared on room reset.
- Native support count explicitly accepts zero, preventing the old forced-four
  fallback.

## Automated results

Command:

```powershell
& 'E:\gemesmods\stg\LuaSTG-Sub-master\tool\luajit\luajit.exe' tests\run.lua
```

Result: `TouHouNightReign core tests passed`.

The new integration spec covers empty loadouts, equipped weapon/support
descriptors, independent cooldown behavior, volley modifiers, remote descriptor
reconstruction, fallback output, and runtime destruction on room exit.

Native script syntax was checked with LuaJIT `loadfile`. A real LuaSTG process
was launched for a resource/startup smoke test; initialization completed
without a new Lua runtime error in `engine.log`.

## Native/LAN gate status

The full native combat and two-process LAN matrix has not been certified in
this pass. In particular, the following still require manual execution with
two independent LuaSTG windows:

- empty native loadout has zero player/support projectiles;
- each configured weapon and support emits its own descriptor and damage;
- native `legacy_shot_calls == 0` while `runtime_shot_calls` increases;
- native projectile scale, volley, formation, and periodic clear are visible;
- two peers consume different committed builds and converge on Boss HP;
- Bomb, death/respawn, map transition, and disconnect regression behavior.

Therefore the overall task status is:

```text
MODULAR COMBAT RUNTIME: FAIL (native/LAN acceptance pending)
```

The implementation is ready for the manual matrix; the report intentionally
does not claim PASS without observing the native runtime and LAN behavior.
