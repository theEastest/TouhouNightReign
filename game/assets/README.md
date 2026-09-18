# Imported Runtime Assets

The project now has active runtime asset directories in addition to the full
legacy archive under `game/legacy/assets`.

- `texture/white.png` - procedural UI and fallback primitive texture.
- `players/reimu/` - Reimu sprite/effect files and replacement slots.
- `backgrounds/night_road/` - imported Gensokyo night-road background layer.
- `bosses/reimu/` and `bosses/sanae/` - imported Boss portrait sprites.
- `bosses/spellcard/` - imported Sanae spell-card background layers.
- `audio/se/` - imported THlib WAV sound effects, including firing, Bomb,
  damage, card and player-death sounds.
- `audio/music/` - imported menu and spell-card OGG tracks.

The music files in `audio/music/` are the original files extracted from
`E:\galgames\TouHouDoujinshi\mod\activity7.zip` (using the supplied archive
password), including the 50 files registered by the exported reference Lua
scripts. `legacy_native_main.lua` resolves legacy music paths by exact basename
and never substitutes `menu.ogg` for a missing BGM. A missing original music
file is reported as an error so it can be restored instead of masking the
problem with a compatibility track.

`game/scripts/tnr/audio/audio_manager.lua` loads the selected sound and music
resources when LuaSTG is available. Headless tests run without an audio device
and safely skip loading.

## Original resource index

The complete preserved reference assets remain under `game/legacy/assets/` so
the original Lua scripts can load them without path rewriting. For project code
and tools, use:

- `game/assets/reference/legacy_resources.json` for a searchable JSON index;
- `game/scripts/tnr/stages/legacy_resources.lua` for the runtime Lua index.

The index currently covers 1,450 original files and records a stable logical
ID, category, project-relative path, byte size, and SHA-256 hash. Categories are
`background`, `character`, `bullet`, `effect`, `sound`, `music`, `font`,
`texture`, `script`, and `other`.

Regenerate both indexes after replacing reference files with:

```powershell
& .\tools\generate_legacy_resource_manifest.ps1
```
