local RelicRuntime = {}
RelicRuntime.__index = RelicRuntime

function RelicRuntime.new(session)
    return setmetatable({ session = session, hit_taken = {}, stats = {}, active = {} }, RelicRuntime)
end

function RelicRuntime:_ids(player)
    local ids = {}
    if player.loadout and player.loadout.character_relic then ids[#ids + 1] = player.loadout.character_relic end
    for _, relic_id in ipairs(player.relics or {}) do ids[#ids + 1] = relic_id end
    return ids
end

function RelicRuntime:add(player_id, relic_id)
    local player = self.session:get_player(player_id)
    local definition = self.session.relic_catalog and self.session.relic_catalog[relic_id]
    if not player or not definition then return nil, "UNKNOWN_RELIC" end
    if definition.character_relic then
        player.loadout.character_relic = relic_id
        return true
    end
    player.relics = player.relics or {}
    player.relics[#player.relics + 1] = relic_id
    return true
end

function RelicRuntime:emit(event_name, player_id, context)
    context = context or {}
    for _, player in ipairs(self.session.players:get_players()) do
        if not player_id or player.player_id == player_id then
            local hit = self.hit_taken[player.player_id] == true
            for _, relic_id in ipairs(self:_ids(player)) do
                if event_name == "ON_BATTLE_START" and relic_id == "reimu_initial_relic" then
                    self.hit_taken[player.player_id] = false
                elseif event_name == "ON_PLAYER_HIT" and relic_id == "reimu_initial_relic" then
                    self.hit_taken[player.player_id] = true
                elseif event_name == "ON_BATTLE_CLEAR" and relic_id == "reimu_initial_relic" and not hit then
                    self.session.party:add_life_fragments(1)
                elseif event_name == "ON_ENEMY_KILL" and relic_id == "test_relic" then
                    self.stats[player.player_id] = (self.stats[player.player_id] or 0) + 1
                end
            end
        end
    end
    return true
end

return RelicRuntime
