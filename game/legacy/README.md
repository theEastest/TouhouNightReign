# Legacy Resource Bundle

This directory contains the reusable material curated from the local
TouHouDoujinshi project. It is intentionally isolated from the active game
runtime so legacy global names cannot overwrite TouHouNightReign state.

## Layout

- `source/data/` - extracted THlib and engine-side Lua source files, including
  bullet, laser, enemy, boss, spell-card, task and background modules.
- `source/activity7/` - generated stage logic and Karl helper modules used by
  the original activity. The generated `_editor_output.lua` is kept as
  reference material; it is not loaded automatically.
- `assets/data/` - reusable THlib images, effects and background resources.
- `assets/activity7/` - activity sprites, spell-card art, backgrounds and
  effect resources.

The active adapter uses English IDs declared in
`game/scripts/tnr/stages/content_catalog.lua` and
`game/scripts/tnr/stages/stage_specs.lua`. Display names remain Chinese UI
text. New code should add a catalog entry instead of requiring files from this
directory directly.

## Imported runtime content

- Ordinary-stage enemies: the curated `legacy_small_fairy`,
  `legacy_red_seed`, `legacy_butterfly`, plus all 18 standard THlib
  `enemy.lua` styles exposed as `legacy_enemy_style_01` through
  `legacy_enemy_style_18`.
- Ordinary-stage card: `preparation_danmaku_ritual`.
- Boss cards: `reimu_nonspell`, `spirit_seal`, `yin_yang_jewel`,
  `four_direction_formation`.
- The editor export is parsed at startup. It currently contributes 381
  additional card records (including unnamed nonspells), preserving boss ID,
  source line, HP, timeout and the original time-spell flag.
- The complete catalog currently exposes 741 cards (418 spells and 323
  nonspells) to the spell-card and nonspell training menus.
- Pattern families available in the fallback runtime: aimed, fan,
  aimed-fan, spiral, ritual, seal, wind, cross, laser, radial, orbit, curtain,
  rain, burst, vortex, windmill, light-seal, barrier, starburst and formation.
  Each catalog card is assigned a deterministic family and a matching THlib
  bullet sprite.
- Imported card visuals now select activity arena layers, animated Boss frame
  sets, spell aura effects and the original Boss HP-bar texture. The visual
  aliases are loaded in `game/scripts/main.lua` and are replaceable there.

The regular menu continues to use the deterministic project-owned adapter for
network-safe map runs. For exact reference behavior, set
`TNR_NATIVE_LEGACY=1`; `game/scripts/legacy_native_main.lua` loads the copied
THlib object model and `_editor_output.lua`, then runs a selected original boss
card using `TNR_LEGACY_BOSS` and `TNR_LEGACY_CARD_INDEX`. This native path keeps
the generated task, bullet, background and boss-state logic intact while using
fallbacks only for optional resources absent from the local export.
