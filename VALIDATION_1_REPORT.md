# Validation 1 Report

Date: 2026-08-30

## Scope

This stage stabilizes the existing native THlib/LAN path. Weapon Runtime,
Support Runtime, modifiers, shop/event content and broad Legacy refactors remain
out of scope.

## Git and runtime baseline

- Baseline HEAD: `c85a88d fix: align menu and map UI text`
- Working tree was already mixed (tracked code changes plus imported Legacy
  assets); see `BASELINE_MANIFEST.md`.
- LuaSTG executable: `LuaSTG-Sub-master/build/amd64/bin/LuaSTGSub.exe`
- CMake: `3.31.12`

## Representative native rooms

The representative selector is `tests/native_validation_catalog.lua`:

- `ROOM_A`: first `legacy_exact` ordinary enemy wave longer than 10 seconds.
- `ROOM_B`: first `legacy_exact` boss non-spell card.
- `ROOM_C`: first `legacy_exact` boss spell card.

The selector does not substitute TNR fallback content.

## Implemented

- `LegacyStateAdapter` formalizes PlayerState/PartyState ownership and limits
  native values to compatibility mirrors.
- Native bridge attaches PartyState and local PlayerState; team life and local
  Bomb ownership are copied through that boundary.
- Encounter packets include and validate node, encounter, content seed and
  deterministic room generation.
- LAN input/snapshot/peer-snapshot/event packets carry room generation and stale
  generations are dropped.
- `NativeSyncAudit` samples every 30 frames, records a signature and reports
  `ROOM_GENERATION_MISMATCH` or `KNOWN_VISUAL_DESYNC` without hiding errors.
- `net_status` debug command exposes transport stale-packet count and audit
  status.

## Resource preflight

`tnr.stages.native_resource_preflight` checks the Legacy root, asset root,
native bridge entry and content catalog before representative-room validation.
Shader compilation remains visual-only fallback behavior; missing gameplay
images/effects are not silently replaced by synthetic content.

## Automated checks

- `tests/state_authority_spec.lua`: passed with the bundled LuaJIT.
- `tests/native_sync_protocol_spec.lua`: passed with the bundled LuaJIT.
- Full `tests/run.lua`: passed (`TouHouNightReign core tests passed`).
- All edited Lua files pass `loadfile` syntax validation.
- A small compatibility fix in `WeaponDefinition` makes immutable definitions
  copy correctly under LuaJIT 5.1; this removes the test-runner blocker without
  changing gameplay behavior.

## Native/LAN cases to execute in the game

1. Single-player ROOM_A movement, shoot, Bomb and clear.
2. Single-player ROOM_B non-spell and ROOM_C spell entry.
3. Host/client same seed and same node start barrier.
4. Both players move/shoot/focus independently.
5. Each player uses one Bomb; peer shows effect once and does not lose a Bomb.
6. One player dies and respawns without team-life loss.
7. Simultaneous respawn consumes exactly one team life and revives both.
8. Zero team lives plus simultaneous respawn enters failure.
9. Enemy/boss HP and clear state converge after snapshot correction.
10. Previous-room packets are rejected after a new room starts.
11. `net_status` reports stale packets and first sync mismatch.

Native windowed and two-process LAN execution still requires the locally built
LuaSTG executable. The gate remains pending manual execution; it is not
claimed as headless CI coverage. See `TECHNICAL_ROUTE_VALIDATION_FINAL.md`.
