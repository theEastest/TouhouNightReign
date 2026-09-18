Include'THlib\\ui\\uiconfig.lua'
Include'THlib\\ui\\font.lua'
Include'THlib\\ui\\title.lua'
Include'THlib\\ui\\sc_pr.lua'
ui={}

LoadTexture('boss_ui','THlib\\UI\\boss_ui.png')
LoadImage('boss_spell_name_bg','boss_ui',0,0,256,36)
SetImageCenter('boss_spell_name_bg',256,0)

LoadImage('boss_pointer','boss_ui',0,64,48,16)
SetImageCenter('boss_pointer',24,0)

LoadImage('boss_sc_left','boss_ui',64,64,32,32)
SetImageState('boss_sc_left','',Color(0xFF80FF80))

LoadTexture('hint','THlib\\ui\\hint.png',true)
LoadImage('hint.bonusfail','hint',0,64,256,64)
LoadImage('hint.getbonus','hint',0,128,396,64)
LoadImage('hint.extend','hint',0,192,160,64)
LoadImage('hint.power','hint',0,12,84,32)
LoadImage('hint.graze','hint',86,12,74,32)
LoadImage('hint.point','hint',160,12,120,32)
LoadImage('hint.life','hint',288,0,16,15)
LoadImage('hint.lifeleft','hint',304,0,16,15)
LoadImage('hint.bomb','hint',320,0,16,16)
LoadImage('hint.bombleft','hint',336,0,16,16)
LoadImage('kill_time','hint',232,200,152,56,16,16)
SetImageCenter('hint.power',0,16)
SetImageCenter('hint.graze',0,16)
SetImageCenter('hint.point',0,16)
LoadImageGroup('lifechip','hint',288,16,16,15,4,1,0,0)
LoadImageGroup('bombchip','hint',288,32,16,16,4,1,0,0)
LoadImage('hint.hiscore','hint',424,8,80,20)
LoadImage('hint.score','hint',424,30,64,20)
LoadImage('hint.Pnumber','hint',352,8,56,20)
LoadImage('hint.Bnumber','hint',352,30,72,20)
LoadImage('hint.Cnumber','hint',352,52,40,20)
SetImageCenter('hint.hiscore',0,10)
SetImageCenter('hint.score',0,10)
SetImageCenter('hint.Pnumber',0,10)
SetImageCenter('hint.Bnumber',0,10)

LoadTexture('line','THlib\\ui\\line.png',true)
LoadImageGroup('line_','line',0,0,180,8,1,7,0,0)

LoadTexture('ui_rank','THlib\\ui\\rank.png')
LoadImage('rank_Easy','ui_rank',0,0,144,32)
LoadImage('rank_Normal','ui_rank',0,32,144,32)
LoadImage('rank_Hard','ui_rank',0,64,144,32)
LoadImage('rank_Lunatic','ui_rank',0,96,144,32)
LoadImage('rank_Extra','ui_rank',0,128,144,32)

ui.menu={
	font_size=0.625,
	line_height=24,
	char_width=20,
	num_width=12.5,
	title_color={255,255,255},
	unfocused_color={128,128,128},
--	unfocused_color={255,255,255},
	focused_color1={255,255,255},
	focused_color2={255,192,192},
	blink_speed=7,
	shake_time=9,
	shake_speed=40,
	shake_range=3,
	sc_pr_line_per_page=12,
	sc_pr_line_height=22,
	sc_pr_width=320,
	sc_pr_margin=8,
	rep_font_size=0.6,
	rep_line_height=20,
	achi_width=241,
}

