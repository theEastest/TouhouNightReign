local AudioManager = {}
AudioManager.__index = AudioManager

local SOUNDS = {
    shot = { id = "tnr:plst00", path = "assets/audio/se/se_plst00.wav", volume = 0.35 },
    bomb = { id = "tnr:slash", path = "assets/audio/se/se_slash.wav", volume = 0.8 },
    bomb_focus_power = { id = "tnr:power1", path = "assets/audio/se/se_power1.wav", volume = 0.8 },
    bomb_focus_cat = { id = "tnr:cat00", path = "assets/audio/se/se_cat00.wav", volume = 0.8 },
    bomb_nep = { id = "tnr:nep00", path = "assets/audio/se/se_nep00.wav", volume = 0.8 },
    hit = { id = "tnr:pldead00", path = "assets/audio/se/se_pldead00.wav", volume = 0.55 },
    enemy_hit = { id = "tnr:damage00", path = "assets/audio/se/se_damage00.wav", volume = 0.25 },
    card = { id = "tnr:cardget", path = "assets/audio/se/se_cardget.wav", volume = 0.7 },
}
local MUSIC = {
    -- These are the same recordings and loop points registered by the
    -- reference title/spell-practice scripts. Keeping the loop metadata here
    -- prevents the project menu from drifting into a different cut of the
    -- track.
    menu = { id = "tnr:menu", path = "assets/audio/music/luastg 0.08.540 - 1.27.800.ogg", loop_end = 87.8, loop_length = 79.26 },
    stage = { id = "tnr:stage", path = "assets/audio/music/luastg 0.08.540 - 1.27.800.ogg", loop_end = 87.8, loop_length = 79.26 },
    spellcard = { id = "tnr:spellcard", path = "assets/audio/music/spellcard.ogg", loop_end = 75, loop_length = 0xc36e80 / 44100 / 4 },
}

function AudioManager.new(lstg)
    return setmetatable({
        lstg = lstg,
        loaded = {},
        current_music = nil,
        current_original_music = nil,
    }, AudioManager)
end

local function call(object, method, ...)
    if object and type(object[method]) == "function" then
        return pcall(object[method], ...)
    end
    return false
end

function AudioManager:_with_status(status, callback)
    if not self.lstg or type(callback) ~= "function" then
        return callback and callback() or nil
    end
    local get_status = self.lstg.GetResourceStatus
    local set_status = self.lstg.SetResourceStatus
    local previous
    if type(get_status) == "function" then
        local ok, value = pcall(get_status)
        if ok then previous = value end
    end
    if type(set_status) == "function" and status then
        pcall(set_status, status)
    end
    local ok, result = pcall(callback)
    if type(set_status) == "function" and previous ~= nil then
        pcall(set_status, previous)
    end
    return ok, result
end

function AudioManager:load()
    if not self.lstg or not self.lstg.LoadSound then
        return
    end
    for key, sound in pairs(SOUNDS) do
        local ok = self:_with_status("global", function()
            return self.lstg.LoadSound(sound.id, sound.path)
        end)
        if ok then
            self.loaded[key] = sound
        end
    end
    if self.lstg.LoadMusic then
        for key, music in pairs(MUSIC) do
            local ok = self:_with_status("global", function()
                return self.lstg.LoadMusic(music.id, music.path, music.loop_end or 0, music.loop_length or 0)
            end)
            if ok then
                self.loaded["music:" .. key] = music
            end
        end
    end
end

function AudioManager:play(key, volume, pan)
    local sound = self.loaded[key]
    if sound and self.lstg and self.lstg.PlaySound then
        pcall(self.lstg.PlaySound, sound.id, volume or sound.volume, pan or 0)
    end
end

function AudioManager:play_bomb(focused)
    if focused then
        self:play("bomb_focus_power")
        self:play("bomb_focus_cat")
    else
        self:play("bomb_nep")
        self:play("bomb")
    end
end

