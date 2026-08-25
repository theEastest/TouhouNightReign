local BattleManager = require("tnr.battle.battle_manager")

local StageAdapter = {}
StageAdapter.__index = StageAdapter

function StageAdapter.new(session, stage_api)
    return setmetatable({
        session = session,
        stage_api = stage_api,
        battle = BattleManager.new(session),
        active_encounter = nil,
    }, StageAdapter)
end

function StageAdapter:start(encounter)
    self.active_encounter = encounter
    self.battle:begin(encounter)
    if self.stage_api and self.stage_api.Set then
        self.stage_api.Set(encounter.stage_id)
        return true
    end
    return false
end

function StageAdapter:get_battle_manager()
    return self.battle
end

function StageAdapter:complete(clear_state, options)
    return self.battle:complete(clear_state, options)
end

function StageAdapter:kill_all()
    if self.stage_api and self.stage_api.kill_all then
        return self.stage_api.kill_all()
    end
    return false
end

return StageAdapter

