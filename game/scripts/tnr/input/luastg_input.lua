local PlayerInput = require("tnr.input.player_input")

local LuaSTGInputProvider = {}
LuaSTGInputProvider.__index = LuaSTGInputProvider

function LuaSTGInputProvider.new(lstg)
    local keyboard = lstg.Input and lstg.Input.Keyboard or {}
    local mouse = lstg.Input and lstg.Input.Mouse or {}
    return setmetatable({
        lstg = lstg,
        keyboard = keyboard,
        mouse = mouse,
        tick = 0,
        previous = {},
        previous_mouse = false,
    }, LuaSTGInputProvider)
end

function LuaSTGInputProvider:key_down(code)
    return code ~= nil and self.keyboard.GetKeyState(code) == true
end

function LuaSTGInputProvider:key_pressed(code)
    local down = self:key_down(code)
    local was_down = self.previous[code] == true
    self.previous[code] = down
    return down and not was_down
end

function LuaSTGInputProvider:poll(player_id)
    self.tick = self.tick + 1
    local keyboard = self.keyboard
    local mouse = self.mouse
    local left = self:key_down(keyboard.Left)
    local right = self:key_down(keyboard.Right)
    local up = self:key_down(keyboard.Up)
    local down = self:key_down(keyboard.Down)
    local primary = mouse.GetKeyState and mouse.GetKeyState(mouse.Primary) == true or false
    local primary_pressed = primary and not self.previous_mouse
    self.previous_mouse = primary
    return PlayerInput.new(player_id, self.tick, {
        move_x = (right and 1 or 0) - (left and 1 or 0),
        move_y = (up and 1 or 0) - (down and 1 or 0),
        shoot = self:key_down(keyboard.Z),
        focus = self:key_down(keyboard.LeftShift),
        bomb = self:key_pressed(keyboard.X),
        confirm = self:key_pressed(keyboard.Enter) or self:key_pressed(keyboard.Space),
        cancel = self:key_pressed(keyboard.Escape),
        mouse_primary_pressed = primary_pressed,
    })
end

function LuaSTGInputProvider:get_mouse_position()
    if self.mouse.GetPosition then
        return self.mouse.GetPosition()
    end
    return self.lstg.GetMousePosition()
end

return LuaSTGInputProvider