function ui.DrawMenu(title,text,pos,x,y,alpha,timer,shake,align)
	align=align or 'center'
	local yos
	if title=='' then yos=(#text+1)*ui.menu.line_height*0.5 else
		yos=(#text-1)*ui.menu.line_height*0.5
		SetFontState('menu','',Color(alpha*255,unpack(ui.menu.title_color)))
		RenderText('menu',title,x,y+yos+ui.menu.line_height,ui.menu.font_size,align,'vcenter')
	end
	for i=1,#text do
		if i==pos then
			local color={}
			local k=cos(timer*ui.menu.blink_speed)^2
			for j=1,3 do color[j]=ui.menu.focused_color1[j]*k+ui.menu.focused_color2[j]*(1-k) end

			local xos=ui.menu.shake_range*sin(ui.menu.shake_speed*shake)

			SetFontState('menu','',Color(alpha*255,unpack(color)))
			RenderText('menu',text[i],x+xos,y-i*ui.menu.line_height+yos,ui.menu.font_size,align,'vcenter')
		--	RenderTTF('menuttf',text[i],x+xos+2,x+xos+2,y-i*ui.menu.line_height+yos,y-i*ui.menu.line_height+yos,Color(alpha*255,0,0,0),'centerpoint')
		--	RenderTTF('menuttf',text[i],x+xos,x+xos,y-i*ui.menu.line_height+yos,y-i*ui.menu.line_height+yos,Color(alpha*255,unpack(color)),'centerpoint')
		else
			SetFontState('menu','',Color(alpha*255,unpack(ui.menu.unfocused_color)))
			RenderText('menu',text[i],x,y-i*ui.menu.line_height+yos,ui.menu.font_size,align,'vcenter')
		--	RenderTTF('menuttf',text[i],x+2,x+2,y-i*ui.menu.line_height+yos,y-i*ui.menu.line_height+yos,Color(alpha*255,0,0,0),'centerpoint')
		--	RenderTTF('menuttf',text[i],x,x,y-i*ui.menu.line_height+yos,y-i*ui.menu.line_height+yos,Color(alpha*255,unpack(ui.menu.unfocused_color)),'centerpoint')
		end
	end
end

function ui.DrawMenuTTF(ttfname,title,text,pos,x,y,alpha,timer,shake,align)
	align=align or 'center'
	local yos
	if title=='' then yos=(#text+1)*ui.menu.sc_pr_line_height*0.5 else
		yos=(#text-1)*ui.menu.sc_pr_line_height*0.5
		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height,y+yos+ui.menu.sc_pr_line_height,Color(alpha*255,unpack(ui.menu.title_color)),align,'vcenter','noclip')
	end
	for i=1,#text do
		if i==pos then
			local color={}
			local k=cos(timer*ui.menu.blink_speed)^2
			for j=1,3 do color[j]=ui.menu.focused_color1[j]*k+ui.menu.focused_color2[j]*(1-k) end
			local xos=ui.menu.shake_range*sin(ui.menu.shake_speed*shake)
			RenderTTF(ttfname,text[i],x+xos,x+xos,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(color)),align,'vcenter','noclip')
		else
			RenderTTF(ttfname,text[i],x,x,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(ui.menu.unfocused_color)),align,'vcenter','noclip')
		end
	end
end

function ui.DrawMenuTTFBlack(ttfname,title,text,pos,x,y,alpha,timer,shake,align)
	align=align or 'center'
	local yos
	if title=='' then yos=(#text+1)*ui.menu.sc_pr_line_height*0.5 else
		yos=(#text-1)*ui.menu.sc_pr_line_height*0.5
		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height,y+yos+ui.menu.sc_pr_line_height,Color(0xFF000000),align,'vcenter','noclip')
	end
	for i=1,#text do
		if i==pos then
			local xos=ui.menu.shake_range*sin(ui.menu.shake_speed*shake)
			RenderTTF(ttfname,text[i],x+xos,x+xos,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(0xFF000000),align,'vcenter','noclip')
		else
			RenderTTF(ttfname,text[i],x,x,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(0xFF000000),align,'vcenter','noclip')
		end
	end
end

function ui.DrawRepText(ttfname,title,text,pos,x,y,alpha,timer,shake)
	local yos
	if title=='' then yos=(#text+1)*ui.menu.sc_pr_line_height*0.5 else
		yos=(#text-1)*ui.menu.sc_pr_line_height*0.5
		Render(title,x,y+ui.menu.sc_pr_line_height+yos)
--		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height+1,y+yos+ui.menu.sc_pr_line_height-1,Color(0xFF000000),'center','vcenter','noclip')
--		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height,y+yos+ui.menu.sc_pr_line_height,Color(255,unpack(ui.menu.title_color)),'center','vcenter','noclip')
	end
	local _text=text
	local xos={-300,-240,-120,20,130,240}
	for i=1,#_text do
		if i==pos then
			local color={}
			local k=cos(timer*ui.menu.blink_speed)^2
			for j=1,3 do color[j]=ui.menu.focused_color1[j]*k+ui.menu.focused_color2[j]*(1-k) end
--			local xos=ui.menu.shake_range*sin(ui.menu.shake_speed*shake)
			SetFontState('replay','',Color(0xFFFFFF30))
--			RenderTTF(ttfname,text[i],x+xos,x+xos,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(color)),align,'vcenter','noclip')
			for m=1,6 do
				RenderText('replay',_text[i][m],x+xos[m],y-i*ui.menu.rep_line_height+yos,ui.menu.rep_font_size,'vcenter','left')
			end
		else
			SetFontState('replay','',Color(0xFF808080))
--			RenderTTF(ttfname,text[i],x,x,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(ui.menu.unfocused_color)),align,'vcenter','noclip')
			for m=1,6 do
				RenderText('replay',_text[i][m],x+xos[m],y-i*ui.menu.rep_line_height+yos,ui.menu.rep_font_size,'vcenter','left')
			end
		end
	end
