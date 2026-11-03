local Catalog = require("tnr.equipment.phase1_catalog")
local Instance = require("tnr.equipment.equipment_instance")
local Support = require("tnr.equipment.runtime.support_runtime")
local Projectile = require("tnr.character.runtime.projectile_runtime")
local Session = require("tnr.core.game_session")
return function(eq, yes)
    local session = Session.new({run_seed=451})
    session:start_new()
    local reserved = {}
    for id,d in pairs(Catalog.registry:all()) do
        if d.internal_only or d.starter_only then reserved[id]=d end
    end
    local count=0; for _ in pairs(reserved) do count=count+1 end
    eq(count,12,"six starter and six internal weapon definitions")
    local restricted_registry = {all=function() return reserved end}
    local Shop = require("tnr.shop.shop_service")
    local shop = Shop.new({equipment_registry=restricted_registry,run_seed=2})
    for _,offer in ipairs(shop:open({id="shop",content_seed=5})) do
        yes(offer.kind ~= "EQUIPMENT","reserved-only registry offers no equipment")
    end
    local Reward = require("tnr.reward.reward_service")
    local choices = Reward.new(nil,{equipment_registry=restricted_registry}):generate_choices({encounter_id="test"},4)
    for _,choice in ipairs(choices) do yes(choice.kind ~= "EQUIPMENT","reserved weapons excluded from rewards") end
    for _,character in ipairs({"reimu","marisa","sanae"}) do
        local high=Catalog.registry:get(character.."_initial_high_weapon")
        local low=Catalog.registry:get(character.."_initial_low_weapon")
        eq(high.allowed_slots.LOW_WEAPON,false,"starter high rejects low slot")
        eq(low.allowed_slots.HIGH_WEAPON,false,"starter low rejects high slot")
        eq(low.type,"LOW_WEAPON","UI labels low starter correctly")
        local ok=session.loadout_service:can_equip(Instance.new(high,1),"low_weapons",1,1,true)
        eq(ok,false,"equip service enforces modes")
        local internal=Catalog.registry:get(character.."_support_high_weapon")
        ok=session.loadout_service:can_equip(Instance.new(internal,1),"high_weapons",1,1,true)
        eq(ok,false,"internal attacks cannot be independently equipped")
        local d=Catalog.registry:get(character.."_initial_support")
        local support=Support.new(Instance.new(d,1),d,1)
        local shots=support:fire("HIGH",true,{x=0,y=0,angle=90},Catalog.registry)
        yes(shots[1].metadata.homing,"initial support actually homes: "..character)
        eq(shots[1].targeting,"NEAREST_ENEMY","legacy targeting alias normalized")
        local projectile=Projectile.new(shots[1])
        projectile:update({{x=100,y=100,hp=100,radius=1}},function() return true end)
        yes(projectile.vx>0,"support projectile bends towards off-axis target")
        support.cooldown=0
        shots=support:fire("LOW",true,{x=0,y=0},Catalog.registry)
        eq(shots[1].metadata.homing,false,"low support remains straight")
    end
    for _,id in ipairs({"support_hakurei_yinyang_orb","support_marisa_orreries_sun","support_sanae_snakeskin_amulet"}) do
        local d=Catalog.registry:get(id)
        local support=Support.new(Instance.new(d,1),d,1)
        local function damage()
            support.cooldown=0
            local sum=0
            for _,shot in ipairs(support:fire("HIGH",true,{},Catalog.registry)) do sum=sum+shot.damage end
            return sum
        end
        local original=damage()
        yes(math.abs(original-d.metadata.high_damage)<1e-8,"formation damage is normalized")
        support.entities[#support.entities+1]={x=0,y=0}
        yes(math.abs(damage()-original)<1e-8,"extra entity does not multiply formation damage")
    end
    local function turn(ratio)
        local p=Projectile.new({x=0,y=0,angle=90,speed=10,damage=1,
            metadata={homing=true,homing_turn_rate=0.04,homing_turn_ratio=ratio}})
        p:update({{x=100,y=100,hp=100,radius=1}},function() return true end)
        return math.pi/2-p.angle
    end
    yes(math.abs(turn(0.5)*2-turn(1))<1e-8,"weak homing ratio changes actual trajectory")
end
