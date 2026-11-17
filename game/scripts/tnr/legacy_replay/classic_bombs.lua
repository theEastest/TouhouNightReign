-- Character Bomb routines in TH15 1.00b. ANM scripts come from pl00..pl03.
local Bombs = {}
local BulletTypes = require("tnr.legacy_replay.data.th15_bullet_types")
local Laser = require("tnr.legacy_replay.laser")
local Rules = require("tnr.legacy_replay.reference_rules")
local atan2 = math.atan2 or math.atan
local f32 = Rules.float32

local function circle(x, y, radius)
    return {x=x, y=y, radius=radius}
end

local function rectangle(x, y, angle, width, height)
    return {x=x, y=y, cos=math.cos(angle), sin=math.sin(angle), hw=width/2, hh=height/2}
end

local function local_point(area, x, y)
    local dx, dy = x-area.x, y-area.y
    return dx*area.cos+dy*area.sin, dy*area.cos-dx*area.sin
end

local function inside(area, x, y, pad)
    if area.radius then
        return (x-area.x)^2+(y-area.y)^2 <= (area.radius+pad)^2
    end
    local u,v = local_point(area,x,y)
    local dx = math.max(0, math.abs(u)-area.hw)
    local dy = math.max(0, math.abs(v)-area.hh)
    return dx*dx+dy*dy <= pad*pad
end

local function clip_axis(a, b, half, first, last)
    local delta = b-a
    if delta == 0 then
        if math.abs(a) <= half then return first,last end
        return 1,0
    end
    local enter, leave = (-half-a)/delta, (half-a)/delta
    return math.max(first,math.min(enter,leave)), math.min(last,math.max(enter,leave))
end

local function laser_overlaps(shot, area)
    local hit = false
    local half_width = (shot.draw_width or shot.width or 0)/2
    Laser.segments(shot,function(x1,y1,x2,y2)
        if hit then return end
        if area.radius then
            local dx,dy = x2-x1,y2-y1
            local length2 = dx*dx+dy*dy
            local t = length2 > 0 and ((area.x-x1)*dx+(area.y-y1)*dy)/length2 or 0
            t = math.max(0,math.min(1,t))
            hit = inside(area,x1+t*dx,y1+t*dy,half_width)
        else
            local u1,v1 = local_point(area,x1,y1)
            local u2,v2 = local_point(area,x2,y2)
            local first,last = clip_axis(u1,u2,area.hw+half_width,0,1)
            first,last = clip_axis(v1,v2,area.hh+half_width,first,last)
            hit = first <= last
        end
    end)
    return hit
end

