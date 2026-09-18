# State Authority

This document defines the ownership boundary for the native co-op bridge.

## Formal state

`tnr.core.player_state.PlayerState` owns per-player money, score, graze, bombs,
character/loadout/inventory/relics, alive state and respawn state.
`tnr.core.party_state.PartyState` owns `team_life`, `life_fragments` and the
current map node. Native `lstg.var` values are compatibility mirrors only.

## Native battle

Both processes run the original THlib stage and maintain a local player plus a
remote proxy. Local input, position, hit/graze and local bomb ownership are
local authorities. The host owns shared enemy/boss HP, alive/phase and battle
clear/fail decisions. Compact snapshots correct drift; they do not serialize
the bullet or particle pool.

## Bombs and drops

A bomb is a private resource decrement on the player who pressed it. The edge
event is broadcast with a room generation and sequence id; the peer reproduces
the shared clear/effect without decrementing its own bomb. Drops remain local
to each process and can only be collected by that process's player.

## Respawn

One player's death does not consume a team life. A simultaneous respawn pair
consumes exactly one team life and revives both players. With zero team lives,
the encounter fails only when both players are in the respawn state.

## Diagnostics

`NativeSyncAudit` samples every 30 native frames. A mismatch is reported as a
diagnostic (`KNOWN_VISUAL_DESYNC` or `ROOM_GENERATION_MISMATCH`) and does not
pretend to repair a missing resource or a gameplay rule.
