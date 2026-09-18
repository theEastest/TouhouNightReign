# Reimu Art Replacement Slots

Draw replacement files into this directory using these names. The LuaSTG
renderer loads them at startup. Headless tests and backends without texture
support fall back to procedural shapes, while gameplay logic remains
independent of the image dimensions.

| File | Reference role | Suggested source dimensions |
| --- | --- | --- |
| `reimu.png` | player sprite sheet; legacy sheet is 8 x 3 frames of 32 x 48 | 256 x 144 |
| `reimu_kekkai.png` | focused Bomb barrier texture | 256 x 256 |
| `reimu_bomb_ef.png` | unfocused Bomb / amulet effect | use any power-of-two canvas |
| `reimu_orange_eff.png` | focused shot trail/effect | 64 x 16 |
| `reimu_bullet_ef.psi` | normal-shot particle effect | LuaSTG particle file |
| `reimu_sp_ef.psi` | Bomb particle effect | LuaSTG particle file |

The currently extracted reference files are under
`game/legacy/assets/data/Thlib/player/reimu/`. Copying them is optional; you
can replace them with newly drawn files without changing gameplay code.
