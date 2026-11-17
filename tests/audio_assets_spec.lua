return function(assert_equal, assert_true)
    for stage = 1, 7 do
        local key = string.format("st%02d", stage)
        for _, suffix in ipairs({ "", "boss" }) do
            local path = "game/assets/legacy_replay/bgm/" .. key .. suffix .. ".ogg"
            local file = io.open(path, "rb")
            assert_true(file ~= nil, "replay music asset exists: " .. path)
            local header = file:read(4)
            local size = file:seek("end")
            file:close()
            assert_equal(header, "OggS", "replay music is a valid Ogg stream: " .. path)
            assert_true(size and size > 1000000, "replay music is not an empty placeholder: " .. path)
        end
    end

    local function same_file(left_path, right_path)
        local left = assert(io.open(left_path, "rb"))
        local right = assert(io.open(right_path, "rb"))
        while true do
            local a = left:read(65536)
            local b = right:read(65536)
            if a ~= b then left:close(); right:close(); return false end
            if a == nil then left:close(); right:close(); return true end
        end
    end

    -- A previous package accidentally assigned each boss recording to the
    -- following stage's main slot. Keep the full stage/boss sequence distinct.
    for stage = 1, 6 do
        local boss = string.format("game/assets/legacy_replay/bgm/st%02dboss.ogg", stage)
        local next_stage = string.format("game/assets/legacy_replay/bgm/st%02d.ogg", stage + 1)
        assert_true(not same_file(boss, next_stage),
            "boss track must not be duplicated as the following stage track: " .. boss .. " / " .. next_stage)
    end
end
