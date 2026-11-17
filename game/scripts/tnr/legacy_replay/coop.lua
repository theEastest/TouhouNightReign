-- Existing co-op rules, applied to the imported stage: a ten-second solo
-- respawn; a team wipe spends one Party life; Bomb inventory is now shared.
local Aggro=require("tnr.multiplayer.aggro")
local Coop={};Coop.__index=Coop
Coop.RESPAWN_FRAMES=600
function Coop.new(stage)
    return setmetatable({stage=stage,respawns={},aggro=Aggro.new(300),focus=1,wipes=0},Coop)
end
function Coop:revive(id)
    self.respawns[id]=nil
    local p=self.stage.players[id]
    p:respawn(id==1 and -48 or 48,400)
end
function Coop:hit(id)
    local s=self.stage
    if self.respawns[id] or s.session.team_defeated then return end
    local p=s.players[id]
    p:hit();p.misses=(p.misses or 0)+1
    s:apply_miss_power(id,p)
    self.respawns[id]=Coop.RESPAWN_FRAMES
    local other=id==1 and 2 or 1
    if not self.respawns[other] then
        self.focus=other;s.adapter.player=s.players[other];return
    end
    self.wipes=self.wipes+1
    -- Modern "不甘" progresses on a team wipe, not the first player's miss.
    for _,member in pairs(s.players) do
        if member.combat_runtime then member.combat_runtime.affixes:miss() end
    end
    s.session.party:add_team_life(-1)
    local kept={}
    for _,shot in ipairs(s.adapter.shots) do if shot.player_bullet then kept[#kept+1]=shot end end
    s.adapter.shots=kept
    if s.session.party.team_life<=0 then s.session.team_defeated=true;return end
    -- Only losing a team life is equivalent to a solo miss. A player's
    -- ten-second respawn by itself does not refill the shared inventory.
    s.session:restore_bombs_after_miss(id)
    self:revive(1);self:revive(2)
end
function Coop:update()
    if self.stage.session.team_defeated then return end
    for id=1,2 do
        if self.respawns[id] then
            self.respawns[id]=self.respawns[id]-1
            if self.respawns[id]<=0 then self:revive(id) end
        end
    end
    local report=self.aggro:advance(1)
    if report then self.focus=Aggro.compare(report,report,self.focus) end
    if not self.stage.players[self.focus].alive then self.focus=3-self.focus end
    self.stage.adapter.player=self.stage.players[self.focus]
end
return Coop
