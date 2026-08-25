local GameSession = require("tnr.core.game_session")
local LocalTransport = require("tnr.multiplayer.local_transport")
local SinglePlayerInputProvider = require("tnr.input.single_player")
local MapScene = require("tnr.map.map_scene")
local LuaSTGInputProvider = require("tnr.input.luastg_input")
local MapRenderer = require("tnr.ui.map_renderer")
local StageAdapter = require("tnr.battle.stage_adapter")
local DebugConsole = require("tnr.debug.console")
local Event = require("tnr.core.event")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

function Bootstrap.create(options)
    options = options or {}
    local session = GameSession.new(options)
    local transport = LocalTransport.new(session)
    local input = options.lstg and LuaSTGInputProvider.new(options.lstg) or SinglePlayerInputProvider.new(options.input)
    local map_scene = MapScene.new(session)
    local renderer = options.lstg and MapRenderer.new(options.lstg, options.width or 1280, options.height or 720) or nil
    local stage_adapter = StageAdapter.new(session, options.stage, options.lstg)
    local debug_console = DebugConsole.new(session, {
        on_kill_all = function()
            return stage_adapter:kill_all()
        end,
    })
    session:on(Event.ENCOUNTER_STARTED, function(event)
        stage_adapter:start(event.encounter)
    end)

    return setmetatable({
        session = session,
        transport = transport,
        input = input,
        map_scene = map_scene,
        renderer = renderer,
        stage_adapter = stage_adapter,
        debug_console = debug_console,
        initialized = false,
    }, Bootstrap)
end

function Bootstrap:init()
    if self.initialized then
        return
    end
    self.session:start_new()
    self.initialized = true
end

function Bootstrap:update()
    if not self.initialized then
        self:init()
    end
    local player_input = self.input:poll(1)
    if self.session.run_state == "MAP" then
        if player_input.move_x ~= 0 then
            self.map_scene:move_cursor(player_input.move_x)
        end
        if player_input.confirm then
            self.transport:send({ type = "SELECT_NODE", node_id = self.map_scene.cursor_node_id or (self.map_scene:get_selectable_nodes()[1] and self.map_scene:get_selectable_nodes()[1].id), player_id = 1 })
        end
        if self.input.get_mouse_position then
            local x, y = self.input:get_mouse_position()
            local map_x, map_y = x / 1280, y / 720
            if self.renderer and self.renderer.screen_to_map then
                map_x, map_y = self.renderer:screen_to_map(x, y)
            end
            if map_x and map_y then
                self.map_scene:hover_with_mouse(map_x, map_y)
                if player_input.mouse_primary_pressed then
                    self.map_scene:select_with_mouse(map_x, map_y)
                end
            else
                self.map_scene.cursor_node_id = nil
            end
        end
    elseif self.session.run_state == "ENCOUNTER" then
        self.stage_adapter:update(player_input)
    elseif self.session.run_state == "PLACEHOLDER" and (player_input.confirm or player_input.cancel) then
        self.transport:send({ type = "RETURN_TO_MAP" })
    end
    self.transport:submit_input(player_input)
    self.transport:update()
    return false
end

function Bootstrap:render()
    if self.session.run_state == "ENCOUNTER" and self.stage_adapter:is_fallback_active() then
        self.stage_adapter:render()
    elseif self.renderer then
        self.renderer:render(self.map_scene:get_view(), self.session)
    end
end

function Bootstrap:execute_debug(line)
    return self.debug_console:write(line)
end

function Bootstrap:shutdown()
    self.initialized = false
end

return Bootstrap
