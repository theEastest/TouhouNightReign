local BattleManager = require("tnr.battle.battle_manager")
local StageDefinitions = require("tnr.stages.definitions")

local StageAdapter = {}
StageAdapter.__index = StageAdapter

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function distance_squared(left, right)
    local dx = left.x - right.x
    local dy = left.y - right.y
    return dx * dx + dy * dy
end

function StageAdapter.new(session, stage_api, lstg)
    return setmetatable({
        session = session,
        stage_api = stage_api,
        lstg = lstg,
        battle = BattleManager.new(session),
        active_encounter = nil,
        runtime = nil,
    }, StageAdapter)
end

function StageAdapter:start(encounter)
    self.active_encounter = encounter
    self.battle:begin(encounter)
    if self.stage_api and self.stage_api.Set then
        self.stage_api.Set(encounter.stage_id)
        return true
    end
    self.runtime = {
        frame = 0,
        wave_index = 0,
        wave_wait = 0,
        enemies = {},
        bullets = {},
        player_bullets = {},
        player = { x = 640, y = 100, speed = 5, shoot_cooldown = 0, invulnerable = 0 },
        kill_requested = false,
        bomb_flash = 0,
    }
    self:_spawn_next_wave()
    return false
end

function StageAdapter:is_fallback_active()
    return self.runtime ~= nil
end

function StageAdapter:_spawn_next_wave()
    local runtime = self.runtime
    if not runtime then
        return
    end
    local definition = StageDefinitions[self.active_encounter.stage_id]
    if not definition then
        return
    end
    runtime.wave_index = runtime.wave_index + 1
    local count = definition.waves and definition.waves[runtime.wave_index]
    if count then
        for index = 1, count do
            local hp = 20 + runtime.wave_index * 10
            runtime.enemies[#runtime.enemies + 1] = {
                x = 180 + index * (920 / (count + 1)),
                y = 610,
                hp = hp,
                max_hp = hp,
                fire_timer = 30 + index * 12,
                radius = 18,
            }
        end
        return
    end
    if definition.nonspell_count and runtime.wave_index == 1 then
        runtime.enemies[#runtime.enemies + 1] = {
            x = 640, y = 610, hp = 420, max_hp = 420, fire_timer = 30, radius = 42, boss = true, phase = "NON_SPELL",
        }
    elseif definition.spell_count and runtime.wave_index == 2 then
        runtime.enemies[#runtime.enemies + 1] = {
            x = 640, y = 610, hp = 520, max_hp = 520, fire_timer = 20, radius = 44, boss = true, phase = "SPELL",
        }
    end
end

function StageAdapter:_finish(clear_state, options)
    if not self.runtime then
        return
    end
    self.runtime = nil
    self:complete(clear_state, options)
end