end

function ui.DrawRepText2(ttfname,title,text,pos,x,y,alpha,timer,shake)
	local yos
	if title=='' then yos=(#text+1)*ui.menu.sc_pr_line_height*0.5 else
		yos=(#text-1)*ui.menu.sc_pr_line_height*0.5
		Render(title,x,y+ui.menu.sc_pr_line_height+yos)
--		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height+1,y+yos+ui.menu.sc_pr_line_height-1,Color(0xFF000000),'center','vcenter','noclip')
--		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height,y+yos+ui.menu.sc_pr_line_height,Color(255,unpack(ui.menu.title_color)),'center','vcenter','noclip')
	end
	local _text=text
	local xos={-80,120}
	for i=1,#_text do
		if i==pos then
			local color={}
			local k=cos(timer*ui.menu.blink_speed)^2
			for j=1,3 do color[j]=ui.menu.focused_color1[j]*k+ui.menu.focused_color2[j]*(1-k) end
--			local xos=ui.menu.shake_range*sin(ui.menu.shake_speed*shake)
			SetFontState('replay','',Color(0xFFFFFF30))
--			RenderTTF(ttfname,text[i],x+xos,x+xos,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(color)),align,'vcenter','noclip')
			RenderText('replay',_text[i][1],x+xos[1],y-i*ui.menu.rep_line_height+yos,ui.menu.rep_font_size,'vcenter','center')
			RenderText('replay',_text[i][2],x+xos[2],y-i*ui.menu.rep_line_height+yos,ui.menu.rep_font_size,'vcenter','right')
		else
			SetFontState('replay','',Color(0xFF808080))
--			RenderTTF(ttfname,text[i],x,x,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(ui.menu.unfocused_color)),align,'vcenter','noclip')
			RenderText('replay',_text[i][1],x+xos[1],y-i*ui.menu.rep_line_height+yos,ui.menu.rep_font_size,'vcenter','center')
			RenderText('replay',_text[i][2],x+xos[2],y-i*ui.menu.rep_line_height+yos,ui.menu.rep_font_size,'vcenter','right')
		end
	end
