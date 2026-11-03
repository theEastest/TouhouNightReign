-- Execute the actual exported callbacks: a copied implementation would miss
-- regressions in the source that LuaSTG loads.
return function(eq,yes)
 local file=assert(io.open("game/legacy/source/activity7/_editor_output.lua","rb"))
 local source=file:read("*a"):gsub("\r\n","\n");file:close()
 for _,difficulty in ipairs({"Normal","Lunatic"}) do
  local insertion='table.insert(_editor_class["wuer_ufo:'..difficulty..'"].cards,_tmp_sc)'
  local body
  for callback,next_line in source:gmatch('(function _tmp_sc:del%(%)\n.-\nend)\n([^\n]+)') do
   if next_line==insertion and callback:find('labyrinth.no_ufo',1,true) then body=callback end
  end
  yes(body~=nil,"found exported UFO cleanup: "..difficulty)
  for _,scenario in ipairs({"absent","stale","live"}) do
   local sound_count=0
   local bg=scenario~="absent" and {} or nil
   local env={_tmp_sc={},labyrinth=bg,IsValid=function(o) return o==bg and scenario=="live" end,
    PlaySound=function(name) eq(name,"ufo_die","original death sound retained");sound_count=sound_count+1 end}
   local chunk
   if setfenv then chunk=assert(loadstring(body));setfenv(chunk,env)
   else chunk=assert(load(body,"ufo_cleanup","t",env)) end
   chunk();env._tmp_sc.del({})
   eq(sound_count,1,"cleanup completes with "..scenario.." background")
   if bg then eq(bg.no_ufo,scenario=="live" and true or nil,"only live maze receives progression flag") end
  end
 end
end
