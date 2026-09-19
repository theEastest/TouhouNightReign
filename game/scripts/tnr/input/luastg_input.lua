local PlayerInput = require("tnr.input.player_input")

local LuaSTGInputProvider = {}
LuaSTGInputProvider.__index = LuaSTGInputProvider

local DEFAULT_BINDINGS = {
    [1] = { left = "Left", right = "Right", up = "Up", down = "Down", shoot = "Z", focus = "LeftShift", bomb = "X", confirm = "Enter", cancel = "Escape" },
    -- Each LAN machine controls only its local player, so P2 intentionally
    -- uses the same default device mapping as P1. Same-machine co-op callers
    -- can still provide a distinct P2 mapping through options.bindings.
    [2] = { left = "Left", right = "Right", up = "Up", down = "Down", shoot = "Z", focus = "LeftShift", bomb = "X", confirm = "Enter", cancel = "Escape" },
}

local function resolve_key(keyboard, value)
    if type(value) == "number" then
        return value
    end
    return value and keyboard[value]
end

function LuaSTGInputProvider.new(lstg, options)
    options = options or {}
    local keyboard = lstg.Input and lstg.Input.Keyboard or {}
    local mouse = lstg.Input and lstg.Input.Mouse or {}
    return setmetatable({
        lstg = lstg,
        keyboard = keyboard,
        mouse = mouse,
        tick = 0,
        previous = {},
        previous_mouse = false,
        bindings = options.bindings or DEFAULT_BINDINGS,
        text_input = nil,
        text_input_checked = false,
        clipboard = nil,
        clipboard_checked = false,
        paste_down = {},
        bomb_charge = {},
        bomb_previous = {},
        bomb_fired = {},
        bomb_blocked = {},
        bomb_available = options.bomb_available,
    }, LuaSTGInputProvider)
end

function LuaSTGInputProvider:_ensure_text_input()
    if self.text_input_checked then return self.text_input end
    self.text_input_checked = true
    local ok, Window = pcall(require, "lstg.Window")
    if not ok or not Window or not Window.getMain then return nil end
    local window = Window.getMain()
    if window and window.queryInterface then
        self.text_input = window:queryInterface("lstg.Window.TextInputExtension")
    end
    return self.text_input
end

function LuaSTGInputProvider:_ensure_clipboard()
    if self.clipboard_checked then return self.clipboard end
    self.clipboard_checked = true
    local ok, Clipboard = pcall(require, "lstg.Clipboard")
    self.clipboard = ok and Clipboard or nil
    return self.clipboard
end

function LuaSTGInputProvider:_read_clipboard()
    local clipboard = self:_ensure_clipboard()
    if not clipboard or type(clipboard.getText) ~= "function" then return "" end
    local ok, text, err = pcall(clipboard.getText, clipboard)
    if not ok or text == nil then return "" end
    return tostring(text)
end

function LuaSTGInputProvider:_poll_paste(player_id, keyboard)
    -- Ctrl+V pastes the system clipboard into the focused text field. Use
    -- edge detection so a held modifier does not repeat the paste every frame.
    local ctrl = resolve_key(keyboard, "LeftControl") or resolve_key(keyboard, "RightControl")
        or resolve_key(keyboard, "Control")
    local v_key = resolve_key(keyboard, "V")
    if not ctrl or not v_key then return "" end
    local ctrl_down = self:key_down(ctrl)
    local v_down = self:key_down(v_key)
    local was_paste = self.paste_down[player_id] == true
    self.paste_down[player_id] = (ctrl_down and v_down) or nil
    if (ctrl_down and v_down) and not was_paste then
        return self:_read_clipboard()
    end
    return ""
end

function LuaSTGInputProvider:begin_text_input()
    local extension = self:_ensure_text_input()
    if not extension then return false end
    extension:clear()
    extension:setEnabled(true)
    return true
end

function LuaSTGInputProvider:end_text_input()
    local extension = self:_ensure_text_input()
    if not extension then return false end
    extension:setEnabled(false)
    extension:clear()
    return true
end

function LuaSTGInputProvider:consume_text()
    local extension = self:_ensure_text_input()
    if not extension or not extension:isEnabled() then return "" end
    local value = extension:toString()
    extension:clear()
    return value or ""
end

function LuaSTGInputProvider:key_down(code)
    if code == nil or type(self.keyboard.GetKeyState) ~= "function" then
        return false
    end
    -- LuaSTG versions expose key state as either a boolean or a numeric
    -- flag. Normalize both forms before the project input is serialized.
    local ok, state = pcall(self.keyboard.GetKeyState, code)
    return ok and not not state
end

function LuaSTGInputProvider:key_pressed(code, player_id)
    if code == nil then
        return false
    end
    player_id = player_id or 1
    self.previous[player_id] = self.previous[player_id] or {}
    local down = self:key_down(code)
    local was_down = self.previous[player_id][code] == true
    self.previous[player_id][code] = down
    return down and not was_down
end

