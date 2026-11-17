local History = require("tnr.stages.selection_history")

return function(assert_equal, assert_true, assert_false)
    local entries = {
        { id = "wave-a", class = "boss-a" },
        { id = "wave-b", class = "boss-b" },
        { id = "wave-c", class = "boss-c" },
    }
    local history = History.new()
    local picked = {}
    for index = 1, #entries do
        local entry = history:pick("waves", entries, 19, index, function(item) return item.id end)
        assert_true(entry ~= nil, "unused content remains available")
        assert_false(picked[entry.id] == true, "a content ID cannot repeat before the pool is exhausted")
        picked[entry.id] = true
    end
    local none, reason = history:pick("waves", entries, 19, 4, function(item) return item.id end)
    assert_equal(none, nil, "exhausted content pool does not silently repeat")
    assert_equal(reason, "POOL_EXHAUSTED", "exhaustion is explicit")

    local unique_classes = history:filter("bosses", entries, function(item) return item.class end)
    assert_equal(#unique_classes, #entries, "class history is an independent selection bucket")
    history:mark("bosses", "boss-a")
    unique_classes = history:filter("bosses", entries, function(item) return item.class end)
    assert_equal(#unique_classes, 2, "used classes are excluded from later rooms")
    history:reset()
    assert_equal(#history:filter("waves", entries, function(item) return item.id end), #entries,
        "new runs clear prior selection history")
end
