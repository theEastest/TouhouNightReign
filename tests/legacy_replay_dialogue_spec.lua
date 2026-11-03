return function(equal, truth)
    local Dialogue = require("tnr.legacy_replay.dialogue")
    local data = require("tnr.legacy_replay.data.th15_msg")
    local Adapter = require("tnr.legacy_replay.adapter")
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
    equal(thread.pc, 4, "second wait blocks for the next release")
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
end
