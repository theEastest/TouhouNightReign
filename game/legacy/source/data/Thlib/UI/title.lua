

lstg.var.first=true


stage_init=stage.New('init',true,true)
function stage_init:init()
	New(mask_fader,'open')
end
function stage_init:frame()
	if --[[KeyIsDown'shoot' and ]]self.timer>30 then stage.Set('none', 'menu') end
end
function stage_init:render()

end

stage_menu=stage.New('menu',false,true)

function stage_menu:init()
    if not scoredata.difficulty_sellect then scoredata.difficulty_sellect=1 end
	BgSwitch.change=true
	BgSwitch.x=-800 BgSwitch.y=540
	BgSwitch.timer=0
	local menu_title,menu_player_select,menu_difficulty_select,menu_replay_loader,menu_replay_saver,menu_items,menu_sc_pr,_manual,menu_achi
	if _title_flag==nil then _title_flag=true else New(mask_fader,'open') end
	--
	local function ExitGame()
    task.New(stage_menu,function()
        for i=1,60 do SetBGMVolume('menu',1-i/60) task.Wait() end
			end)
		task.New(stage_menu,function()
			menu.FlyOut(menu_title,'right')
			task.Wait(60)
			stage.QuitGame()
		end)
	end
	--
	menu_items={{'Start Game',function() practice='stage' menu.FlyIn(menu_difficulty_select_pr,'right') menu.FlyOut(menu_title,'left') end}}
	if _allow_practice then table.insert(menu_items,{'Stage Practice',function() practice=nil menu.FlyIn(menu_difficulty_select,'right') menu.FlyOut(menu_title,'left') end}) end
	if _allow_sc_practice then table.insert(menu_items,{'Spell Practice',function() practice='spell' menu.FlyIn(menu_sc_pr,'right') menu.FlyOut(menu_title,'left') end}) end
	table.insert(menu_items,{'Achievement',function() menu.FlyIn(menu_achi,'right') menu.FlyOut(menu_title,'left') end})
	table.insert(menu_items,{'View Replay',function()
    replay_loader.Refresh(menu_replay_loader)
		menu.FadeIn(menu_replay_loader,'right')
		menu.FadeOut(menu_title,'left')
	end})
	table.insert(menu_items,{'Manual',function() menu.FlyIn(_manual,'right') menu.FlyOut(menu_title,'left') end})
	table.insert(menu_items,{'Exit Game',ExitGame})
	table.insert(menu_items,{'exit',function() if menu_title.pos==#menu_title.text then ExitGame() else menu_title.pos=#menu_title.text end end})
	menu_title=New(main_select_menu,'',menu_items)
	--
	menu_items={}
	local difficulty_pos=1
	for _,name in ipairs(stage.groups) do
		if name~='Spell Practice' then
			table.insert(menu_items,{name,function() menu.FlyOut(menu_difficulty_select,'left') last_menu=menu_difficulty_select last_menu.group_name=name menu.FlyIn(menu_player_select,'right') end})
			difficulty_pos=difficulty_pos+1
		end
	end
	table.insert(menu_items,{'exit',function() menu.FlyIn(menu_title,'left') menu.FlyOut(menu_difficulty_select,'right') end})
	menu_difficulty_select=New(rank_select_menu,'Select Difficulty',menu_items)
	menu_difficulty_select.pos=scoredata.difficulty_select or 1
	--
	menu_items={}
	for i,v in ipairs(player_list) do
		table.insert(menu_items,{player_list[i][1],function()
			scoredata.player_select=i
			menu.FlyOut(menu_player_select,'left')
			lstg.var.player_name=player_list[i][2]
			lstg.var.rep_player=player_list[i][3]
			task.New(stage_menu,function()
				for i=1,60 do
					SetBGMVolume('menu',1-i/60)
					BgSwitch.x=BgSwitch.x+1380/60
					BgSwitch.y=BgSwitch.y-9
					BgSwitch.timer=BgSwitch.timer+1
					task.Wait()
				end
			end)
			task.New(stage_menu,function()
				task.Wait(30)
				--New(mask_fader,'close')
				task.Wait(30)
				if practice=='stage' then
					stage.group.PracticeStart(last_menu.stage_name[last_menu.pos])
				elseif practice=='spell' then
					stage.group.PracticeStart('Spell Practice@Spell Practice')
				else
					stage.group.Start(stage.groups[last_menu.group_name])
				end
			end)
		end})
	end
	table.insert(menu_items,{'exit',function() menu.FlyIn(last_menu,'left') menu.FlyOut(menu_player_select,'right') end})
	menu_player_select=New(player_select_menu,'Select Player',menu_items)
	menu_player_select.pos=scoredata.player_select or 1
	--
	menu_items={}
	table.insert(menu_items,{'player',function() menu.FlyIn(menu_title,'left') menu.FlyOut(_manual,'right') end})
	table.insert(menu_items,{'exit',function() menu.FlyIn(menu_title,'left') menu.FlyOut(_manual,'right') end})
	_manual=New(manual_menu,'Manual',menu_items)
	--
	menu_items={}
	local counter=0
	for i,name in ipairs(stage.groups) do
      if stage.groups[name].allow_practice then
        table.insert(menu_items,{name,function() menu.FlyOut(menu_difficulty_select_pr,'left') menu.FlyIn(menu_practice[name],'right') end})
      end
  end
	table.insert(menu_items,{'exit',function() menu.FlyIn(menu_title,'left') menu.FlyOut(menu_difficulty_select_pr,'right') end})
	menu_difficulty_select_pr=New(rank_select_menu,'Select Difficulty',menu_items)
	--
	menu_practice={}
	for _,sg in ipairs(stage.groups) do
		if stage.groups[sg].allow_practice then
			local menu_items={}
			for _,s in ipairs(stage.groups[sg]) do
				if string.match(s,"^[%w_][%w_ ]*")~='ENDING' then
					table.insert(menu_items,{string.match(s,"^[%w_][%w_ ]*"),function() menu.FlyOut(menu_practice[sg],'left') last_menu=menu_practice[sg] menu.FlyIn(menu_player_select,'right') end})
				else
          local nst,lst=0,0
          for i=1,16 do nst=nst+scoredata.stage_clear[1][i] lst=lst+scoredata.stage_clear[2][i] end
          if string.match(s,"^[%w_][%w_ ]*")=='ENDING' and sg=='Normal' and nst>=16 then
            table.insert(menu_items,{string.match(s,"^[%w_][%w_ ]*"),function() menu.FlyOut(menu_practice[sg],'left') last_menu=menu_practice[sg] menu.FlyIn(menu_player_select,'right') end})
          end
          if string.match(s,"^[%w_][%w_ ]*")=='ENDING' and sg=='Lunatic' and lst>=16 then
            table.insert(menu_items,{string.match(s,"^[%w_][%w_ ]*"),function() menu.FlyOut(menu_practice[sg],'left') last_menu=menu_practice[sg] menu.FlyIn(menu_player_select,'right') end})
          end
				end
			end
			table.insert(menu_items,{'exit',function() menu.FlyIn(menu_difficulty_select_pr,'left') menu.FlyOut(menu_practice[sg],'right') end})
			menu_practice[sg]=New(stage_select_menu,'Select Stage',menu_items)
			menu_practice[sg].stage_name={}
			for _,s in ipairs(stage.groups[sg]) do
				if stage.stages[s].allow_practice then
					table.insert(menu_practice[sg].stage_name,s)
				end
			end
		end
	end
	--
	menu_achi=New(achi_menu,function(index)
		if index then
		else
			menu.FlyIn(menu_title,'left')
			menu.FlyOut(menu_achi,'right')
		end
	end)
	--
	menu_sc_pr=New(sc_pr_menu,function(index)
		if index then
			last_menu=menu_sc_pr
			lstg.var.sc_index=index
			menu.FlyIn(menu_player_select,'right')
			menu.FlyOut(menu_sc_pr,'left')
		else
			menu.FlyIn(menu_title,'left')
			menu.FlyOut(menu_sc_pr,'right')
		end
	end)
	--
	menu_replay_loader=New(replay_loader,function(filename, stageName)
		if not filename then
			menu.FlyIn(menu_title,'left')
			menu.FlyOut(menu_replay_loader,'right')
		else
      task.New(stage_menu,function()
        for i=1,60 do SetBGMVolume('menu',1-i/60) task.Wait() end
			end)
			task.New(stage_menu,function()
				menu.FlyOut(menu_replay_loader,'left')
				task.Wait(30)
				New(mask_fader,'close')
				task.Wait(30)
				stage.Set('load', filename, stageName)
			end)
		end
	end)
	local task_menu_init=function()
		New(stargameobj,lstg.var.first,menu_title)
		if not lstg.var.first then PlayMusic('menu') menu.FlyIn(menu_title,'right')  end
	end
	if self.save_replay then
		menu_replay_saver=New(replay_saver,self.save_replay,self.finish,function()
			menu.FlyOut(menu_replay_saver,'right')
			task.New(stage_menu,function() task.Wait(30) task.New(stage_menu,task_menu_init) end)
		end)
		menu.FlyIn(menu_replay_saver,'left')
	else
		task.New(stage_menu,task_menu_init)
	end
	LoadMusic('menu',music_list.menu[1],music_list.menu[2],music_list.menu[3])
end

function stage_menu:render()
	ui.DrawMenuBG()
	if scoredata.play_timer then
	end
end

LoadImageFromFile("lualogo","Thlib\\UI\\lua.jpg")
LoadImageFromFile("luastg","Thlib\\UI\\luastg.jpg")
LoadImageFromFile("org","Thlib\\UI\\org.jpg")


stargameobj=Class(object)
function stargameobj:init(first,menu_title)
    self.img="lualogo"
	self.x=320
	self.y=240
	self.bound=false
	self.group=GROUP_GHOST
	self.layer=LAYER_TOP+3.5
	self.alpha=1
	self.alpha1=1
	self.state=1
	self.first=first
  	task.New(self,function()
		if first then
			task.Wait(20)
			self.alpha1=1
			self.state=1
			for i=20,0,-1 do
				self.alpha1=i/20
				task.Wait(1)
			end
			task.Wait(70)
			for i=0,20 do
				self.alpha1=i/20
				task.Wait(1)
			end
			self.alpha=1
			task.Wait(20)
			self.alpha1=1
			self.state=2
			for i=20,0,-1 do
				self.alpha1=i/20
				task.Wait(1)
			end
			task.Wait(70)
			for i=0,20 do
				self.alpha1=i/20
				task.Wait(1)
			end
			self.alpha=1
			self.state=3
			task.Wait(20)
			self.alpha1=1
			for i=20,0,-1 do
				self.alpha1=i/20
				task.Wait(1)
			end
			task.Wait(70)
			for i=0,20 do
				self.alpha1=i/20
				task.Wait(1)
			end
			self.alpha=0
		    task.Wait(10)
		    menu.FlyIn(menu_title,'right')
			PlayMusic('menu')
			lstg.var.first=false
			for i=20,0,-1 do
				self.alpha1=i/20
				task.Wait(1)
			end
		end
		Del(self)
	end)
end
function stargameobj:frame()
    if KeyIsDown('shoot') then
	    task.Do(self)
		task.Do(self)
	end
	task.Do(self)
end
function stargameobj:render()
	SetViewMode"ui"
	if self.first then
	SetImageState("white","",Color(255*self.alpha,0,0,0))
	Render("white",320,240,0,100,100,0.5)
	SetImageState("white","",Color(255,255,255,255))
    if self.state==1 then
		SetImageState("org","",Color(255*self.alpha,255,255,255))
		Render("org",320,240,0,0.5,0.5,0.5)
	end
    if self.state==2 then
		SetImageState("lualogo","",Color(255*self.alpha,255,255,255))
		Render("lualogo",320,240,0,0.5,0.5,0.5)
	end
    if self.state==3 then
		SetImageState("luastg","",Color(255*self.alpha,255,255,255))
		Render("luastg",320,240,0,0.5,0.5,0.5)
	end
	SetImageState("white","",Color(255*self.alpha1,0,0,0))
	Render("white",320,240,0,100,100,0.5)
	SetImageState("white","",Color(255,255,255,255))
	end
end