function AudioManager:_enum_music()
    if not self.lstg then return {} end
    local enum = self.lstg.EnumRes
    if type(enum) ~= "function" then return {} end
    -- EnumRes returns two lists: global first, then stage.  Original
    -- MusicRecord files are loaded into the global pool so both lists must
    -- be stopped before a new BGM begins.
    local ok, global, stage = pcall(enum, 4)
    if not ok then
        ok, global, stage = pcall(enum, "bgm")
    end
    if not ok then return {} end
    local resources = {}
    for _, pool in ipairs({ global, stage }) do
        if type(pool) == "table" then
            for _, name in pairs(pool) do
                if type(name) == "string" then
                    resources[#resources + 1] = name
                end
            end
        end
    end
    return resources
end

function AudioManager:stop_all_music()
    if not self.lstg then return end
    local stop = self.lstg.StopMusic
    if type(stop) == "function" then
        -- Explicitly stop the two tracks this manager is tracking first. The
        -- native stage BGM is registered as a legacy MusicRecord and may not
        -- appear in the enumerable music pools, so relying on EnumRes alone
        -- can leave the battle track playing after returning to the menu.
        if self.current_original_music then pcall(stop, self.current_original_music) end
        if self.current_music and self.loaded["music:" .. self.current_music] then
            pcall(stop, self.loaded["music:" .. self.current_music].id)
        end
        for _, resource in pairs(self:_enum_music()) do
            pcall(stop, resource)
        end
    end
    self.current_music = nil
    self.current_original_music = nil
end

function AudioManager:_play_raw(id, volume, position)
    if self.lstg and type(self.lstg.PlayMusic) == "function" then
        return pcall(self.lstg.PlayMusic, id, volume or 1.0, position or 0)
    end
    return false
end

function AudioManager:play_music(name)
    local music = self.loaded["music:" .. name]
    if not music then return false end
    self:stop_all_music()
    local ok = self:_play_raw(music.id, 1.0, 0)
    if ok then
        self.current_music = name
        return true
    end
    return false
end

-- Called by the native legacy PlayMusic guard.  The original scripts use
-- both `_play_music` and direct `PlayMusic`; handling both here is what keeps
-- a stage transition from leaving two tracks alive at once.
function AudioManager:play_original(name, volume, position)
    if type(name) ~= "string" or name == "" then return false end
    if self.current_original_music == name then
        -- Consecutive rooms may use the same reference recording. Keep its
        -- playback position instead of restarting it at the room boundary.
        return true
    end
    if type(rawget(_G, "LoadMusicRecord")) == "function" then
        -- Keep imported reference recordings (including their loop points)
        -- intact. The global status prevents a stage reset from evicting the
        -- one track that is intentionally carried into the next room.
        self:_with_status("global", function()
            pcall(LoadMusicRecord, name)
        end)
    end
    if self.lstg and type(self.lstg.CheckRes) == "function" then
        local ok, resource = pcall(self.lstg.CheckRes, 4, name)
        if ok and not resource then
            -- An optional export may name a track whose source file was not
            -- shipped. Keep the already playing track instead of creating a
            -- silent gap (or a second generic replacement).
            return false
        end
    end
    self:stop_all_music()
    local ok = self:_play_raw(name, volume or 1.0, position or 0)
    if ok then
        self.current_original_music = name
        return true
    end
    return false
end

function AudioManager:set_original_volume(name, volume, ...)
    if type(rawget(_G, "LoadMusicRecord")) == "function" and type(name) == "string" then
        self:_with_status("global", function()
            pcall(LoadMusicRecord, name)
        end)
    end
    if self.lstg and type(self.lstg.SetBGMVolume) == "function" then
        return pcall(self.lstg.SetBGMVolume, name, volume, ...)
    end
    return false
end

function AudioManager:continue_music()
    -- The current handle may have been paused by a legacy transition. Do not
    -- select a replacement: preserving the track is the reference behavior
    -- for stages that do not issue a startup PlayMusic command.
    return self.current_music ~= nil or self.current_original_music ~= nil
end

function AudioManager:attach_native()
    _G.__tnr_audio_manager = self
end

return AudioManager
