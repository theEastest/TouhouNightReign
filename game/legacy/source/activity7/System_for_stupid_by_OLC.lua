--素材加载
LoadTexture('stupid_magicsquare','THlib\\enemy\\eff_magicsquare.png')
LoadImageGroup('stupid_boss_aura_3D','stupid_magicsquare',0,0,256,256,5,5)


--相关定义内容已较为完善，可直接调用，亦可手动修改。
--本lua文件内定义内容为OLC为Stupid所辅助建立的一些东西
--内容基本兼容于LuaSTGPlus ~ 1.02及以后版本，泛用性也较为广泛
--如有需求，可寻求帮助，亦可手动修改参数
--未来或将推出更加容易自定义参数的版本

--法阵显示系统
--使用方法:
--New(stupid_aura,显示法阵的对象)
--以下是obj的定义
stupid_aura=Class(object)
function stupid_aura:init(master)
    --设置基础的object的类别
    self.group = GROUP_GHOST
    --设置法阵相关显示系统
    --master为显示法阵的对象
    self.master = master
    --初始化坐标位置
    self.x,self.y = self.master.x,self.master.y
    --定义法阵展开时不透明度变化
    self.aura_alpha_first = 0
    self.aura_alpha_final = 255
    --定义法阵展开时大小变化
    self.size_first = 0
    self.size_final = 1
    --定义法阵展开时间
    self.spt = 0
    self.spreadtime = 30
    --数据处理
    self.size_change = self.size_final-self.size_first
    self.alpha_change = self.aura_alpha_final-self.aura_alpha_first
end
function stupid_aura:frame()
    --以下为实时数据处理
    if self.spt <= self.spreadtime then
        self.spt = self.spt + 1
    end
    local t = (self.spt/self.spreadtime)*90

    --不透明度变化
    if self.aura_alpha == self.aura_alpha_final then
    else
        self.aura_alpha = self.aura_alpha_first+self.alpha_change*sin(t)
    end
    for i=1,25 do
        SetImageState('stupid_boss_aura_3D'..i,'mul+add',Color(self.aura_alpha,255,255,255))
    end

    --大小变化
    if self.size == self.size_final then
    else
        self.size = self.size_first+self.size_change*sin(t)
    end

    if IsValid(self.master) then
        --法阵显示位置跟随
        local x,y = self.master.x,self.master.y
        self.x,self.y = x,y
    else
        --自动清除自身
        Del(self)
    end
end
function stupid_aura:render()
    --法阵渲染
    Render('stupid_boss_aura_3D'..self.ani%25+1,self.x,self.y,self.ani*0.75,0.92*self.size,(0.8+0.12*sin(90+self.ani*0.75))*self.size)
end

--血条显示系统
--使用方法:
--New(stupid_hpbar,显示血条的对象,血条数据来源)
--以下是obj的定义
stupid_hpbar=Class(object)
function stupid_hpbar:init(master,unit)
    --设置基础的object的类别
    self.group = GROUP_GHOST
    --设置血条相关显示系统
    --master为显示血条的对象
    self.master = master
    --unit为血条数据的对象
    self.unit = unit
    --初始化坐标位置
    self.x,self.y = self.master.x,self.master.y
    --获取血条数据
    self.hp = self.unit.hp
    self.maxhp = self.unit.maxhp
    --建立阶段点用表
    self.sp_point={}
end
function stupid_hpbar:frame()
    --以下是实时数据处理
    if IsValid(self.unit) and IsValid(self.master) then
        --血条显示位置跟随
        local x,y = self.master.x,self.master.y
        self.x,self.y = x,y
        --血条数据处理
        local hp,maxhp = self.unit.hp,self.unit.maxhp
        self.hp = max(0,hp)
        self.hpbarlen = hp/maxhp
        if self.unit.sp_point and #self.unit.sp_point~=0 then
            local sp_point = self.unit.sp_point
            self.sp_point = sp_point
        end
    else
        --self.master或self.unit不存在时删除自身
        Del(self)
    end
end
function stupid_hpbar:render()
    --显示血条的框
    misc.Renderhpbar(self.x,self.y,90,360,60,64,360,1)
    --显示血条数据
    misc.Renderhp(self.x,self.y,90,360,60,64,360,self.hpbarlen*min(1,self.timer/60))
    Render('base_hp',self.x,self.y,0,0.274,0.274)
    Render('base_hp',self.x,self.y,0,0.256,0.256)
    --显示阶段点(如果存在的话)
    if self.sp_point and #self.sp_point~=0 then
			    			for i=1,#self.sp_point do
					        	Render('life_node',self.x+61*cos(self.sp_point[i]),self.y+61*sin(self.sp_point[i]),self.sp_point[i]-90,0.5)
			    			end
    end
end
function stupid_hpbar:kill()
    --防止因hp为0而被系统自动kill
    PreserveObject(self)
end