function LuaSTGInputProvider:_poll_one(player_id, tick)
    local binding = self.bindings[player_id] or self.bindings[1] or DEFAULT_BINDINGS[1]
    local keyboard = self.keyboard
    local mouse = self.mouse
    local left = self:key_down(resolve_key(keyboard, binding.left))
    local right = self:key_down(resolve_key(keyboard, binding.right))
    local up = self:key_down(resolve_key(keyboard, binding.up))
    local down = self:key_down(resolve_key(keyboard, binding.down))
    local paste_text = self:_poll_paste(player_id, keyboard)
    local primary = false
    if type(mouse.GetKeyState) == "function" and mouse.Primary ~= nil then
        local ok, state = pcall(mouse.GetKeyState, mouse.Primary)
        primary = ok and not not state
    end
    local primary_pressed = primary and not self.previous_mouse
    self.previous_mouse = primary
    local bomb_down = self:key_down(resolve_key(keyboard, binding.bomb))
    local previous_bomb_down = self.bomb_previous[player_id] == true
    local bomb_charge = self.bomb_charge[player_id] or 0
    local bomb_fired = self.bomb_fired[player_id] == true
    local bomb_available = true
    if type(self.bomb_available) == "function" then
        local ok, value = pcall(self.bomb_available, player_id)
        bomb_available = ok and value ~= false
    end
    local bomb_blocked = self.bomb_blocked[player_id] == true
    if not bomb_available then
        bomb_charge, bomb_fired = 0, false
        bomb_blocked = bomb_down
        self.bomb_previous[player_id] = bomb_down
        self.bomb_charge[player_id] = 0
        self.bomb_fired[player_id] = false
        self.bomb_blocked[player_id] = bomb_blocked
        return PlayerInput.new(player_id, tick, {
            move_x = (right and 1 or 0) - (left and 1 or 0),
            move_y = (up and 1 or 0) - (down and 1 or 0),
            shoot = self:key_down(resolve_key(keyboard, binding.shoot)),
            focus = self:key_down(resolve_key(keyboard, binding.focus)),
            bomb_down = false,
            bomb = false,
            bomb_charged = false,
            bomb_success = false,
            confirm = self:key_pressed(resolve_key(keyboard, binding.confirm), player_id) or self:key_pressed(resolve_key(keyboard, binding.space or "Space"), player_id),
            cancel = self:key_pressed(resolve_key(keyboard, binding.cancel), player_id),
            tab = self:key_pressed(resolve_key(keyboard, "Tab"), player_id),
            backspace = self:key_pressed(resolve_key(keyboard, "Back"), player_id),
            paste = paste_text,
            mouse_primary_pressed = primary_pressed,
            mouse_primary_down = primary,
        })
    elseif bomb_blocked then
        if bomb_down then
            self.bomb_previous[player_id] = true
            self.bomb_charge[player_id] = 0
            self.bomb_fired[player_id] = false
            return PlayerInput.new(player_id, tick, {
                move_x = (right and 1 or 0) - (left and 1 or 0),
                move_y = (up and 1 or 0) - (down and 1 or 0),
                shoot = self:key_down(resolve_key(keyboard, binding.shoot)),
                focus = self:key_down(resolve_key(keyboard, binding.focus)),
                bomb_down = false,
                bomb = false,
                bomb_charged = false,
                bomb_success = false,
                confirm = self:key_pressed(resolve_key(keyboard, binding.confirm), player_id) or self:key_pressed(resolve_key(keyboard, binding.space or "Space"), player_id),
                cancel = self:key_pressed(resolve_key(keyboard, binding.cancel), player_id),
                tab = self:key_pressed(resolve_key(keyboard, "Tab"), player_id),
                backspace = self:key_pressed(resolve_key(keyboard, "Back"), player_id),
                paste = paste_text,
                mouse_primary_pressed = primary_pressed,
                mouse_primary_down = primary,
            })
        end
        self.bomb_blocked[player_id] = false
        self.bomb_previous[player_id] = false
        bomb_charge, bomb_fired = 0, false
    end
    local bomb_event, bomb_charged = false, false
    if bomb_down then
        if not previous_bomb_down then
            bomb_charge = 0
            bomb_fired = false
        end
        bomb_charge = math.min(180, bomb_charge + 1)
        if bomb_charge >= 180 and not bomb_fired then
            bomb_event, bomb_charged, bomb_fired = true, true, true
        end
    elseif previous_bomb_down then
        if bomb_charge > 0 and not bomb_fired then
            bomb_event = true
        end
        bomb_charge, bomb_fired = 0, false
    else
        bomb_charge = 0
    end
    self.bomb_previous[player_id] = bomb_down
    self.bomb_charge[player_id] = bomb_charge
    self.bomb_fired[player_id] = bomb_fired
    self.bomb_blocked[player_id] = false
    return PlayerInput.new(player_id, tick, {
        move_x = (right and 1 or 0) - (left and 1 or 0),
        move_y = (up and 1 or 0) - (down and 1 or 0),
        shoot = self:key_down(resolve_key(keyboard, binding.shoot)),
        focus = self:key_down(resolve_key(keyboard, binding.focus)),
        bomb_down = bomb_down,
        bomb = bomb_event,
        bomb_charged = bomb_charged,
        bomb_success = bomb_event,
        confirm = self:key_pressed(resolve_key(keyboard, binding.confirm), player_id) or self:key_pressed(resolve_key(keyboard, binding.space or "Space"), player_id),
        cancel = self:key_pressed(resolve_key(keyboard, binding.cancel), player_id),
        tab = self:key_pressed(resolve_key(keyboard, "Tab"), player_id),
        backspace = self:key_pressed(resolve_key(keyboard, "Back"), player_id),
        paste = paste_text,
        -- On a LAN peer the locally controlled player may be P2, so mouse
        -- input belongs to whichever player this provider is polling.
        mouse_primary_pressed = primary_pressed,
        mouse_primary_down = primary,
    })
end

function LuaSTGInputProvider:poll(player_id)
    self.tick = self.tick + 1
    return self:_poll_one(player_id, self.tick)
end

function LuaSTGInputProvider:poll_all(player_ids)
    self.tick = self.tick + 1
    local result = {}
    for _, player_id in ipairs(player_ids or { 1 }) do
        result[player_id] = self:_poll_one(player_id, self.tick)
    end
    return result
end

function LuaSTGInputProvider:get_mouse_position()
    if self.mouse.GetPosition then
        return self.mouse.GetPosition()
    end
    return self.lstg.GetMousePosition()
end

return LuaSTGInputProvider
