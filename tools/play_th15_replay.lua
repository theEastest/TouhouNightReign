-- Run a stage using held input decoded from an original TH15 replay.
-- This is a development comparison harness; it never changes game resources.
package.path="game/scripts/?.lua;"..package.path
local input_path=assert(arg[1],"usage: play_th15_replay.lua <extracted-replay.lua> [classic|modern] [trace.tsv]")
local reference=assert(dofile(input_path),"replay input file returned no data")
local mode=arg[2] or "classic"
assert(mode=="classic" or mode=="modern","mode must be classic or modern")
local I=require("tnr.legacy_replay.interfaces")
local Stage=require("tnr.legacy_replay.stage_runtime")
local roster=I.PlayerRoster.new({player_ids={1}})
local definition=mode=="classic" and I.classic_mode() or I.modern_mode()
local session=I.ReplaySession.new({mode=definition,roster=roster})
session.power[1]=math.min(4,tonumber(reference.power) or session:get_power(1))
session.lives_left[1]=tonumber(reference.lives) or session:life_count(1)
session.bombs_left[1]=tonumber(reference.bombs) or session:bomb_count(1)
local stage_key=string.format("st%02d",assert(tonumber(reference.stage),"replay stage is missing"))
local stage=Stage.new({lstg={},stage=stage_key,difficulty=reference.difficulty,session=session,
    character=reference.character,seed=reference.seed,chunks=require("tnr.legacy_replay.data.th15_all"),
    anm=require("tnr.legacy_replay.data.th15_anm"),std=require("tnr.legacy_replay.data.th15_std"),
    sht=require("tnr.legacy_replay.data.th15_sht")})
local player=stage.players[1]
player.x,player.y=reference.start_x or player.x,reference.start_y or player.y
player.graze=reference.graze or 0
-- A mid-run replay starts with the fragments earned in earlier stages.
player.life_piece=reference.life_piece or 0
player.bomb_piece=reference.bomb_piece or 0
-- Older extracted tables stored PIV in native (100x) units.
if reference.seed and reference.point_rate then
    stage.point_rate=reference.point_rate
    player.point_rate=reference.point_rate
end
local control_index,held=1,0
local input_frame=0
local function bit(value,n) return math.floor(value/(2^n))%2==1 end
local function get_input(frame)
    local controls=reference.controls
    while controls[control_index] and controls[control_index][1]<=frame do
        held=controls[control_index][2]
        control_index=control_index+1
    end
    -- 4540ed..4541be prioritizes diagonal directions and reads focus at 0x08.
    local up,down=bit(held,4),bit(held,5)
    local horizontal=bit(held,6) and -1 or bit(held,7) and 1 or 0
    local vertical
    if horizontal~=0 then vertical=up and 1 or down and -1 or 0
    else vertical=down and -1 or up and 1 or 0 end
    return {move_x=horizontal,move_y=vertical,shoot=bit(held,0),bomb=bit(held,1),
        focus=bit(held,3),skip_dialogue=bit(held,9)}
end
roster:set_input(1,{sample=function() return get_input(input_frame) end})
stage:start()
local trace=arg[3] and assert(io.open(arg[3],"w"))
if trace then
    trace:write("stage\treplay_frame\tstage_frame\tchapter\tinput\tx\ty\trng_seed\trng_draws\tpower\tlives\tbombs\tgraze\tenemies\tscore\tchapter_graze\ttargets\tdefeated\tpoint_rate\n")
end
local last_report=0
for frame=1,reference.frames do
    input_frame=frame
    stage:update()
    if trace then
        trace:write(table.concat({reference.stage,frame,stage.frames,stage.chapter,held,player.x,player.y,
            stage.adapter.rng.state,stage.adapter.rng.draws,player.power,session:life_count(1),session:bomb_count(1),
            player.graze,#stage.adapter.enemies,stage.stats and stage.stats.score or 0,player.chapter_graze or 0,
            stage.adapter.chapter_targets,stage.adapter.chapter_defeated,player.point_rate or stage.point_rate},"\t"),"\n")
    end
    if stage.frames>=last_report+600 then
        last_report=stage.frames
        local p=stage.players[1]
        local bullets=0
        for _,shot in ipairs(stage.adapter.shots or {}) do if not shot.player_bullet then bullets=bullets+1 end end
        print(string.format("%s mode=%s frame=%d pos=(%.2f,%.2f) boss=%s shots=%d items=%d graze=%d power=%.2f lives=%d bombs=%d rng=%04x/%d",
            stage_key,mode,stage.frames,p.x,p.y,stage.adapter.boss_object and stage.adapter.boss_object.legacy_ecl or "-",
            bullets,#stage.items.list,p.graze,(p.power or 0)/100,session:life_count(1),session:bomb_count(1),
            stage.adapter.rng.state,stage.adapter.rng.draws))
    end
    if stage:timeline_finished() or session:life_count(1)<0 then break end
end
if trace then trace:close() end
local p=stage.players[1]
print("reference_complete",stage_key,mode,"frames",stage.frames,"source",reference.source,
    "timeline_clear",stage:timeline_finished(),"position",string.format("%.2f,%.2f",p.x,p.y),
    "power",string.format("%.2f",(p.power or 0)/100),"lives",session:life_count(1),"bombs",session:bomb_count(1))
