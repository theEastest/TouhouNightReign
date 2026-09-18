# Legacy enemy wave catalog

`game/scripts/tnr/stages/legacy_enemy_waves.lua` is generated from the
original `activity7/_editor_output.lua` stage functions.

The catalog is grouped at the stage level rather than split at every `Wait`
call:

- A stage with a mid-boss has two entries: `Before Mid-Boss` and `After Mid-Boss`.
- A stage without a mid-boss has one `Complete Enemy Run` entry.
- The current extraction contains 32 source stages, 52 grouped waves, and
  1172 original enemy constructor records. No stage has more than two waves.
- `members` preserves the original `New(_editor_class[...])` class, argument
  expressions, environment values, and source order.
- `spawn_frame` is the original relative frame at which that constructor is
  reached. The native bridge schedules the constructor at that frame, so
  practice does not collapse all formations into frame zero.
- `duration_frames` and `duration_seconds` cover the grouped section. They are
  selector metadata; runtime behavior still comes from the original stage code
  and parameters.
- Normal entries use difficulty levels 1-3; Lunatic entries use 4-6. A
  one-segment stage uses the middle level of its range.

Roguelike enemy rooms select one grouped Normal wave using the room seed and
then enter the original nonspell phase. Enemy practice lists every grouped
wave, including its source stage, segment label, duration, and difficulty.

To regenerate after replacing the reference extraction, run from the workspace
root:

```powershell
& .\TouHouNightReign\tools\generate_legacy_enemy_wave_catalog.ps1
```

The generator defaults to `_reference_extract_20260827\activity7\_editor_output.lua`;
`-Source` and `-Output` can be used to override those paths.
