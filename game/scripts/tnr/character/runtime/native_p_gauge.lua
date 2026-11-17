local Native = {}
local rain_class, copy_class
local hud_font_loaded = false
local smoke = os.getenv("TNR_P_GAUGE_SMOKE") == "1" and require("tnr.debug.p_gauge_smoke") or nil
local function valid(o) return o and IsValid(o) end
local attributes = { "img", "a", "b", "rect", "colli", "hscale", "vscale", "rot", "omiga",
    "layer", "color", "_blend", "_a", "_r", "_g", "_b", "_index", "imgclass", "damage" }
local function classes()
    if rain_class then return end
    rain_class = Class(object)
    function rain_class:init(x, y, speed)
        self.x, self.y, self.vx, self.vy = x, y, 0, -speed
        self.group, self.layer, self.img = GROUP_ENEMY_BULLET, LAYER_ENEMY_BULLET, "ball_small1"
        self.a, self.b, self.hscale, self.vscale = 2, 2, 0.5, 0.5
        self._p_hazard = "rain"
    end
    function rain_class:render()
        SetImageState(self.img, "", Color(255, 255, 255, 255))
        object.render(self)
        SetImageState(self.img, "", Color(255, 255, 255, 255))
    end
    copy_class = Class(object)
    function copy_class:init(source)
        self.source = source
        self.x, self.y, self.group = source.x, source.y, source.group
        self.source_x, self.source_y = source.x, source.y
        self.vx, self.vy = source.vx or 0, -(source.vy or 0)
        self._p_duplicate = true
        self._p_hazard = "copy"
        for _, key in ipairs(attributes) do if source[key] ~= nil then self[key] = source[key] end end
    end
    function copy_class:frame()
        local source = self.source
        if valid(source) then
            -- Follow all scripted acceleration/turns while reflecting vertical motion.
            -- Engine motion is applied after frame(), as it is for the source bullet.
            self.vx, self.vy = source.vx or 0, -(source.vy or 0)
            for _, key in ipairs(attributes) do if source[key] ~= nil then self[key] = source[key] end end
        end
    end
    function copy_class:render()
        if self.imgclass and self.imgclass.render then self.imgclass.render(self)
        else object.render(self) end
    end
    if lstg.RegisterGameObjectClass then
        lstg.RegisterGameObjectClass(rain_class)
        lstg.RegisterGameObjectClass(copy_class)
    end
