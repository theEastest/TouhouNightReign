local LANTransport = require("tnr.multiplayer.lan_transport")
local NativeSyncAudit = require("tnr.multiplayer.native_sync_audit")
local NativeResourcePreflight = require("tnr.stages.native_resource_preflight")
local Bootstrap = require("tnr.bootstrap")
local FakeTransport = require("tnr.multiplayer.fake_transport")
local Constants = require("tnr.core.constants")

return function(assert_equal, assert_true)
    local transport = LANTransport.new({ mode = "client", player_id = 2 })
    transport:set_room_generation("run:4:99")
    transport.connected = true
    transport:submit_input({ tick = 1, move_x = 1, shoot = true })
    local decoded = LANTransport.decode(transport.outgoing[1]:sub(9))
    assert_equal(decoded.payload.room_generation, "run:4:99", "input packets carry room generation")

    transport.inbox[#transport.inbox + 1] = { kind = "input", payload = { player_id = 1, tick = 2, room_generation = "old" } }
    assert_true(transport:poll() == nil, "stale input is dropped")
    assert_equal(transport.stale_packets, 1, "stale packet count is observable")

    transport.inbox[#transport.inbox + 1] = {
        kind = "command", payload = { type = "RETURN_TO_MAP", room_generation = "old" },
    }
    assert_true(transport:poll() == nil, "stale command is dropped")
    assert_equal(transport.stale_packets, 2, "stale command count is observable")

    local rollover_transport = LANTransport.new({ mode = "host", player_id = 1 })
    rollover_transport:set_room_generation("room:first")
    rollover_transport:attach_session({
        room_generation = "room:second",
        current_encounter = { room_generation = "room:second" },
    })
    rollover_transport.inbox[#rollover_transport.inbox + 1] = {
        kind = "command",
        payload = { type = "LOADOUT_COMMIT", room_generation = "room:second" },
    }
    assert_true(rollover_transport:poll() ~= nil,
        "next-room loadout commit crosses the previous-room transport boundary")
    assert_equal(rollover_transport.stale_packets, 0,
        "valid next-room handshake is not counted as stale")
    rollover_transport.inbox[#rollover_transport.inbox + 1] = {
        kind = "command",
        payload = { type = "ENCOUNTER_READY", room_generation = "room:unrelated" },
    }
    assert_true(rollover_transport:poll() == nil,
        "unrelated room handshake remains rejected")
    assert_equal(rollover_transport.stale_packets, 1,
        "unrelated room handshake increments the stale counter")

    local map_transport = LANTransport.new({ mode = "host", player_id = 1 })
    local map_bootstrap = Bootstrap.create({
        transport = map_transport, network_role = "host", player_count = 2,
        local_player_id = 1, run_seed = 20260915,
    })
    map_bootstrap.session:start_new(20260915)
    map_transport:set_room_generation("room:finished")
    map_bootstrap.session.current_encounter = { id = "finished", room_generation = "room:finished" }
    map_bootstrap.session.run_state = Constants.run_states.REWARD
    assert_true(map_bootstrap.session:return_to_map() ~= nil,
        "completed network room returns to the map")
    assert_equal(map_transport:get_room_generation(), nil,
        "returning to the map clears the completed transport generation")

    local disconnect_reason
    local callback_transport = LANTransport.new({
        mode = "client",
        on_disconnect = function(reason) disconnect_reason = reason end,
    })
    callback_transport:disconnect("test disconnect")
    callback_transport:disconnect("duplicate disconnect")
    assert_equal(disconnect_reason, "test disconnect", "disconnect callback fires once")

    -- Host-local command dispatch may advance the room immediately. The wire
    -- copy must still carry the preparation-time generation captured before
    -- dispatch, otherwise the peer drops SET_READY as a new-room packet.
    local host_transport = LANTransport.new({ mode = "host", player_id = 1 })
    host_transport.connected = true
    local fake_session = {}
    function fake_session:dispatch()
        host_transport:set_room_generation("new-room")
    end
    host_transport:attach_session(fake_session)
    host_transport:send({ type = "SET_READY", player_id = 1 })
    local wire_ready = LANTransport.decode(host_transport.outgoing[1]:sub(9))
    assert_true(wire_ready.payload.room_generation == nil,
        "preparation command must not be tagged after host-local room transition")

    -- Both endpoints must leave preparation only after both Ready commands
    -- have been observed. In particular, the client must register its local
    -- loadout commit before sending SET_READY; otherwise the host advances
    -- while the client remains stuck in the preparation screen.
    local host_link, client_link = FakeTransport.create_pair()
    local host_bootstrap = Bootstrap.create({
        transport = host_link, network_role = "host", player_count = 2,
        local_player_id = 1, run_seed = 20260830,
    })
    local client_bootstrap = Bootstrap.create({
        transport = client_link, network_role = "client", player_count = 2,
        local_player_id = 2, run_seed = 20260830,
    })
    host_bootstrap._queue_encounter_start = function() end
    client_bootstrap._queue_encounter_start = function() end
    host_bootstrap.session:start_new(20260830)
    client_bootstrap.session:start_new(20260830)
    local preparation_node
    for _, candidate in ipairs(host_bootstrap.session.map.nodes or {}) do
        if host_bootstrap.session.map:is_adjacent(candidate.id) then
            preparation_node = candidate.id
            break
        end
    end
    assert_true(preparation_node ~= nil, "network preparation has an adjacent node")
    local host_preparation, host_preparation_err = host_bootstrap.session:enter_preparation(preparation_node)
    assert_true(host_preparation ~= nil,
        "host enters network preparation: " .. tostring(host_preparation_err))
    local client_preparation, client_preparation_err = client_bootstrap.session:enter_preparation(preparation_node)
    assert_true(client_preparation ~= nil,
        "client enters network preparation: " .. tostring(client_preparation_err))
    host_bootstrap.preparation_cursor = 1
    client_bootstrap.preparation_cursor = 1
    assert_true(client_bootstrap:_activate_preparation(), "client Ready accepted locally")
    client_link:update()
    host_link:update()
    assert_true(client_bootstrap.session:is_loadout_committed(2),
        "client keeps its local loadout commit")
    assert_true(client_bootstrap.session:get_player(2).map_ready,
        "client keeps its local Ready state")
    assert_true(host_bootstrap.session.run_state == "MAP_PREPARATION",
        "host waits for its own Ready state")
    assert_true(host_bootstrap:_activate_preparation(), "host Ready accepted")
    client_link:update()
    host_link:update()
    client_link:update()
    -- The lightweight fake transport can finish the synthetic encounter
    -- immediately.  Consume the new enemy-room reward barrier so this
    -- preparation protocol assertion still reaches the map state.
    if host_bootstrap.session.run_state == Constants.run_states.REWARD then
        host_bootstrap.session:claim_reward(1, 1)
        host_bootstrap.session:claim_reward(1, 2)
        host_bootstrap.session:claim_reward(2, 1)
        host_bootstrap.session:claim_reward(2, 2)
    end
    if client_bootstrap.session.run_state == Constants.run_states.REWARD then
        client_bootstrap.session:claim_reward(1, 1)
        client_bootstrap.session:claim_reward(1, 2)
        client_bootstrap.session:claim_reward(2, 1)
        client_bootstrap.session:claim_reward(2, 2)
    end
    assert_true(host_bootstrap.session.run_state == "MAP",
        "host leaves preparation after both Ready states")
    assert_true(client_bootstrap.session.run_state == "MAP",
        "client leaves preparation with host")

    local audit = NativeSyncAudit.new({ interval = 1 })
    local first = {
        room_generation = "run:4:99", frame = 30, team_lives = 3,
        boss_hp = 100, boss_timer = 60, boss_alive = true, bomb_generation = 0,
        players = { [1] = { x = 10, y = 20, hidden = false, dead = false } },
    }
    local second = {
        room_generation = "run:4:99", frame = 30, team_lives = 3,
        boss_hp = 100, boss_timer = 60, boss_alive = true, bomb_generation = 0,
        players = { [1] = { x = 10, y = 20, hidden = false, dead = false } },
    }
    assert_true(audit:observe("host", first, 1) ~= nil, "audit samples on interval")
    assert_true(audit:compare(first, second, 1), "matching native signatures are accepted")
    second.room_generation = "old"
    assert_true(not audit:compare(first, second, 2), "different room generations are rejected")
    local preflight = NativeResourcePreflight.run(".", { "ROOM_A", "ROOM_B", "ROOM_C" })
    assert_true(preflight.ok, "native resource roots must be present")
end
