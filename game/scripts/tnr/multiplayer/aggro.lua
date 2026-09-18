-- Deterministic five-second damage windows used by the co-op native bridge.
-- The transport only needs the completed report and the selected player; all
-- bullet simulation remains local on both peers.
local Aggro = {}
Aggro.__index = Aggro

function Aggro.new(window_frames)
    return setmetatable({
        window_frames = math.max(1, math.floor(tonumber(window_frames) or 300)),
        window_id = 0,
        frame = 0,
        damage = { [1] = 0, [2] = 0 },
        last_report = nil,
        focus_player = 1,
    }, Aggro)
end

function Aggro:reset()
    self.window_id = 0
    self.frame = 0
    self.damage[1], self.damage[2] = 0, 0
    self.last_report = nil
    self.focus_player = 1
    return self
end

function Aggro:record(player_id, amount)
    player_id = tonumber(player_id)
    amount = tonumber(amount)
    if (player_id ~= 1 and player_id ~= 2) or not amount or amount <= 0 then
        return false
    end
    self.damage[player_id] = (self.damage[player_id] or 0) + amount
    return true
end

function Aggro:advance(frames)
    frames = math.max(0, math.floor(tonumber(frames) or 1))
    local report
    self.frame = self.frame + frames
    if self.frame >= self.window_frames then
        self.frame = self.frame % self.window_frames
        self.window_id = self.window_id + 1
        report = {
            window_id = self.window_id,
            damage = { [1] = self.damage[1] or 0, [2] = self.damage[2] or 0 },
        }
        self.damage[1], self.damage[2] = 0, 0
        self.last_report = report
    end
    return report
end

function Aggro.compare(local_report, remote_report, current_focus)
    if type(local_report) ~= "table" or type(remote_report) ~= "table"
            or tonumber(local_report.window_id) ~= tonumber(remote_report.window_id) then
        return nil
    end
    local local_damage = tonumber(local_report.damage and local_report.damage[1]) or 0
    local remote_damage = tonumber(remote_report.damage and remote_report.damage[2]) or 0
    -- Ties deliberately retain the previous focus to avoid oscillation.
    if local_damage > remote_damage then return 1 end
    if remote_damage > local_damage then return 2 end
    return tonumber(current_focus) == 2 and 2 or 1
end

return Aggro