end
---!2017/8/30
function ui.DrawMenuSCP(ttfname,title,text,pos,x,y,alpha,timer,shake,align,get)
	align=align or 'center'
	local yos
	if title=='' then yos=(#text+1)*ui.menu.sc_pr_line_height*0.5 else
		yos=(#text-1)*ui.menu.sc_pr_line_height*0.5
		RenderTTF(ttfname,title,x,x,y+yos+ui.menu.sc_pr_line_height,y+yos+ui.menu.sc_pr_line_height,Color(alpha*255,unpack(ui.menu.title_color)),align,'vcenter','noclip')
	end
	local color={50,255,155}
	local un_focus_color={128,128,128}
	for i=1,#text do
		if get[i]==1 then
			color={70,220+25*cos(timer*ui.menu.blink_speed),200+30*cos(timer*ui.menu.blink_speed)}
			un_focus_color={35,128,115}
		else
			color={255,220+25*cos(timer*ui.menu.blink_speed),220+25*cos(timer*ui.menu.blink_speed)}
			un_focus_color={128,128,128}
		end
		if i==pos then
		--	alpha=1
			local xos=ui.menu.shake_range*sin(ui.menu.shake_speed*shake)
			RenderTTF(ttfname,text[i],x+xos,x+xos,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(color)),align,'vcenter','noclip')
		else
		--	alpha=0.5
			RenderTTF(ttfname,text[i],x,x,y-i*ui.menu.sc_pr_line_height+yos,y-i*ui.menu.sc_pr_line_height+yos,Color(alpha*255,unpack(un_focus_color)),align,'vcenter','noclip')
		end
	end
end
---!
function RenderScore(fontname,score,x,y,size,mode)
	if score<1000 then
		RenderText(fontname,string.format('%d',score),x,y,size,mode)
	elseif score<1000000 then
		RenderText(fontname,string.format('%d,%03d',math.floor(score/1000),score%1000),x,y,size,mode)
	elseif score<1000000000 then
		RenderText(fontname,string.format('%d,%03d,%03d',math.floor(score/1000000),math.floor(int(score/1000))%1000,score%1000),x,y,size,mode)
	elseif score<100000000000 then
		RenderText(fontname,string.format('%d,%03d,%03d,%03d',math.floor(score/1000000000),math.floor(int(score/1000000))%1000,math.floor(score/1000)%1000,score%1000),x,y,size,mode)
	else
		RenderText(fontname,string.format('99,999,999,999'),x,y,size,mode)
	end
end
--
diff_render_obj=Class(object)
function diff_render_obj:init(x,y,_type,img)
	self.group=GROUP_GHOST
	self.bound=false
	self.x=x
	self.y=y
	self.rot,self.
	self.layer=LAYER_TOP
	self.img=_type..img
	self._a,self._r,self._g,self._b=255,255,255,255
	ui_diff=self
end
function diff_render_obj:render()
	Render(self.img,self.x,self.y,self.rot,self.hscale,self.vscale)
end
--
ui.uiloaded=0

luastg_ui=Class(object)
	function luastg_ui:init()
		self.x=320
		self.y=240
		self.bound=false
		self.layer=LAYER_TOP+1
		self.group=GROUP_GHOST
		if not CheckRes('img','image:UI_img') 	then LoadImageFromFile('ui_bg','THlib\\ui\\ui_bg.png') end
		if not CheckRes('img','image:LOGO_img') then LoadImageFromFile('logo','THlib\\ui\\logo.png') end
		SetImageState('ui_bg','mul+alpha',Color(255,255,255,255))
		SetImageCenter('logo',0,0)
		SetImageCenter('ui_bg',224,240)
		LoadImageFromFile('menu_bg','THlib\\ui\\menu_bg.png')
		--
		_luastg_ui=self
	end
	function luastg_ui:render()
		local w=lstg.world
		SetViewMode'ui'
		--ui.DrawFrame--
		SetImageCenter('ui_bg',224,240)
		if CheckRes('img','image:UI_img') then
			Render('image:UI_img',(w.scrr-w.scrl)/2+w.scrl,(w.scrt-w.scrb)/2+w.scrb,0,(w.scrr-w.scrl)/384,(w.scrt-w.scrb)/448)
		else
			Render('ui_bg',(w.scrr-w.scrl)/2+w.scrl,(w.scrt-w.scrb)/2+w.scrb,0,(w.scrr-w.scrl)/384,(w.scrt-w.scrb)/448)
		end
		if CheckRes('img','image:LOGO_img') then Render('image:LOGO_img',-16+w.scrr,150,0,0.5,0.5) else Render('logo',-16+w.scrr+16+4,200,0,0.5,0.5) end
		SetFontState('menu','',Color(0xFFFFFFFF))
		RenderText('menu',string.format('%.1ffps',GetFPS()),220+w.scrr,1,0.25,'right','bottom')
		--
		--ui.DrawScore
		SetFontState('score3','',Color(0xFFADADAD))
		local diff=string.match(stage.current_stage.name,"[%w_][%w_ ]*$")
		local diffimg=CheckRes('img','image:diff_'..diff)
		if ext.sc_pr then
			if _editor_class[_sc_table[lstg.var.sc_index][1]].difficulty~='All' then
				diff=_editor_class[_sc_table[lstg.var.sc_index][1]].difficulty
			end
		end
		if diffimg then
			Render('image:diff_'..diff,112+w.scrr,448)
		else
			if diff=='Easy' or diff=='Normal' or diff=='Hard' or diff=='Lunatic' or diff=='Extra' then
				Render('rank_'..diff,112+w.scrr,448,0.5,0.5)
			else
				RenderText('score',diff,112+w.scrr,466,0.5,'center')
			end
		end
		Render('line_1',109+w.scrr,419,0,1,1)
		Render('line_2',109+w.scrr,397,0,1,1)
		Render('line_3',109+w.scrr,349,0,1,1)
		Render('line_4',109+w.scrr,311,0,1,1)
		Render('line_5',109+w.scrr,247,0,1,1)
		Render('line_6',109+w.scrr,224,0,1,1)
		Render('line_7',109+w.scrr,202,0,1,1)
		Render('hint.hiscore',12+w.scrr,425,0,1,1)
		Render('hint.score',12+w.scrr,403,0,1,1)
		Render('hint.Pnumber',12+w.scrr,371,0,1,1)
		Render('hint.Bnumber',12+w.scrr,334,0,1,1)
		Render('hint.Cnumber',138+w.scrr,316,0,0.85,0.85)
		Render('hint.Cnumber',138+w.scrr,354,0,0.85,0.85)
		Render('hint.power',39+w.scrr,253,0,0.5,0.5)
		Render('hint.point',39+w.scrr,230,0,0.5,0.5)
		Render('hint.graze',54+w.scrr,208,0,0.5,0.5)
		--RenderText('score','HiScore\nScore\nPlayer\nSpell\nGraze',432,424,0.5,'left')
		for i=1,8 do
			Render('hint.life',89+w.scrr+13*i,371,0,1,1)
		end
		for i=1,lstg.var.lifeleft do
			Render('hint.lifeleft',89+w.scrr+13*i,371,0,1,1)
		end
		for i=1,8 do
			Render('hint.bomb',89+w.scrr+13*i,334,0,1,1)
		end
		for i=1,lstg.var.bomb do
			Render('hint.bombleft',89+w.scrr+13*i,334,0,1,1)
		end
		local Lchip=int(lstg.var.chip/20)
		if Lchip>0 and Lchip<5 and lstg.var.lifeleft<8 then
			Render('lifechip'..Lchip,89+w.scrr+13*(lstg.var.lifeleft+1),371,0,1,1)
		end
		local Bchip=int(lstg.var.bombchip/20)
		if Bchip>0 and Bchip<5 and lstg.var.bomb<8 then
			Render('bombchip'..Bchip,89+w.scrr+13*(lstg.var.bomb+1),334,0,1,1)
		end
		SetFontState('score3','',Color(0xFFADADAD))
		RenderScore('score3',max(lstg.tmpvar.hiscore or 0,lstg.var.score),216+w.scrr,436,0.43,'right')
		SetFontState('score3','',Color(0xFFFFFFFF))
		RenderScore('score3',lstg.var.score,216+w.scrr,414,0.43,'right')
		RenderText('score3',string.format('%.1f',lstg.var.chip)..'%',214+w.scrr,361,0.35,'right')--596,left
		RenderText('score3',string.format('%.1f',lstg.var.bombchip)..'%',214+w.scrr,323,0.35,'right')
		--Render('hint.power',450,258,0,0.5)
		--Render('hint.point',452,240,0,0.5)
		--Render('hint.graze',466,222,0,0.5)
		SetFontState('score1','',Color(0xFFCD6600))
		SetFontState('score2','',Color(0xFF22D8DD))
		---
		RenderText('score1',string.format('%d.    /4.    ',math.floor(lstg.var.power/100)),204+w.scrr,262,0.4,'right')
		RenderText('score1',string.format('      %d%d        00',math.floor((lstg.var.power%100)/10),min(9,lstg.var.power%10)),205+w.scrr,258.5,0.3,'right')
		RenderScore('score2',lstg.var.pointrate,204+w.scrr,239,0.4,'right')
		--RenderText('score2',string.format('%d,%d%d%d',math.floor(lstg.var.pointrate/1000),math.floor(lstg.var.pointrate/100)%10,math.floor(lstg.var.pointrate/10)%10,lstg.var.pointrate%10),204+w.scrr,239,0.4,'right')
		SetFontState('score3','',Color(0xFFADADAD))
		RenderText('score3',string.format('%d',lstg.var.graze),204+w.scrr,216,0.4,'right')
		SetViewMode'world'
	--
	end
	function luastg_ui:del()
		ui.uiloaded=0
	end
--

--
if setting.resx>setting.resy then
	if not CheckRes('img','image:UI_img') 	then LoadImageFromFile('ui_bg','THlib\\ui\\ui_bg.png') end
	if not CheckRes('img','image:LOGO_img') then LoadImageFromFile('logo','THlib\\ui\\logo.png') end
	SetImageCenter('logo',0,0)
	LoadImageFromFile('menu_bg','THlib\\ui\\menu_bg.png')

	function ui.DrawFrame()
		if CheckRes('img','image:UI_img') then Render('image:UI_img',320,240) else Render('ui_bg',320,240) end
		if CheckRes('img','image:LOGO_img') then Render('image:LOGO_img',400,150,0,0.5,0.5) else Render('logo',400,150,0,0.5,0.5) end
		SetFontState('menu','',Color(0xFFFFFFFF))
		RenderText('menu',string.format('%.1ffps',GetFPS()),636,1,0.25,'right','bottom')
	end

	function ui.DrawMenuBG()
		SetViewMode'ui'
		Render('menu_bg',320,240)
		SetFontState('menu','',Color(0xFFFFFFFF))
		RenderText('menu',string.format('%.1ffps',GetFPS()),636,1,0.25,'right','bottom')
	end
	function ui.DrawScore()
		if ui.uiloaded==0 then
			New(luastg_ui)
			ui.uiloaded=1
		end
		if not IsValid(_luastg_ui) then ui.uiloaded=0 end
		--[[SetFontState('score3','',Color(0xFFADADAD))
		local diff=string.match(stage.current_stage.name,"[%w_][%w_ ]*$")
		local diffimg=CheckRes('img','image:diff_'..diff)
		if diffimg then
			Render('image:diff_'..diff,528,448)
		else
      if diff=='Easy' or diff=='Normal' or diff=='Hard' or diff=='Lunatic' or diff=='Extra' then
        Render('rank_'..diff,528,448,0.5,0.5)
      else
        RenderText('score',diff,528,466,0.5,'center')
      end
		end
		Render('line_1',525,419,0,1,1)
		Render('line_2',525,397,0,1,1)
		Render('line_3',525,349,0,1,1)
		Render('line_4',525,311,0,1,1)
		Render('line_5',525,247,0,1,1)
		Render('line_6',525,224,0,1,1)
		Render('line_7',525,202,0,1,1)
		Render('hint.hiscore',428,425,0,1,1)
		Render('hint.score',428,403,0,1,1)
		Render('hint.Pnumber',428,371,0,1,1)
		Render('hint.Bnumber',428,334,0,1,1)
		Render('hint.Cnumber',554,316,0,0.85,0.85)
		Render('hint.Cnumber',554,354,0,0.85,0.85)
		Render('hint.power',455,253,0,0.5,0.5)
		Render('hint.point',455,230,0,0.5,0.5)
		Render('hint.graze',470,208,0,0.5,0.5)
		--RenderText('score','HiScore\nScore\nPlayer\nSpell\nGraze',432,424,0.5,'left')
		for i=1,8 do
			Render('hint.life',505+13*i,371,0,1,1)
		end
		for i=1,lstg.var.lifeleft do
			Render('hint.lifeleft',505+13*i,371,0,1,1)
		end
		for i=1,8 do
			Render('hint.bomb',505+13*i,334,0,1,1)
		end
		for i=1,lstg.var.bomb do
			Render('hint.bombleft',505+13*i,334,0,1,1)
		end
		local Lchip=int(lstg.var.chip/20)
		if Lchip>0 and Lchip<5 and lstg.var.lifeleft<8 then
			Render('lifechip'..Lchip,505+13*(lstg.var.lifeleft+1),371,0,1,1)
		end
		local Bchip=int(lstg.var.bombchip/20)
		if Bchip>0 and Bchip<5 and lstg.var.bomb<8 then
			Render('bombchip'..Bchip,505+13*(lstg.var.bomb+1),334,0,1,1)
		end
		SetFontState('score3','',Color(0xFFADADAD))
		RenderScore('score3',max(lstg.tmpvar.hiscore or 0,lstg.var.score),622,436,0.43,'right')
		SetFontState('score3','',Color(0xFFFFFFFF))
		RenderScore('score3',lstg.var.score,622,414,0.43,'right')
		RenderText('score3',string.format('%.1f',lstg.var.chip)..'%',620,361,0.35,'right')--596,left
		RenderText('score3',string.format('%.1f',lstg.var.bombchip)..'%',620,323,0.35,'right')
		--Render('hint.power',450,258,0,0.5)
		--Render('hint.point',452,240,0,0.5)
		--Render('hint.graze',466,222,0,0.5)
		SetFontState('score1','',Color(0xFFCD6600))
		SetFontState('score2','',Color(0xFF22D8DD))
		---
		RenderText('score1',string.format('%d.    /4.    ',math.floor(lstg.var.power/100)),610,262,0.4,'right')
		RenderText('score1',string.format('      %d%d        00',min(math.floor((lstg.var.power%100)/10),9),min(lstg.var.power%10,9)),611,258.5,0.3,'right')
		RenderScore('score2',lstg.var.pointrate,610,239,0.4,'right')
--		RenderText('score2',string.format('%d,%d%d%d',math.floor(lstg.var.pointrate/1000),math.floor(lstg.var.pointrate/100)%10,math.floor(lstg.var.pointrate/10)%10,lstg.var.pointrate%10),610,239,0.4,'right')
		SetFontState('score3','',Color(0xFFADADAD))
		RenderText('score3',string.format('%d',lstg.var.graze),610,216,0.4,'right')--]]
	end
else
	LoadImageFromFile('ui_bg','THlib\\ui\\ui_bg_2.png')
	LoadImageFromFile('logo','THlib\\ui\\logo.png')
	LoadImageFromFile('menu_bg','THlib\\ui\\menu_bg_2.png')

	function ui.DrawFrame()
		Render('ui_bg',198,264)
	end

	function ui.DrawMenuBG()
		SetViewMode'ui'
		Render('menu_bg',198,264)
		SetFontState('menu','',Color(0xFFFFFFFF))
		RenderText('menu',string.format('%.1ffps',GetFPS()),392,1,0.25,'right','bottom')
	end

	function ui.DrawScore()
		RenderText('score','HiScore',8,520,0.5,'left','top')
		RenderText('score',string.format('%d',max(lstg.tmpvar.hiscore or 0,lstg.var.score)),190,520,0.5,'right','top')
		RenderText('score','Score',206,520,0.5,'left','top')
		RenderText('score',string.format('%d',lstg.var.score),388,520,0.5,'right','top')
		SetFontState('score','',Color(0xFFFF4040))
		RenderText('score',string.format('%1.2f',lstg.var.power/100),8,496,0.5,'left','top')
		SetFontState('score','',Color(0xFF40FF40))
		RenderText('score',string.format('%d',lstg.var.faith),84,496,0.5,'left','top')
		SetFontState('score','',Color(0xFF4040FF))
		RenderText('score',string.format('%d',lstg.var.pointrate),160,496,0.5,'left','top')
		SetFontState('score','',Color(0xFFFFFFFF))
		RenderText('score',string.format('%d',lstg.var.graze),236,496,0.5,'left','top')
		RenderText('score',string.rep('*',max(0,lstg.var.lifeleft)),388,496,0.5,'right','top')
		RenderText('score',string.rep('*',max(0,lstg.var.bomb)),380,490,0.5,'right','top')
	end
end
