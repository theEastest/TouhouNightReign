-- Opt-in real-engine audit. Runs actual cards and their defeat callbacks;
-- errors are recorded, never hidden from normal gameplay.
local Audit={};Audit.__index=Audit
function Audit.new(game)
 local self=setmetatable({game=game,cases={},index=(tonumber(os.getenv("TNR_AUDIT_START")) or 1)-1,tick=0,failures=0},Audit)
 local filter=os.getenv("TNR_AUDIT_FILTER")
 for _,kind in ipairs({"card","nonspell"}) do
  local catalog=require(kind=="card" and "tnr.training.card_training_catalog" or "tnr.training.nonspell_training_catalog")
  for i,c in ipairs(catalog) do
   if c.legacy_boss and c.legacy_card_slot and (not filter or (c.legacy_boss..":"..c.legacy_card_slot):find(filter,1,true)) then
    self.cases[#self.cases+1]={kind=kind,catalog=catalog,index=i,card=c}
   end
  end
 end
 self.path=os.getenv("TNR_AUDIT_OUTPUT") or "native_audit.result"
 self.results={"status\tboss\tslot\tframes\terror\n"}
 self.duration=tonumber(os.getenv("TNR_AUDIT_FRAMES")) or 1200
 self.full=os.getenv("TNR_AUDIT_FULL")=="1"
 self.batch=tonumber(os.getenv("TNR_AUDIT_BATCH")) or 30
 return self
end
function Audit:finish(err)
 local c=self.current.card
 local line=table.concat({err and "FAIL" or "PASS",c.legacy_boss,c.legacy_card_slot,self.tick,
  (tostring(err or ""):gsub("[\r\n\t]"," "))},"\t")
 self.results[#self.results+1]=line.."\n"
 print("NATIVE_AUDIT "..self.index.." "..line)
 if err then self.failures=self.failures+1;self.done=true end
 self.current=nil
end
function Audit:step()
 if not self.current then
  self.index=self.index+1
  if self.index>#self.cases then self.done=true;return end
  self.current=self.cases[self.index];self.tick=0;self.seen=false;self.killing=false;self.combat_tick=0;self.limit=self.duration
  self.game.selection_kind=self.current.kind;self.game.selection_catalog=self.current.catalog
  assert(self.game:start_selected_training(self.current.index),"training launch failed")
 end
 self.tick=self.tick+1
 cheat=true
 local p=rawget(_G,"player");if p and IsValid(p) then p.protect=999;p.death=0 end
 local bridge=self.game.stage_adapter.native_bridge
 bridge.update({player_id=1,tick=self.tick,move_x=0,move_y=0})
 local b=stage.current_stage and stage.current_stage.boss
 if b and IsValid(b) then
  self.seen=true
  if b.is_combat then
   self.combat_tick=self.combat_tick+1
   local target=self.duration
   if self.full and b.current_card then
    target=math.max(1,(tonumber(b.current_card.t3) or self.duration)-1)
    self.limit=math.max(self.limit,target+600)
   end
   if self.combat_tick>=target then b.hp=0;self.killing=true end
  end
 elseif self.seen then self:finish() end
 if self.current and self.tick>=self.limit+900 then
  self:finish(self.seen and "boss did not finish after defeat" or "boss never spawned")
 end
end
function Audit:update()
 for _=1,self.batch do
  if self.done then
   local file=assert(io.open(self.path,"w"));file:write(table.concat(self.results));file:close()
   return true
  end
  local ok,err=xpcall(function() self:step() end,debug.traceback)
  if not ok then
   if self.current then self:finish(err) else error(err) end
  end
 end
 return false
end
function Audit:render()
 if not self.current then return end
 local ok,err=xpcall(function() self.game.stage_adapter.native_bridge.render() end,debug.traceback)
 if not ok then self:finish(err) end
end
return Audit