end
function Native.update(driver, player, context)
    local gauge = driver.p_gauge
    if not gauge then return end
    classes()
    if smoke then smoke.update(driver, player) end
    if driver.pending_p_hazard then
        gauge.event = driver.pending_p_hazard
        driver.pending_p_hazard = nil
    end
    if gauge.event then
        -- One stage-wide negative effect at a time, including co-op triggers.
        if Native.active and Native.active.gauge ~= gauge then Native.active.gauge.hazard_frames = 0 end
        Native.active = { gauge = gauge, owner = driver.player_id, kind = gauge.event }
        for _, group in ipairs({ GROUP_ENEMY_BULLET, GROUP_INDES }) do
            for _, b in ObjList(group) do if b._p_hazard then Del(b) end end
        end
    end
    local active = Native.active and Native.active.gauge == gauge
    if active and gauge.hazard_frames == 0 and Native.active.kind == 1 then
        for _, b in ObjList(GROUP_ENEMY_BULLET) do if b._p_hazard == "rain" then Del(b) end end
    end
    if gauge.event == 2 then
        local sources = {}
        for _, group in ipairs({ GROUP_ENEMY_BULLET, GROUP_INDES }) do
            if group then
                for _, b in ObjList(group) do
                    if valid(b) and not b._p_duplicate and not b._p_hazard then sources[#sources + 1] = b end
                end
            end
        end
        if smoke then driver.p_smoke_sources = #sources end
        for _, b in ipairs(sources) do
            local copy = New(copy_class, b)
            if smoke then
                assert(copy.vx == b.vx and copy.vy == -b.vy, "copy velocity mismatch")
                assert(copy.a == b.a and copy.b == b.b and copy.img == b.img, "copy properties mismatch")
                driver.p_smoke_copies = (driver.p_smoke_copies or 0) + 1
            end
        end
    end
    if active and gauge.hazard == 1 and gauge.hazard_frames > 0 and gauge.frame % 3 == 0 then
        local world = lstg.world
        local left, right = world.l or -192, world.r or 192
        local top = world.t or 224
        for _ = 1, 4 do
            local x = left + driver.p_rng:next_float() * (right - left)
            New(rain_class, x, top - 1, 2 + driver.p_rng:next_float() * 2)
        end
    end
end
local function rect(color, left, right, bottom, top)
    SetImageState("tnr-white", "", color)
    RenderRect("tnr-white", left, right, bottom, top)
    SetImageState("tnr-white", "", Color(255, 255, 255, 255))
end
function Native.render_world(driver, player)
    SetViewMode("world")
    local gauge = driver.p_gauge
    if not gauge then return end
    if gauge.resting then
        for i = 1, 24 do
            local angle = math.rad(i * 15 + gauge.frame * 3)
            local x, y = player.x + math.cos(angle) * 24, player.y + math.sin(angle) * 24
            rect(Color(200, 255, 45, 70), x - 1.5, x + 1.5, y - 1.5, y + 1.5)
        end
    end
    if driver.affixes then require("tnr.character.runtime.status_art").ring(driver.affixes,player) end
    if Native.active and Native.active.gauge == gauge and gauge.hazard == 3 and gauge.hazard_frames > 0 then
        require("tnr.character.runtime.vision_mask").render(_G, player.x, player.y)
    end
end
function Native.render_hud(driver)
    if not driver or not driver.p_gauge then return end
    local g = driver.p_gauge
    if not hud_font_loaded then
        local previous = lstg.GetResourceStatus()
        lstg.SetResourceStatus("global")
        lstg.LoadTTF("tnr-p-hud", "assets/font/SourceHanSansCN-Bold.otf", 28, 28)
        lstg.LoadTTF("tnr-status-small", "assets/font/SourceHanSansCN-Bold.otf", 16, 16)
        lstg.SetResourceStatus(previous)
        hud_font_loaded = true
    end
    SetViewMode("ui")
    local right = (screen and screen.width or 640) - 14
    local left, y = right - 180, 230
    rect(Color(220, 25, 24, 40), left, right, y, y + 12)
    rect(Color(255, 230, 50, 85), left, left + 180 * g.value / g.maximum, y, y + 12)
    rect(Color(255, 255, 230, 200), left + 180 * 30/g.maximum - 1, left + 180 * 30/g.maximum + 1, y - 2, y + 14)
    RenderTTF("tnr-p-hud", string.format("P %.1f / %.0f%%", g.value, g.maximum), left, right, y + 18, y + 18,
        Color(255, 255, 230, 230), "left", "vcenter", "noclip")
    rect(Color(255,110,210,255),left+180*0.9-1,left+180*0.9+1,y-2,y+14)
    -- Fixed 30-point threshold; high threshold is 90% of current capacity.
    local art=require("tnr.character.runtime.status_art")
    art.icon(13,left+8,y-20,20,"ordinary")
    RenderTTF("tnr-p-hud", "渴血兽", left + 20, left + 76, y - 20, y - 20,
        Color(255, 255, 220, 220), "left", "vcenter", "noclip")
    RenderTTF("tnr-p-hud", string.format("%.0f%%", g.progress/g.progress_maximum*100), left + 80, right,
        y - 20, y - 20, Color(255, 255, 190, 180), "left", "vcenter", "noclip")
    rect(Color(200,35,15,25),left,right,y-36,y-33)
    rect(Color(255,210,35,65),left,left+(right-left)*math.min(1,g.progress/g.progress_maximum),y-36,y-33)
    local rows=driver.affixes and driver.affixes:statuses() or {}
    art.grid(rows,left,y-55,180,driver.affixes,function(text,x,cy)
        RenderTTF("tnr-status-small",text,x-25,x,cy,cy,Color(255,255,255,255),"right","vcenter","noclip")
    end,"ordinary")
    SetViewMode("world")
end
function Native.sync(driver, snapshot)
    if snapshot.triggers and snapshot.triggers > driver.p_gauge.triggers and (snapshot.hazard_frames or 0) > 0 then
        driver.pending_p_hazard = snapshot.hazard
    end
    driver.p_gauge:apply_snapshot(snapshot)
end
function Native.reset() Native.active = nil end
return Native
