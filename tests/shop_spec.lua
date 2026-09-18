local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local a = GameSession.new({ run_seed = 12345, player_count = 2 })
    local b = GameSession.new({ run_seed = 12345, player_count = 2 })
    a:start_new(); b:start_new()
    local shop_a, shop_b
    for _, node in ipairs(a.map.nodes) do if node.type == Constants.node_types.SHOP then shop_a = node break end end
    for _, node in ipairs(b.map.nodes) do if node.type == Constants.node_types.SHOP then shop_b = node break end end
    assert_true(shop_a ~= nil and shop_b ~= nil, "shop test needs a shop node")
    a:debug_goto(shop_a.id); b:debug_goto(shop_b.id)
    assert_equal(a.shop_service:get_offers()[1].kind, b.shop_service:get_offers()[1].kind, "same seed shop kind")
    assert_equal(#a.shop_service:get_offers(), 5, "shop exposes five slots")
    for index, offer in ipairs(a.shop_service:get_offers()) do
        assert_equal(offer.price, 0, "shop offer is free during economy placeholder")
        assert_true(offer.kind ~= nil, "shop offer has a kind")
    end
    a:get_player(1):add_money(100); a:get_player(2):add_money(100)
    local before_b = a:get_player(2).money
    local bought, err = a:shop_purchase(1, 1)
    assert_true(bought, err or "player A should buy shop offer")
    assert_equal(a:get_player(2).money, before_b, "shop money is private")
    assert_true(a.shop_service.purchases[1][1] == true, "shop purchase is tracked per player")
end