function StageAdapter:update(input)
    local runtime = self.runtime
    if not runtime then
        return
    end
    runtime.frame = runtime.frame + 1
    local player = runtime.player
    input = input or {}
    player.x = clamp(player.x + (input.move_x or 0) * player.speed, 40, 1240)
    player.y = clamp(player.y + (input.move_y or 0) * player.speed, 40, 680)
    player.invulnerable = math.max(0, player.invulnerable - 1)

    if input.bomb and self.session:get_player(1).bomb > 0 then
        self.battle:use_bomb(1)
        runtime.bomb_flash = 20
        runtime.bullets = {}
        for _, enemy in ipairs(runtime.enemies) do
            enemy.hp = enemy.hp - 80
        end
    end
    runtime.bomb_flash = math.max(0, runtime.bomb_flash - 1)

    if input.shoot and player.shoot_cooldown <= 0 then
        runtime.player_bullets[#runtime.player_bullets + 1] = { x = player.x, y = player.y + 16, speed = 12, damage = 5 }
        player.shoot_cooldown = 5
    end
    player.shoot_cooldown = math.max(0, player.shoot_cooldown - 1)

    if runtime.kill_requested then
        for _, enemy in ipairs(runtime.enemies) do
            enemy.hp = 0
        end
        runtime.kill_requested = false
    end

    for index = #runtime.player_bullets, 1, -1 do
        local bullet = runtime.player_bullets[index]
        bullet.y = bullet.y + bullet.speed
        local hit = false
        for _, enemy in ipairs(runtime.enemies) do
            if enemy.hp > 0 and distance_squared(bullet, enemy) <= (enemy.radius + 5) ^ 2 then
                enemy.hp = enemy.hp - bullet.damage
                self.battle:add_score(100, 1, "shot")
                hit = true
                break
            end
        end
        if hit or bullet.y > 740 then
            table.remove(runtime.player_bullets, index)
        end
    end

    for _, enemy in ipairs(runtime.enemies) do
        if enemy.hp > 0 then
            enemy.y = 610 + math.sin((runtime.frame + enemy.x) * 0.02) * 20
            enemy.fire_timer = enemy.fire_timer - 1
            if enemy.fire_timer <= 0 then
                runtime.bullets[#runtime.bullets + 1] = {
                    x = enemy.x,
                    y = enemy.y - enemy.radius,
                    speed = enemy.boss and 3 or 4,
                    radius = enemy.boss and 7 or 5,
                }
                enemy.fire_timer = enemy.boss and 24 or 55
            end
        end
    end

    for index = #runtime.bullets, 1, -1 do
        local bullet = runtime.bullets[index]
        bullet.y = bullet.y - bullet.speed
        if player.invulnerable == 0 and distance_squared(bullet, player) <= (bullet.radius + 8) ^ 2 then
            player.invulnerable = 90
            self.battle:record_life_lost(1)
            self.session:add_life(1, -1, "hit")
            table.remove(runtime.bullets, index)
            if self.session:get_player(1).life <= 0 then
                self:_finish(false, { reward_eligible = false })
                return
            end
        elseif bullet.y < -20 then
            table.remove(runtime.bullets, index)
        end
    end

    for index = #runtime.enemies, 1, -1 do
        if runtime.enemies[index].hp <= 0 then
            self.battle:collect_money(runtime.enemies[index].boss and 25 or 2, 1, "enemy_drop")
            table.remove(runtime.enemies, index)
        end
    end

    if #runtime.enemies == 0 then
        local definition = StageDefinitions[self.active_encounter.stage_id]
        local total_waves = definition and (definition.waves and #definition.waves or 2) or 0
        if runtime.wave_index < total_waves then
            runtime.wave_wait = runtime.wave_wait + 1
            if runtime.wave_wait >= 45 then
                runtime.wave_wait = 0
                self:_spawn_next_wave()
            end
        else
            self:_finish(true, { reward_eligible = true })
        end
    end
end

function StageAdapter:render()
    local runtime = self.runtime
    local lstg = self.lstg
    if not runtime or not lstg then
        return
    end
    lstg.BeginScene()
    lstg.RenderClear(lstg.Color(255, 9, 12, 28))
    lstg.SetViewport(0, 1280, 0, 720)
    lstg.SetScissorRect(0, 1280, 0, 720)
    lstg.SetOrtho(0, 1280, 0, 720)
    local image = "tnr-white"
    local player_state = self.session:get_player(1)
    lstg.SetImageState(image, "", lstg.Color(255, 110, 220, 255))
    if runtime.player.invulnerable % 6 < 3 then
        lstg.RenderRect(image, runtime.player.x - 8, runtime.player.x + 8, runtime.player.y - 8, runtime.player.y + 8)
    end
    for _, bullet in ipairs(runtime.player_bullets) do
        lstg.SetImageState(image, "", lstg.Color(255, 120, 255, 160))
        lstg.RenderRect(image, bullet.x - 3, bullet.x + 3, bullet.y - 10, bullet.y + 10)
    end
    for _, bullet in ipairs(runtime.bullets) do
        lstg.SetImageState(image, "", lstg.Color(255, 255, 80, 90))
        lstg.RenderRect(image, bullet.x - bullet.radius, bullet.x + bullet.radius, bullet.y - bullet.radius, bullet.y + bullet.radius)
    end
    for _, enemy in ipairs(runtime.enemies) do
        lstg.SetImageState(image, "", enemy.boss and lstg.Color(255, 220, 80, 100) or lstg.Color(255, 255, 170, 80))
        lstg.RenderRect(image, enemy.x - enemy.radius, enemy.x + enemy.radius, enemy.y - enemy.radius, enemy.y + enemy.radius)
    end
    lstg.RenderTTF("Sans", string.format("Battle Score %d   Money %d   Life %d   Bomb %d", self.battle.active.battle_score, player_state.money, player_state.life, player_state.bomb), 40, 40, 680, 680, 0, lstg.Color(255, 240, 240, 240), 2)
    lstg.RenderTTF("Sans", "Z: 射击   X: Bomb   Shift: 低速   方向键: 移动", 40, 40, 30, 30, 0, lstg.Color(255, 220, 220, 220), 1.5)
    if runtime.bomb_flash > 0 then
        lstg.RenderTTF("Sans", "BOMB", 640, 640, 360, 360, 1 + 4, lstg.Color(255, 255, 255, 255), 4)
    end
    lstg.EndScene()
end

function StageAdapter:get_battle_manager()
    return self.battle
end

function StageAdapter:complete(clear_state, options)
    return self.battle:complete(clear_state, options)
end

function StageAdapter:kill_all()
    if self.runtime then
        self.runtime.kill_requested = true
        return true
    end
    if self.stage_api and self.stage_api.kill_all then
        return self.stage_api.kill_all()
    end
    return false
end

return StageAdapter
