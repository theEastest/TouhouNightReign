local NativeSyncAudit = {}
NativeSyncAudit.__index = NativeSyncAudit

local function n(value, default)
    value = tonumber(value)
    return value == nil and default or value
end

local function q(value, precision)
    value = n(value, 0)
    local scale = precision or 100
    return math.floor(value * scale + (value >= 0 and 0.5 or -0.5)) / scale
end

local function player_signature(player)
    player = player or {}
    return table.concat({
        q(player.x), q(player.y), player.visible == false and 0 or 1,
        player.alive == false and 0 or 1, n(player.respawn_frames, 0),
    }, ":")
end

function NativeSyncAudit.signature(snapshot)
    snapshot = snapshot or {}
    local players = snapshot.players or {}
    local ids = {}
    for id in pairs(players) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
    local parts = {
        tostring(snapshot.room_generation or "nil"),
        tostring(n(snapshot.native_frame or snapshot.frame_count, 0)),
        tostring(n(snapshot.team_lives, 0)),
        tostring(n(snapshot.boss_hp, 0)),
        tostring(n(snapshot.boss_timer, 0)),
        tostring(snapshot.boss_alive == false and 0 or 1),
        tostring(snapshot.bomb_generation or 0),
    }
    for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) .. "=" .. player_signature(players[id]) end
    return table.concat(parts, "|")
end

function NativeSyncAudit.new(options)
    options = options or {}
    return setmetatable({
        interval = math.max(1, math.floor(options.interval or 30)),
        tick = 0,
        samples = {},
        first_mismatch = nil,
        last_result = "UNINITIALIZED",
        room_generation = nil,
    }, NativeSyncAudit)
end

function NativeSyncAudit:reset(room_generation)
    self.tick, self.samples, self.first_mismatch = 0, {}, nil
    self.last_result = "RESET"
    self.room_generation = room_generation
end

function NativeSyncAudit:observe(role, snapshot, tick)
    if type(snapshot) ~= "table" then return nil end
    self.tick = tonumber(tick) or (self.tick + 1)
    if self.tick % self.interval ~= 0 then return nil end
    local sample = {
        role = role,
        tick = self.tick,
        room_generation = snapshot.room_generation,
        signature = NativeSyncAudit.signature(snapshot),
        snapshot = snapshot,
    }
    self.samples[#self.samples + 1] = sample
    if #self.samples > 12 then table.remove(self.samples, 1) end
    return sample
end

function NativeSyncAudit:compare(local_snapshot, remote_snapshot, tick)
    if type(local_snapshot) ~= "table" or type(remote_snapshot) ~= "table" then
        self.last_result = "WAITING"
        return false, "missing_snapshot"
    end
    if local_snapshot.room_generation ~= remote_snapshot.room_generation then
        self.last_result = "ROOM_GENERATION_MISMATCH"
        self.first_mismatch = self.first_mismatch or { tick = tick, field = "room_generation" }
        return false, "room_generation"
    end
    local left, right = NativeSyncAudit.signature(local_snapshot), NativeSyncAudit.signature(remote_snapshot)
    if left ~= right then
        self.last_result = "KNOWN_VISUAL_DESYNC"
        self.first_mismatch = self.first_mismatch or { tick = tick, field = "signature", local_signature = left, remote_signature = right }
        return false, "signature"
    end
    self.last_result = "OK"
    return true
end

function NativeSyncAudit:status()
    return { result = self.last_result, first_mismatch = self.first_mismatch, room_generation = self.room_generation, sample_count = #self.samples }
end

return NativeSyncAudit
