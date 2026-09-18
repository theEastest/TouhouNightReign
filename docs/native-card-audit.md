# Native Card Audit

The runtime now loads `game/legacy/source/activity7/_editor_output.lua` and
resolves cards by the original Boss class and card-list slot. Slot numbering
includes `boss.move.New(...)` entries because that is how the reference Boss
object consumes its list.

Current audit (2026-08-28):

- 355 spell and 321 non-spell entries are exposed by the two practice
  catalogs (676 total).
- Static validation found an original Boss class, numeric source slot,
  `legacy_exact=true`, and a combat initializer for every entry.
- Each entry was launched in an isolated runtime process. The initial batch
  run found five genuine runtime defects: two missing `wuer_yamame` helper
  images, two `akuma` cards requiring the legacy world-center aliases, and
  one card requiring a preceding setup/dialogue entry. All five were fixed by
  restoring the original resource registration and setup sequence, then
  re-tested successfully. The remaining batch-only `_editor_class=nil` and
  stage-reset reports were not reproducible in isolated launches.
- Direct launches also confirmed the original movement segments place the
  Boss inside the playfield; the off-screen starting coordinates are the
  reference entrance animation, not a catalog position error.

Room routing is native by default:

- Ordinary: original activity small-enemy classes plus Reimu's first non-spell.
- Elite: a deterministic `:Normal` Boss class with fewer than three cards.
- Boss: a deterministic main Boss class with its complete original card list.

The audit intentionally does not label a card native based on its display name
alone; it must have both `legacy_boss` and `legacy_card_slot` metadata.
Direct training also validates that the resolved source entry is a combat card
with an `init` function before changing stages, preventing silent empty rooms.
