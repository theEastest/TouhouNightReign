local BattleSync = {}
BattleSync.__index = BattleSync

local INPUT_BUNDLE = "INPUT_BUNDLE"

local function transport_is_host(transport)
    if transport and transport.is_host then
        return transport:is_host()
    end
    return transport and (transport.role == "host" or transport.mode == "host") or false
end

local function copy_input(input, player_id, tick)
    return {
        player_id = player_id,
        tick = tick,
        move_x = input and input.move_x or 0,
        move_y = input and input.move_y or 0,
        shoot = input and input.shoot == true,
        focus = input and input.focus == true,
        bomb = input and input.bomb == true,
        bomb_charged = input and input.bomb_charged == true,
        bomb_success = input and input.bomb_success == true,
    }
end

function BattleSync.new(transport, options)
    options = options or {}
    local role = options.role
    if not role and transport and (transport.role or transport.mode) then
        role = transport_is_host(transport) and "host" or "client"
    end
    return setmetatable({
        transport = assert(transport, "battle sync transport is required"),
        role = role or "local",
        local_player_id = options.local_player_id or transport.player_id or 1,
        snapshot_interval = math.max(1, math.floor(options.snapshot_interval or 30)),
        pending_inputs = {},
        input_bundles = {},
        pending_snapshots = {},
        submitted_tick = nil,
        first_mismatch_tick = nil,
        last_compared_tick = nil,
        last_host_hash = nil,
        last_local_hash = nil,
    }, BattleSync)
end

function BattleSync:is_networked()
    return self.role == "host" or self.role == "client"
end

function BattleSync:is_host()
    return self.role == "host"
end

function BattleSync:_player_ids(session)
    local ids = session.party and session.party.player_ids or nil
    if ids and #ids > 0 then
        return ids
    end
    local result = {}
    for player_id = 1, session.player_count or 1 do
        result[#result + 1] = player_id
    end
    return result
end

function BattleSync:_receive()
    self.transport:update()
    if self.transport.consume_inputs then
        for player_id, input in pairs(self.transport:consume_inputs() or {}) do
            local tick = input.tick
            if tick then
                self.pending_inputs[tick] = self.pending_inputs[tick] or {}
                self.pending_inputs[tick][player_id] = copy_input(input, player_id, tick)
            end
        end
    end
    if self.transport.consume_events then
        for _, event in ipairs(self.transport:consume_events() or {}) do
            if event and event.type == INPUT_BUNDLE and event.tick then
                self.input_bundles[event.tick] = event.inputs or {}
            end
        end
    end
    if self.transport.consume_snapshot then
        local snapshot = self.transport:consume_snapshot()
        if snapshot and snapshot.tick then
            self.pending_snapshots[snapshot.tick] = snapshot
        end
    end
end

function BattleSync:_submit_local_input(local_inputs, target_tick)
    if self.submitted_tick == target_tick then
        return
    end
    local input = local_inputs[self.local_player_id] or local_inputs[1] or {}
    input = copy_input(input, self.local_player_id, target_tick)
    self.transport:submit_input(input)
    self.pending_inputs[target_tick] = self.pending_inputs[target_tick] or {}
    self.pending_inputs[target_tick][self.local_player_id] = input
    self.submitted_tick = target_tick
end

function BattleSync:before_update(local_inputs, stage_adapter)
    if not self:is_networked() then
        return local_inputs
    end
    local runtime = stage_adapter and stage_adapter.runtime
    if not runtime then
        self:_receive()
        return nil
    end
    local target_tick = runtime.battle_tick.tick + 1
    self:_submit_local_input(local_inputs or {}, target_tick)
    self:_receive()

    if self:is_host() then
        local pending = self.pending_inputs[target_tick] or {}
        local bundle = {}
        for _, player_id in ipairs(self:_player_ids(stage_adapter.session)) do
            if not pending[player_id] then
                return nil
            end
            bundle[player_id] = pending[player_id]
        end
        self.pending_inputs[target_tick] = nil
        local wire_bundle = {}
        for player_id, player_input in pairs(bundle) do
            local wire_input = {}
            for key, value in pairs(player_input) do
                if key ~= "bomb_down" then wire_input[key] = value end
            end
            wire_bundle[player_id] = wire_input
        end
        self.transport:broadcast({ type = INPUT_BUNDLE, tick = target_tick, inputs = wire_bundle })
        self.transport:update()
        -- Keep the held Bomb state local to the owning simulation. It is
        -- deliberately absent from the wire bundle, but the host still needs
        -- it to advance its own charge meter on this frame.
        local local_input = local_inputs and local_inputs[self.local_player_id]
        if local_input then bundle[self.local_player_id].bomb_down = local_input.bomb_down == true end
        return bundle
    end

    local bundle = self.input_bundles[target_tick]
    if bundle then
        self.input_bundles[target_tick] = nil
        -- The client also advances its own charge locally; only the release
        -- event (bomb/bomb_charged/bomb_success) comes from the host bundle.
        local local_input = local_inputs and local_inputs[self.local_player_id]
        if local_input and bundle[self.local_player_id] then
            bundle[self.local_player_id].bomb_down = local_input.bomb_down == true
        end
    end
    return bundle
end

function BattleSync:_compare_snapshot(stage_adapter, snapshot)
    if not snapshot or not stage_adapter.runtime then
        return
    end
    local local_tick = stage_adapter.runtime.battle_tick.tick
    if snapshot.tick ~= local_tick then
        return
    end
    local local_hash = stage_adapter:world_hash()
    self.last_compared_tick = local_tick
    self.last_local_hash = local_hash
    self.last_host_hash = snapshot.world_hash
    if snapshot.world_hash and local_hash ~= snapshot.world_hash then
        self.first_mismatch_tick = self.first_mismatch_tick or local_tick
        stage_adapter:apply_snapshot(snapshot)
    end
end

function BattleSync:after_update(stage_adapter)
    if not self:is_networked() or not stage_adapter or not stage_adapter.runtime then
        return
    end
    local tick = stage_adapter.runtime.battle_tick.tick
    if self:is_host() then
        if tick % self.snapshot_interval == 0 then
            local snapshot = stage_adapter:make_network_snapshot()
            snapshot.world_hash = stage_adapter:world_hash()
            self.transport:publish_snapshot(snapshot)
            self.transport:update()
        end
        return
    end
    self:_receive()
    local snapshot = self.pending_snapshots[tick]
    if snapshot then
        self.pending_snapshots[tick] = nil
        self:_compare_snapshot(stage_adapter, snapshot)
    end
end

function BattleSync:get_status()
    if self.first_mismatch_tick then
        return "DESYNC", self.first_mismatch_tick
    end
    return "SYNC OK", self.last_compared_tick
end

return BattleSync
