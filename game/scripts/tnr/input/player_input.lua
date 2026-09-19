local PlayerInput = {}

function PlayerInput.new(player_id, tick, values)
    values = values or {}
    return {
        player_id = player_id,
        tick = tick,
        move_x = values.move_x or 0,
        move_y = values.move_y or 0,
        shoot = values.shoot == true,
        focus = values.focus == true,
        bomb = values.bomb == true,
        bomb_charged = values.bomb_charged == true,
        bomb_success = values.bomb_success == true,
        -- Held state is local-only. Network serialization intentionally
        -- strips it and transmits only the final release event.
        bomb_down = values.bomb_down == true,
        confirm = values.confirm == true,
        cancel = values.cancel == true,
        tab = values.tab == true,
        backspace = values.backspace == true,
        text = tostring(values.text or ""),
        paste = tostring(values.paste or ""),
        mouse_primary_pressed = values.mouse_primary_pressed == true,
        mouse_primary_down = values.mouse_primary_down == true,
    }
end

return PlayerInput
