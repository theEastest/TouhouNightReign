# Legacy resource bundle

The files here are curated from the local TouHouDoujinshi reference project.
Native battles load `source/activity7/_editor_output.lua` through
`game/scripts/legacy_native_main.lua`; these files are active dependencies.

- `source/data/`: reference THlib/engine Lua, also used by comparison tests.
- `source/activity7/`: original cards, backgrounds and helper modules, with
  narrowly scoped compatibility fixes documented in `docs/native-card-audit.md`.
- `assets/data/` and `assets/activity7/`: original images, sound and effects.

The active compatibility library is `game/scripts/LegacyTHlib`. Its bullet
atlas registrations are checked against the reference source, including
collision shapes and animated frames. Old D3D9 effects are ported in
`game/scripts/shader/` for the current D3D11 engine.

The native practice catalogs contain 355 spells and 312 nonspells (nine retirement-only entries are excluded). Slots count
movement and dialogue entries as well as combat entries. Direct practice must
supply any campaign setup state used by the selected card.

The separate `tnr/legacy_replay` runtime is the TH15 reconstruction and should
not be confused with the activity7 native battle path. See the validation
reports for the scope actually tested; loading a card alone is not proof that
its later phases or defeat callbacks are correct.
