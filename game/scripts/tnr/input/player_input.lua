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
        confirm = values.confirm == true,
        cancel = values.cancel == true,
        mouse_primary_pressed = values.mouse_primary_pressed == true,
    }
end

return PlayerInput
