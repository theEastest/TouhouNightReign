return function(assert_equal, assert_true)
    local AudioManager = require("tnr.audio.audio_manager")
    local events = {}
    local status = "stage"
    local fake = {
        GetResourceStatus = function() return status end,
        SetResourceStatus = function(value) status = value end,
        LoadSound = function(id) events[#events + 1] = "load-sound:" .. id end,
        LoadMusic = function(id) events[#events + 1] = "load-music:" .. id end,
        EnumRes = function() return { "old-global" }, { "old-stage" } end,
        StopMusic = function(id) events[#events + 1] = "stop:" .. id end,
        PlayMusic = function(id) events[#events + 1] = "play:" .. id end,
        SetBGMVolume = function(id) events[#events + 1] = "volume:" .. id end,
    }
    local old_record = rawget(_G, "LoadMusicRecord")
    _G.LoadMusicRecord = function(name) events[#events + 1] = "record:" .. name end
    local audio = AudioManager.new(fake)
    audio:load()
    assert_true(audio.loaded["music:menu"] ~= nil, "menu BGM is loaded")
    assert_equal(status, "stage", "resource status is restored after audio loading")
    assert_true(audio:play_music("menu"), "menu BGM starts")
    assert_true(audio:play_original("BGM-YEWAN"), "reference BGM starts")
    local stopped_global, stopped_stage = false, false
    for _, event in ipairs(events) do
        if event == "stop:old-global" then stopped_global = true end
        if event == "stop:old-stage" then stopped_stage = true end
    end
    assert_true(stopped_global and stopped_stage, "both global and stage BGM pools are stopped")
    assert_equal(audio.current_music, nil, "starting original BGM clears project track")
    assert_equal(audio.current_original_music, "BGM-YEWAN", "current original BGM is tracked")
    local before_repeat = #events
    assert_true(audio:play_original("BGM-YEWAN"), "same reference BGM continues")
    assert_equal(#events, before_repeat, "same reference BGM does not restart")

    -- Switching back to the menu theme must explicitly stop the tracked
    -- original battle track, even when it is absent from the enumerable pools.
    events = {}
    fake.EnumRes = function() return {}, {} end
    assert_true(audio:play_music("menu"), "menu BGM restarts after a battle")
    local stopped_original = false
    for _, event in ipairs(events) do
        if event == "stop:BGM-YEWAN" then stopped_original = true end
    end
    assert_true(stopped_original, "returning to menu must explicitly stop the tracked original BGM")
    assert_equal(audio.current_original_music, nil, "original BGM tracking is cleared on menu return")
    assert_equal(audio.current_music, "menu", "menu BGM becomes the tracked track")

    _G.LoadMusicRecord = old_record
end
