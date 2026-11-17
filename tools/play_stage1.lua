package.path="game/scripts/?.lua;"..package.path
local Stage=require("tnr.legacy_replay.stage_runtime")
local I=require("tnr.legacy_replay.interfaces")
local Pilot=require("tnr.debug.replay_pilot")
local mode=arg[1] or "classic"
assert(mode=="classic" or mode=="modern","mode must be classic or modern")
local player_count=tonumber(arg[5]) or 1
assert(player_count==1 or player_count==2,"player count must be 1 or 2")
local roster=I.PlayerRoster.new({player_ids=player_count==2 and {1,2} or {1}})
local session=I.ReplaySession.new({mode=mode=="classic" and I.classic_mode() or I.modern_mode(),roster=roster})
local stage_key=arg[4] or "st01"
local characters={ [1]=arg[3] or "reimu",[2]=arg[6] or "sanae" }
local equipment_session
if mode=="modern" then
    -- Give every co-op pilot the same starter equipment that Replay:start_stage
    -- supplies in the actual selection flow. Without this, StageRuntime's
    -- fallback creates a one-player equipment session and P2 has no weapons.
    equipment_session=require("tnr.core.game_session").new({
        run_seed=151,player_count=player_count,character_id=characters[1],
        character_by_player=characters,
    })
    equipment_session:start_new(151)
end
local stage=Stage.new({lstg={},stage=stage_key,difficulty=tonumber(arg[2]) or 1,session=session,
    character=characters[1],characters=characters,
    equipment_session=equipment_session,
    anm=require("tnr.legacy_replay.data.th15_anm"),chunks=require("tnr.legacy_replay.data.th15_all"),
    std=require("tnr.legacy_replay.data.th15_std"),sht=require("tnr.legacy_replay.data.th15_sht")})
for _,player_id in ipairs(session.roster:list()) do
    local pilot_id=player_id
    session.roster:set_input(player_id,{sample=function() return Pilot.sample(stage,pilot_id) end})
end
stage:start()
-- Later stages can exceed ten minutes even with normal attacks. A stage-one
-- duration limit must not classify a still-live stage-six run as a failure.
for frame=1,100000 do
    stage:update()
    if frame%2000==0 then print(mode,"players="..player_count,frame,session:life_count(1),session.bombs_left[1],#stage.adapter.shots) end
    if stage:timeline_finished() or session:life_count(1)<0 then break end
end
print("result",mode,"players="..player_count,stage.frames,"clear",stage:timeline_finished(),"lives",session:life_count(1),"bombs",session:bomb_count(1),
    "modern_shots",stage.modern and #stage.modern.shots or 0)
if not stage:timeline_finished() then
    for player_id,p in ipairs(stage.players) do
        print("player",player_id,"misses",p.misses or 0,"alive",p.alive,"xy",p.x,p.y,
            "power",p.power,"invulnerable",p.invulnerable)
        local d=stage.modern and stage.modern.drivers[player_id]
        if d then print("driver",player_id,"weapons",#d.weapon_manager.weapons,"P",d.p_gauge.value,
            "hot",d.p_gauge.hot_frames) end
    end
    local boss=stage.adapter.boss_object
    print("world","enemies",#stage.adapter.enemies,"shots",#stage.adapter.shots,
        "boss",boss and boss.legacy_ecl or "none",boss and boss.x or "-",boss and boss.y or "-")
end
for _,entry in ipairs(stage.adapter:missing_report()) do print("unhandled",entry[1],entry[2]) end
assert(stage:timeline_finished(),"input-only pilot did not clear "..stage_key)
for _,player_id in ipairs(session.roster:list()) do
    assert(session:life_count(player_id)>=0,"player "..player_id.." exhausted lives before stage clear")
end
if stage_key=="st01" then assert(stage.dialogue.completed[0] and stage.dialogue.completed[1],"both conversations must complete") end
assert(not stage.adapter.boss_object,"boss must be defeated or timeout before clear")
assert(#stage.adapter:missing_report()==0,"unhandled ECL")
