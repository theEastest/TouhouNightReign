local CapacityProgression = require("tnr.character.runtime.capacity_progression")
local PlayerState = require("tnr.core.player_state")

return function(assert_equal, assert_true)
    local progression = CapacityProgression.new({
        { score = 0, capacity = 100, level = 0 },
        { score = 10, capacity = 120, level = 1 },
        { score = 20, capacity = 150, level = 2 },
    })
    local player = PlayerState.new(1)
    progression:apply(player)
    assert_equal(player.current_capacity, 100, "base capacity is 100")
    player:add_score(10)
    local changed, capacity, level = progression:apply(player)
    assert_true(changed, "threshold changes capacity")
    assert_equal(capacity, 120, "first threshold capacity")
    assert_equal(level, 1, "first threshold level")
    assert_equal(player.score, 10, "capacity does not consume score")
    player:add_score(10)
    progression:apply(player)
    assert_equal(player.current_capacity, 150, "second threshold capacity")
end
