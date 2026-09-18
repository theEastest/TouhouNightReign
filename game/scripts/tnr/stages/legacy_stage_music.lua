-- Initial BGM used by the exported reference stages.  A stage can later
-- change its BGM from inside a card; those changes still go through the
-- native PlayMusic guard.  A missing entry is intentional: the reference
-- stage did not issue a startup PlayMusic command, so the current track is
-- preserved when entering it.
return {
    ["lico@Normal"] = "はちみつれもん-二色莲花蝶",
    ["lico@Lunatic"] = "はちみつれもん-二色莲花蝶",
    ["xy@Normal"] = "BGM-YEWAN",
    ["xy@Lunatic"] = "BGM-YEWAN",
    ["qxs@Normal"] = "qxs_GrayMoon",
    ["qxs@Lunatic"] = "qxs_GrayMoon",
    ["karl@Normal"] = "Cirno_stage",
    ["karl@Lunatic"] = "Cirno_stage",
    ["kbz@Normal"] = "黄昏フロンティア - アンノウンＸ～Occultly Madness",
    ["kbz@Lunatic"] = "黄昏フロンティア - アンノウンＸ～Occultly Madness",
    ["xiv@Normal"] = "stageBGM",
    ["xiv@Lunatic"] = "Still Love You",
    ["sf@Normal"] = "妖怪宇宙旅行",
    ["sf@Lunatic"] = "妖怪宇宙旅行",
    ["ae@Normal"] = "AE_bgm_road",
    ["ae@Lunatic"] = "AE_bgm_road",
    ["void@Normal"] = "静寂の祭 ~ the shadow in the library",
    ["void@Lunatic"] = "静寂の祭 ~ the shadow in the library",
    ["wyj@Normal"] = "wyj_Roadbgm",
    ["wyj@Lunatic"] = "wyj_Roadbgm",
    ["yyzy@Normal"] = "th12.8_07",
    ["yyzy@Lunatic"] = "th12.8_07",
    ["stp@Normal"] = "dBu music - 雾雨 ~ Loose Rain",
    ["stp@Lunatic"] = "dBu music - 雾雨 ~ Loose Rain",
    ["smf@Normal"] = "格兰之森",
    ["smf@Lunatic"] = "格兰之森",
    ["olc@Normal"] = "OLC_マジカルストーム",
    ["olc@Lunatic"] = "OLC_マジカルストーム",
    ["er@Normal"] = "black opal labyrinth",
    ["er@Lunatic"] = "black opal labyrinth",
    ["yh@Normal"] = "yahoon-road",
    ["yh@Lunatic"] = "yahoon-road",
}
