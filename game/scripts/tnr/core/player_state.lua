local PlayerState = {}
PlayerState.__index = PlayerState

function PlayerState.new(player_id, options)
    options = options or {}
    return setmetatable({
        player_id = assert(player_id, "player_id is required"),
        money = options.money or 0,
        score = options.score or 0,
        life = options.life or 3,
        bomb = options.bomb or 3,
        alive = options.alive ~= false,
        character_id = options.character_id or "reimu",
    }, PlayerState)
end

function PlayerState:add_money(amount)
    self.money = math.max(0, self.money + (amount or 0))
end

function PlayerState:add_score(amount)
    self.score = math.max(0, self.score + (amount or 0))
end

function PlayerState:add_life(amount)
    self.life = math.max(0, self.life + (amount or 0))
    self.alive = self.life > 0
end

function PlayerState:add_bomb(amount)
    self.bomb = math.max(0, self.bomb + (amount or 0))
end

return PlayerState

