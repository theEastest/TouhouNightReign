return function(equal, truth)
    local Dialogue = require("tnr.legacy_replay.dialogue")
    local data = require("tnr.legacy_replay.data.th15_msg")
    local Adapter = require("tnr.legacy_replay.adapter")
    local events = {}
    local ending = Dialogue.new({data = {[0] = {
        {time = 0, id = 21}, {time = 120, id = 0},
    }}, on_event = function(kind) events[#events + 1] = kind end})
    ending:start(0)
    equal(events[1], "stage_end", "opcode 21 requests the stage transition immediately")
    truth(ending.active and not ending.completed[0], "the later end opcode remains pending")
    for _ = 1, 120 do ending:update({}) end
    equal(events[2], "complete", "opcode 0 still ends the dialogue at its own time")
    local replay = require("tnr.legacy_replay.replay").new({lstg = {}})
    truth(replay:start_stage(), "stage starts for the ending transition test")
    local stage = replay.runtime
    stage.original_main = true
    local previous_entry = stage.dialogue.data[99]
    stage.dialogue.data[99] = {{time = 0, id = 21}, {time = 120, id = 0}}
    stage.dialogue:start(99)
    stage:_advance_timeline()
    truth(stage.timeline_done and stage.dialogue.active,
        "stage clears on opcode 21 without waiting for the dialogue end")
    stage.dialogue.data[99] = previous_entry
    for _, key in ipairs({"st01a", "st01b", "st01c", "st01d"}) do
        truth(data[key][0] ~= nil and data[key][1] ~= nil, key .. " has both dialogue entries")
    end
    local dialog = Dialogue.new({data = data.st01a})
    dialog:start(0)
    for _ = 1, 38 do dialog:update({}) end
    equal(dialog.wait, 600, "first line waits for input or source timeout")
    equal(dialog.lines[1], "这是什么", "Chinese source text is preserved")
    for _ = 1, 20 do dialog:update({}) end
    equal(dialog.time, 38, "MSG timeline freezes while waiting")
    local adapter = Adapter.new({lstg = {}, chunks = {}})
    adapter.dialogue = dialog
    local thread = {pc = 5}
    adapter.instructions.dialogWait(thread, adapter.runtime)
    equal(thread.pc, 4, "ECL remains blocked before resume opcode")
    dialog:update({shoot = true})
    for _ = 1, 4 do dialog:update({shoot = true}) end
    equal(dialog.generation, 1, "opcode 12 releases ECL during dialogue")
    truth(dialog.active, "boss entrance does not finish dialogue")
    thread.pc = 5
    adapter.instructions.dialogWait(thread, adapter.runtime)
    equal(thread.pc, 5, "first wait resumes")
    adapter.instructions.dialogWait(thread, adapter.runtime)
    equal(thread.pc, 5, "all waits in the same enemy tick observe the native resume pulse")
    dialog:update({shoot=true})
    adapter.instructions.dialogWait(thread,adapter.runtime)
    equal(thread.pc,4,"the next GUI tick expires the resume pulse")
    for i = 1, 10000 do
        dialog:update({shoot = i % 2 == 0})
        if not dialog.active then break end
    end
    truth(dialog.completed[0], "pre-boss dialogue reaches end opcode")
    truth(next(dialog.unknown) == nil, "stage-one instructions have explicit handling")
    dialog:start(1)
    truth(not dialog.completed[1], "requesting ending dialogue does not complete it")
    for _ = 1, 10000 do
        dialog:update({})
        if not dialog.active then break end
    end
    truth(dialog.completed[1] and dialog.stage_end, "ending completes after source stage-end and end opcodes")

    local opening=Dialogue.new({data=data.st06a})
    opening:start(0)
    adapter.dialogue=opening
    local entrance={pc=5}
    adapter.instructions.dialogWait(entrance,adapter.runtime)
    equal(entrance.pc,4,"stage-six time-zero resume waits for the GUI publication tick")
    opening:update({},false)
    entrance.pc=5
    adapter.instructions.dialogWait(entrance,adapter.runtime)
    equal(entrance.pc,5,"stage-six boss enters on the first resume without waiting for dialogue to end")

    local skip = Dialogue.new({data = { [0] = {
        {time=0,id=10,1}, {time=0,id=11,600},
        {time=30,id=10,0}, {time=35,id=12}, {time=36,id=11,600}, {time=37,id=0},
    }}})
    skip:start(0)
    for _=1,19 do skip:update({skip_dialogue=true}) end
    equal(skip.wait,581,"Ctrl requires twenty held ticks before skipping")
    skip:update({skip_dialogue=true})
    equal(skip.wait,0,"Ctrl clears a skippable wait")
    skip:update({skip_dialogue=true})
    equal(skip.time,30,"fast-forward seeks to the next MSG instruction")
    for _=1,5 do skip:update({skip_dialogue=true}) end
    equal(skip.generation,1,"unskippable entrance still takes its scripted time")
    skip:update({skip_dialogue=true})
    equal(skip.wait,600,"Ctrl leaves an unskippable wait intact")
    skip:update({confirm=true})
    equal(skip.wait,0,"Enter advances the current line")
end
