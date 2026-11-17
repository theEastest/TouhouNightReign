-- Player body scripts 0..4 are independent of shooting (shot scripts start at 5).
local VM=require("tnr.legacy_replay.anm_player")
local A={};A.__index=A
A.POSE={IDLE=0,SIDE_A=1,SIDE_B=3,RETURN_LEFT=2,RETURN_RIGHT=4,FIRE=0}
function A.new(archive,sheet)
    return setmetatable({archive=archive,sheet=sheet,vm=VM.new(archive,sheet),facing=0,sprite=1},A)
end
function A:play(pose)
    if self.script==pose then return end
    self.script=pose;self.vm:play(pose)
end
function A:choose_pose(input)
    local dx=tonumber(input and input.move_x) or 0
    if dx<0 then return 1 elseif dx>0 then return 3 end
    if self.facing<0 then return 2 elseif self.facing>0 then return 4 end
    return 0
end
function A:update(input)
    local dx=tonumber(input and input.move_x) or 0
    if input then self:play(self:choose_pose(input)) end
    if dx~=0 then self.facing=dx end
    self.vm:update();self.sprite=self.vm.sprite
end
function A:sprite_index() return self.sprite end
return A