local function cancel(stage, player, area, drops)
    local adapter = stage.adapter
    local pieces={}
    local function emit(x,y)
        if drops and math.abs(x)<224 and y> -32 and y<480 then
            stage.items:spawn_launched("cancel",x,y,player.player_id)
        end
    end
    for index=#adapter.shots,1,-1 do
        local shot=adapter.shots[index]
        local contact = false
        if not shot.player_bullet and not shot.laser and not shot.deleted and (shot.bomb_invulnerable or 0) <= 0 then
            local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
            local size = descriptor and descriptor.radius or 0
            -- 41e750 uses half the descriptor size; 41e850 uses its
            -- scaled size when checking the Master Spark rectangle.
            local padding = area.radius and size/2 or size*(shot.scale or 1)
            contact = inside(area,shot.x,shot.y,padding)
        end
        if contact then
            emit(shot.x,shot.y)
            adapter:cancel_bullet(shot)
        end
    end
    for index=#adapter.shots,1,-1 do
        local shot=adapter.shots[index]
        if shot.laser and not shot.deleted and (shot.bomb_invulnerable or 0)<=0 and laser_overlaps(shot,area) then
            local remaining=Laser.cancel_in_shape(shot,function(x,y) return inside(area,x,y,0) end,emit,
                function(x,y,source)
                    local script=Laser.cancel_effect_script(source)
                    if script then adapter:spawn_animation("bullet",script,x,y) end
                end)
            if shot.deleted then for _,piece in ipairs(remaining) do pieces[#pieces+1]=piece end end
        end
    end
    local kept={}
    for _,shot in ipairs(adapter.shots) do if not shot.deleted then kept[#kept+1]=shot end end
    for _,piece in ipairs(pieces) do kept[#kept+1]=piece end
    adapter.shots = kept
end

local function damage_overlaps(area, enemy)
    local box = enemy.legacy_hurtbox
    local hw,hh = 24,24
    if box then hw,hh = box[1]/2,box[2]/2 end
    if hw <= 0 or hh <= 0 then return false end
    if area.radius then
        local dx = math.max(0,math.abs(enemy.x-area.x)-hw)
        local dy = math.max(0,math.abs(enemy.y-area.y)-hh)
        return dx*dx+dy*dy <= area.radius^2
    end
    local dx,dy = math.abs(enemy.x-area.x),math.abs(enemy.y-area.y)
    local c,s = math.abs(area.cos),math.abs(area.sin)
    if dx > hw+area.hw*c+area.hh*s or dy > hh+area.hw*s+area.hh*c then return false end
    local u,v = local_point(area,enemy.x,enemy.y)
    return math.abs(u) <= area.hw+hw*c+hh*s and math.abs(v) <= area.hh+hw*s+hh*c
end

local function damage(stage, player, area, amount)
    for _,enemy in ipairs(stage.adapter.enemies) do
        if enemy.hp and enemy.hp>0 and not enemy.legacy_deleted and not enemy.legacy_no_damage
            and (enemy.legacy_invulnerable_until or 0)<=(stage.adapter.frame or 0) and damage_overlaps(area,enemy) then
            stage:damage_classic_enemy(player.player_id,enemy,amount)
        end
    end
end

local function place(vm, x, y)
    if vm then vm.origin_x,vm.origin_y = x,y end
end

local function interrupt(vm, label)
    if not vm or vm.finished then return end
    vm:interrupt(label)
    for _,child in ipairs(vm.children) do interrupt(child,label) end
end

local function animation(stage, p, script, x, y)
    return stage.adapter:spawn_animation(p.archive,script,x,y)
end

function Bombs.begin(stage, player)
    local b = {kind=player.archive, age=0, x=player.x, y=player.y}
    player.classic_bomb = b
    stage:play_sound(44)
    if b.kind == "pl03" then
        -- 417730: three barriers and a wave centered at the casting point.
        b.layers = 3
        b.main = animation(stage,player,10,b.x,b.y)
        b.flash = animation(stage,player,17,b.x,b.y)
        player.invulnerable = 30
    elseif b.kind == "pl01" then
        -- 414c60: the ANM's forward axis is local +X.
        b.angle = f32(-math.pi/2)
        b.main = animation(stage,player,16,b.x,b.y)
        b.flash = animation(stage,player,24,b.x,b.y)
        stage:play_sound(49)
    elseif b.kind == "pl02" then
        b.main = animation(stage,player,16,b.x,b.y)
        b.flash = animation(stage,player,20,b.x,b.y)
        stage:play_sound(30)
    else
        b.main = animation(stage,player,24,b.x,b.y)
        b.orbs = {}
        for index=1,8 do
            b.orbs[index] = {x=b.x,y=b.y,angle=f32((index-1)*math.pi/4),radius=0,
                speed=0,dx=0,dy=0,vm=animation(stage,player,16,b.x,b.y)}
        end
    end
end

function Bombs.master_spark(player)
    local b = player.classic_bomb
    return b and b.kind=="pl01" and b.age<=300
end

local function update_marisa(stage, p, b, drops)
    b.x,b.y = p.x,p.y
    place(b.main,b.x,b.y)
    place(b.flash,b.x,b.y)
    if b.main then b.main.child_rotation = b.angle end
    if b.age == 300 then
        interrupt(b.main,1)
        interrupt(b.flash,1)
    end
    if b.age > 300 then return not b.main or b.main.finished end
    local vx = p.move_velocity_x or 0
    if vx ~= 0 then
        local turn = vx < 0 and -0.0026179938577115536 or 0.0026179938577115536
        b.angle = f32(b.angle+turn)
    end
    local c,s = math.cos(b.angle),math.sin(b.angle)
    if b.age%3 == 0 then
        -- 4150c8..41524a: overlapping sources taper outside the core.
        damage(stage,p,rectangle(b.x+c*208,b.y+s*208,b.angle,512,32),60)
        damage(stage,p,rectangle(b.x+c*240,b.y+s*240,b.angle,512,128),20)
        damage(stage,p,rectangle(b.x+c*304,b.y+s*304,b.angle,512,256),20)
    end
    for _,vm in ipairs(b.main and b.main.children or {}) do
        if vm.script==23 and vm.scale_x>0 and vm.scale_y>0 then
            local ca,sa = math.cos(b.main.child_rotation),math.sin(b.main.child_rotation)
            local x,y = b.x+ca*vm.x-sa*vm.y,b.y+sa*vm.x+ca*vm.y
            cancel(stage,p,rectangle(x,y,b.angle,48*vm.scale_x,160*vm.scale_y),drops)
        end
    end
    return false
end

local function update_sanae(stage, p, b, drops)
    local age = b.age
    if age >= 280 then
        interrupt(b.flash,1)
        return true
    end
    if age == 180 then stage:play_sound(6) end
    -- 418533..418665 draws two positions from the gameplay RNG per
    -- tick of the small burst emitters, independently of the ANM RNG.
    if age >= 30 then
        stage.adapter.random(-1,1)
        stage.adapter.random(0,1)
    end
    if age < 180 then
        damage(stage,p,circle(b.x,b.y,16+age*0.35555556416511536),13)
        cancel(stage,p,circle(b.x,b.y,16+age*48/180),drops)
    else
        local elapsed = age-180
        damage(stage,p,circle(b.x,b.y,80+elapsed*20),80)
        cancel(stage,p,circle(b.x,b.y,math.min(480,64+elapsed*416/20)),drops)
    end
    return false
end

local function wrap(angle)
    return (angle+math.pi)%(2*math.pi)-math.pi
end

local function nearest(enemies, orb)
    local target, best = nil, 512^2
    for _,e in ipairs(enemies) do
        if (e.hp or 0)>0 and not e.legacy_deleted and not e.legacy_no_damage then
            local d = (e.x-orb.x)^2+(e.y-orb.y)^2
            if d<best then target,best=e,d end
        end
    end
    return target
end

local function move_orb(stage, p, orb, age, release)
    local x,y = orb.x,orb.y
    if age < release then
        if age < 90 then orb.radius = orb.radius+1.5 end
        orb.angle = f32(wrap(orb.angle+0.10471975803375244))
        x,y = p.x+math.cos(orb.angle)*orb.radius,p.y+math.sin(orb.angle)*orb.radius
    else
        if age == release then
            orb.angle = f32(atan2(orb.dy,orb.dx))
            orb.speed = f32(math.sqrt(orb.dx^2+orb.dy^2))
        else
            local e = nearest(stage.adapter.enemies,orb)
            if e then
                local delta = wrap(atan2(e.y-y,e.x-x)-orb.angle)
                if math.abs(delta)>=math.pi/4 then orb.speed=math.max(1,orb.speed-0.7)
                elseif math.abs(delta)<math.pi/12 then orb.speed=math.min(8,orb.speed+0.2) end
                orb.angle = f32(wrap(orb.angle+delta*.1))
            elseif math.abs(x)>160 or y<32 or y>416 then orb.speed=orb.speed*.9 end
        end
        x,y = x+math.cos(orb.angle)*orb.speed,y+math.sin(orb.angle)*orb.speed
    end
    x,y = Rules.motion_coordinate(x),Rules.motion_coordinate(y)
    orb.dx,orb.dy = x-orb.x,y-orb.y
    orb.x,orb.y = x,y
    place(orb.vm,x,y)
end

local function update_reimu(stage, p, b, drops)
    place(b.main,p.x,p.y)
    if b.age < 200 then
        for index,orb in ipairs(b.orbs) do
            move_orb(stage,p,orb,b.age,80+10*index)
            if b.age%3==0 then damage(stage,p,circle(orb.x,orb.y,56),15) end
        end
        local orb = b.orbs[b.age%8+1]
        cancel(stage,p,circle(orb.x,orb.y,64),drops)
    elseif b.age == 200 then
        stage:play_sound(27)
        for _,orb in ipairs(b.orbs) do
            cancel(stage,p,circle(orb.x,orb.y,128),true)
            interrupt(orb.vm,1)
        end
        interrupt(b.main,1)
        -- 4164a0 leaves an expanding damage source at each detonation.
        stage.classic_blasts = stage.classic_blasts or {}
        stage.classic_blasts[#stage.classic_blasts+1] = {player_id=p.player_id,age=0,orbs=b.orbs}
    end
    return b.age >= 250
end

function Bombs.update_blasts(stage)
    if not stage.classic_blasts then return end
    local remaining = {}
    for _,blast in ipairs(stage.classic_blasts) do
        local p = stage.players[blast.player_id]
        for _,orb in ipairs(blast.orbs) do
            damage(stage,p,circle(orb.x,orb.y,64+blast.age*8),11)
        end
        blast.age = blast.age+1
        if blast.age<100 then remaining[#remaining+1] = blast end
    end
    stage.classic_blasts = remaining
end

local function update_reisen(stage, p, b, drops)
    place(b.main,p.x,p.y)
    if b.age <= 30 then
        cancel(stage,p,circle(b.x,b.y,b.age*4),drops)
        if b.age==30 then stage:play_sound(54) end
    else
        p.hitbox = 3+1.5*b.layers
        p.hitbox_half = p.hitbox/2
    end
end

function Bombs.absorb(stage, p)
    local b = p.classic_bomb
    if not b or not b.layers then return false end
    p.invulnerable = 30
    b.layers,b.age,b.x,b.y = b.layers-1,0,p.x,p.y
    interrupt(b.main,7+b.layers)
    cancel(stage,p,circle(b.x,b.y,64),not stage.adapter.spell_active)
    if b.layers == 0 then
        p.hitbox,p.hitbox_half = 3,1.5
        interrupt(b.flash,1)
        p.classic_bomb = nil
    end
    return true
end

local update = {pl00=update_reimu,pl01=update_marisa,pl02=update_sanae,pl03=update_reisen}

function Bombs.update(stage, p)
    local b = p.classic_bomb
    if not b then return end
    if b.kind~="pl03" then p.invulnerable=40 end
    if update[b.kind](stage,p,b,not stage.adapter.spell_active) then p.classic_bomb=nil end
    b.age = b.age+1
end

return Bombs
