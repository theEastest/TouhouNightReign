-- TH15 v1.00b executable, not the stale SHT header defaults.
-- See docs/th15-reference-audit.md for addresses and extraction procedure.
local Rules={
    players = {
        reimu={hitbox=2, attract_speed=5, collect_line=128},
        marisa={hitbox=3, attract_speed=6, collect_line=148},
        sanae={hitbox=3, attract_speed=5, collect_line=128},
        reisen={hitbox=3, attract_speed=5, collect_line=128},
    },
    pickup_half=15, attract_half=30, focus_attract_half=50,
    graze_range=40, graze_drop_frames=45, graze_interval=60,
    graze_interval_after_drop=30,
    fall_accel=0.03, fall_max=2, attract_accel=0.2, attract_max=12,
    -- TH15 stores one global item-speed multiplier. A graze sets it to 0.3;
    -- ItemManager::on_tick__body recovers it by 0.1 after updating all items.
    graze_slowdown=0.3, slowdown_recovery=0.1,
}

local function float32(value)
    local fraction, exponent = math.frexp(math.abs(value))
    local significand = fraction * 0x1000000
    local whole = math.floor(significand)
    local remainder = significand - whole
    if remainder > 0.5 or (remainder == 0.5 and whole % 2 == 1) then
        whole = whole + 1
    end
    return math.ldexp(value < 0 and -whole or whole, exponent - 24)
end

if string.pack then
    float32 = function(value)
        return (string.unpack("<f", string.pack("<f", value)))
    end
end

Rules.float32 = float32

function Rules.normalize_angle(value)
    -- 403920 keeps both endpoints and rounds each subtraction to float32.
    local angle=float32(value)
    local pi,tau=float32(math.pi),float32(math.pi*2)
    for _=1,34 do
        if angle>pi then angle=float32(angle-tau)
        elseif angle< -pi then angle=float32(angle+tau)
        else break end
    end
    return angle
end

function Rules.motion_coordinate(value)
    -- 40443d..4044b6 multiplies the single-precision position by 100,
    -- floors it, and converts it back to a single-precision position.
    return float32(math.floor(float32(float32(value) * 100)) / 100)
end

function Rules.point_score(rate,player_y,collect_line,auto_collect)
    -- 4405c0..4406f5. Internal maximum-point units are 100x the displayed
    -- value; score awards round down to tens after the height calculation.
    local full=math.floor(rate/10)*10
    if auto_collect or player_y<=collect_line then return math.max(10,full) end
    local base=math.floor(full*3/4)
    local delta=math.modf(-base*(math.floor(player_y)-collect_line)/450)
    return math.max(10,math.floor((base+delta)/10)*10)
end
return Rules
