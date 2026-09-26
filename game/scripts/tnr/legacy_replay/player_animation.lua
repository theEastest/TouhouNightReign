-- Legacy replay player animation.
--
-- The player sheet carries a script per pose: an idle and walk cycle, a
-- side-step cycle, and a firing pose. The reference switches between them from
-- the aim direction and the shot and focus buttons. This module drives that
-- switch and reports the sprite to draw.
--
-- Scripts come from the reference sheet (player/plNN/plNN.png):
--   0 idle and straight walk      sprites 0..7
--   1 side step one way           sprites 8..15
--   2 side step the other way     sprites 8..15 reversed
--   3 a second walk cycle         sprites 16..23
--   5 the firing pose             sprite 24 then 26..28

local PlayerAnimation = {}

PlayerAnimation.__index = PlayerAnimation

-- Pose ids, matching the archive script indices.
PlayerAnimation.POSE = {
    IDLE = 0,
    SIDE_A = 1,
    SIDE_B = 2,
    WALK = 3,
    FIRE = 5,
}

---@param archive table the player archive's first entry
function PlayerAnimation.new(archive, sheet)
    return setmetatable({
        archive = archive,
        sheet = sheet,
        script = nil,
        pc = 1,
        frame = 0,
        sprite = 1,
        -- The last movement direction, so the side-step pose faces the way the
        -- ship is moving.
        facing = 0,
    }, PlayerAnimation)
end

--- Begin a pose. A no-op when it is already playing.
function PlayerAnimation:play(pose)
    if self.script == pose then return end
    self.script = pose
    self.pc = 1
    self.frame = 0
    self.sprite = 1
end

--- Choose the pose from the current input and movement.
-- The reference fires while the shot button is held, steps sideways when moving
-- laterally and idles otherwise.
function PlayerAnimation:choose_pose(input)
    if input and input.shoot then
        return PlayerAnimation.POSE.FIRE
    end
    local move_x = tonumber(input and input.move_x) or 0
    if move_x > 0 then
        return self.facing >= 0 and PlayerAnimation.POSE.SIDE_A or PlayerAnimation.POSE.SIDE_B
    elseif move_x < 0 then
        return self.facing <= 0 and PlayerAnimation.POSE.SIDE_A or PlayerAnimation.POSE.SIDE_B
    end
    return PlayerAnimation.POSE.IDLE
end

--- Advance one frame, following the pose script's frame timeline.
function PlayerAnimation:update(input)
    if input then
        local move_x = tonumber(input.move_x) or 0
        if move_x ~= 0 then self.facing = move_x end
        self:play(self:choose_pose(input))
    end
    local script = self.archive and self.archive.scripts and self.archive.scripts[self.script]
    if not script then return end
    self.frame = self.frame + 1
    local guard = 0
    while self.pc <= #script and guard < 64 do
        guard = guard + 1
        local instruction = script[self.pc]
        if (instruction.time or 0) > self.frame then break end
        self.pc = self.pc + 1
        local id = instruction.id
        if id == 300 or id == 304 then
            -- Set sprite (the anm sprite index is zero based).
            if instruction[1] ~= nil then
                self.sprite = (tonumber(instruction[1]) or 0) + 1
            end
        elseif id == 200 then
            -- Loop back a number of instructions.
            local offset = tonumber(instruction[1]) or 0
            self.pc = math.max(1, self.pc - offset)
            self.frame = 0
        elseif id == 1 or id == 3 then
            -- Stop.
            break
        end
    end
end

--- The current sprite index, ready to address the image table.
function PlayerAnimation:sprite_index()
    return self.sprite
end

return PlayerAnimation
