-- Selectable characters shown on the pre-map character select screen.
--
-- Order is the display order. `blurb` is a short player-facing description of
-- the character's shot identity. `asset_prefix` is the project asset folder
-- used for the portrait, when one ships.

return {
    {
        id = "reimu",
        display_name = "博丽灵梦",
        display_name_en = "Hakurei Reimu",
        blurb = "平衡型 · 高速封魔针",
        detail = "追踪灵符与阴阳玉子机，攻守均衡。",
        asset_prefix = "reimu",
    },
    {
        id = "marisa",
        display_name = "雾雨魔理沙",
        display_name_en = "Kirisame Marisa",
        blurb = "高速型 · 广域魔法弹",
        detail = "移动速度最快，魔法飞弹覆盖范围广。",
        asset_prefix = "marisa",
    },
    {
        id = "sanae",
        display_name = "东风谷早苗",
        display_name_en = "Kochiya Sanae",
        blurb = "追踪型 · 风祝神风",
        detail = "风刃具备追踪能力，擅长清理分散目标。",
        asset_prefix = "sanae",
    },
}
