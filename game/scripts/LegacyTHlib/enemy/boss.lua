---@class boss
boss = Class(enemybase)
local boss = boss
boss.record = {}

function boss:init(x, y, name, cards, bg, diff)
    enemybase.init(self, 999999999)
    self.x, self.y = x, y
    self.img = "undefined"
    --boss系统
    self._bosssys = boss.system(self, name, cards, bg, diff)
    --boss行走图系统
    self._wisys = BossWalkImageSystem(self)
    self._wisys:SetFloat(function(ani)
        return 0, 4 * sin(ani * 4)
    end)
    lstg.tmpvar.boss = self
    _boss = self
end
function boss:frame()
    self._bosssys:frame() --boss系统帧逻辑
    self._wisys:frame() --行走图系统帧逻辑
    --受击闪烁
    if self.dmgt then
        self.dmgt = max(0, self.dmgt - 1)
    end
end
function boss:render()
    self._bosssys:render() --boss系统渲染
    self._wisys:render(self.dmgt, self.dmgmaxt) --行走图渲染
end
function boss:kill()
    self._bosssys:kill() --boss系统kill
end
function boss:del()
    self._bosssys:del() --boss系统del
end
function boss:take_damage(dmg)
    if self.dmgmaxt then
        self.dmgt = self.dmgmaxt
    end
    if not self.protect then
        local dmg0 = dmg * self.dmg_factor * self.DMG_factor
        self.spell_damage = self.spell_damage + dmg0
        self.hp = self.hp - dmg0
        lstg.var.score = lstg.var.score + 10
    end
end
function boss:show_aura(show)
    if show then
        self.aura_alpha_d = 4
    else
        self.aura_alpha_d = -4
    end
end
function boss:cast(cast_t)
    self.cast_t = cast_t + 0.5
    self.cast = 1
end

local function new_scbg(scbg)
    local t = type(scbg)
    local obj
    if t == "string" then
        obj = New(_editor_class[scbg])
    elseif scbg then
        obj = New(scbg)
    else
        obj = New(default_spellcard_background)
    end
    return obj
end

function boss.define(id, name, x, y, scbg, diff, bgm, bg, img, nCol, nRow, a, b, intv, imgs, anis)
    local class = Class(boss)
    boss.record[id] = class
    class.cards = {}
    class.name = name
    class.bgm = bgm
    class._bg = bg
    class.difficulty = diff
    function class:init(cards)
        boss.init(self, x, y, name, cards, new_scbg(scbg), diff)
        self._wisys:SetImage(img, nRow, nCol, imgs, anis, intv, a, b)
    end
    return class
end

function boss.create(id, x, y)
    local obj = New(boss.record[id])
    if x and y then
        obj.x, obj.y = x, y
    end
    return obj
end

function boss.createWithCards(id, cards)
    local obj = New(boss.record[id], cards)
    return obj
end

----------------------------------------
---boss函数库和资源

local patch = "THlib/enemy/"

LoadTexture("boss", patch .. "boss.png")
LoadImageGroup("bossring1", "boss", 80, 0, 16, 8, 1, 16)
for i = 1, 16 do
    SetImageState("bossring1" .. i, "mul+add", Color(0x80FFFFFF))
end
LoadImageGroup("bossring2", "boss", 48, 0, 16, 8, 1, 16)
for i = 1, 16 do
    SetImageState("bossring2" .. i, "mul+add", Color(0x80FFFFFF))
end
LoadImage("spell_card_ef", "boss", 96, 0, 16, 128)
LoadImage("hpbar", "boss", 116, 0, 8, 128)
--LoadImage("hpbar1", "boss", 116, 0, 2, 2)
LoadImage("hpbar2", "boss", 116, 0, 2, 2)
SetImageCenter("hpbar", 0, 0)
LoadTexture("undefined", patch .. "undefined.png")
LoadImage("undefined", "undefined", 0, 0, 128, 128, 16, 16)
SetImageState("undefined", "mul+add", Color(0x80FFFFFF))
LoadImageFromFile("base_hp", patch .. "ring00.png")
SetImageState("base_hp", "", Color(0xFFFF0000))
LoadTexture("lifebar", patch .. "lifebar.png")
LoadImage("life_node", "lifebar", 20, 0, 12, 16)
LoadImage("hpbar1", "lifebar", 4, 0, 2, 2)
SetImageState("hpbar1", "", Color(0xFFFFFFFF))
SetImageState("hpbar2", "", Color(0x77D5CFFF))
LoadTexture("magicsquare", patch .. "eff_magicsquare.png")
LoadImageGroup("boss_aura_3D", "magicsquare", 0, 0, 256, 256, 5, 5)
LoadImageFromFile("dialog_box", patch .. "dialog_box.png")
LoadTexture("timesign", patch .. "timesign.png")
LoadImage("hint.killtimer", "timesign", 0, 0, 128, 32)
LoadImage("hint.truetimer", "timesign", 0, 32, 128, 32)
do
    local ok = pcall(LoadFont, "bonus2", patch .. "bonus2.fnt", true)
    if not ok then
        -- Some reference exports omit the optional HGE score font.  Keep the
        -- original score resource name while using the bundled Chinese font.
        LoadTTF("bonus2", "assets/font/SourceHanSansCN-Bold.otf", 24, 24)
    end
end
-- Use the bundled reference UI/effect atlas. The newer THlib sheets are
-- absent from this project; treating the entire boss atlas as each sheet
-- produced corrupt labels, oversized effects and out-of-range balloon UVs.
LoadTexture("reference_boss_ui", "THlib/UI/boss_ui.png")
LoadImage("boss_cardleft", "reference_boss_ui", 64, 64, 32, 32)
LoadImageFromFile("boss_shockwave", patch .. "ring00.png")
LoadImage("boss_Cherry", "misc", 0, 32, 32, 32)
LoadImage("boss_light", "particles", 0, 0, 32, 32)
LoadTTF("balloon_font", "assets/font/wqy-microhei-mono.ttf", 32)

Include(patch .. "boss_system.lua")--boss行为逻辑
Include(patch .. "boss_function.lua")--boss额外函数
Include(patch .. "boss_card.lua")--boss非符、符卡
Include(patch .. "boss_dialog.lua")--boss对话
Include(patch .. "boss_other.lua")--杂项、boss移动、特效
Include(patch .. "boss_ui.lua")--boss ui
