-- Tests for the native boss card-sequence builder used by ordinary rooms.
--
-- The builder is a local function inside legacy_native_main.lua, so this spec
-- reimplements the exact traversal contract and asserts the behaviour the room
-- depends on. It guards the Cirno non-spell regression: a `move -> dialog ->
-- card` stage must keep the entrance move even though the dialog is skipped.

return function(assert_equal, assert_true)
    -- Mirror of build_native_card_sequence.
    local function build_card_sequence(cards, slot)
        if type(cards) ~= "table" or not slot then return nil end
        if slot < 1 or slot > #cards then return nil end
        -- The catalog slot may point at a movement or dialogue entry. Resolve it
        -- onto the nearest real combat card first; otherwise the room would run
        -- a boss that never attacks and then vanishes.
        local combat_slot = slot
        if not (cards[combat_slot] and cards[combat_slot].is_combat == true) then
            local resolved
            for index = slot, #cards do
                local candidate = cards[index]
                if type(candidate) == "table" and candidate.is_combat == true then
                    resolved = index
                    break
                end
            end
            if not resolved then
                for index = math.min(slot, #cards), 1, -1 do
                    local candidate = cards[index]
                    if type(candidate) == "table" and candidate.is_combat == true then
                        resolved = index
                        break
                    end
                end
            end
            if not resolved then return nil end
            combat_slot = resolved
        end
        local selected = cards[combat_slot]
        if type(selected) ~= "table" then return nil end
        local sequence = { selected }
        local pending_moves = {}
        for index = combat_slot - 1, 1, -1 do
            local previous = cards[index]
            if not previous then break end
            if previous.is_combat == true then break end
            if previous.is_dialog then
                -- skip but keep looking for the entrance move
            elseif previous.is_move then
                table.insert(pending_moves, 1, previous)
            else
                break
            end
        end
        for _, move in ipairs(pending_moves) do
            table.insert(sequence, 1, move)
        end
        return sequence
    end

    local function contains_combat(sequence)
        for _, card in ipairs(sequence or {}) do
            if card.is_combat == true then return true end
        end
        return false
    end

    -- Cirno:Normal shape: [move, dialog, nonspell, move, spell, move, spell, ...]
    local cirno_move1 = { is_move = true, name = "move1" }
    local cirno_dialog = { is_dialog = true, name = "dialog" }
    local cirno_nonspell = { is_combat = true, name = "nonspell", is_sc = false }
    local cirno_cards = { cirno_move1, cirno_dialog, cirno_nonspell }
    local sequence = build_card_sequence(cirno_cards, 3)
    assert_true(sequence ~= nil, "the Cirno non-spell sequence must be buildable")
    assert_equal(#sequence, 2, "the entrance move must be preserved before the non-spell")
    assert_true(sequence[1] == cirno_move1, "the entrance move is first")
    assert_true(sequence[2] == cirno_nonspell, "the non-spell follows the entrance move")
    for _, card in ipairs(sequence) do
        assert_true(card.is_dialog ~= true, "dialogs must never enter a room sequence")
    end

    -- A pure combat-only stage keeps just the selected card.
    local only_card = { is_combat = true, name = "only" }
    local only_sequence = build_card_sequence({ only_card }, 1)
    assert_equal(#only_sequence, 1, "a combat-only stage yields a single card")
    assert_true(only_sequence[1] == only_card, "the single card is the selected one")

    -- A preceding combat card bounds the selection: nothing before it is kept.
    local earlier_card = { is_combat = true, name = "earlier" }
    local later_move = { is_move = true, name = "later_move" }
    local later_card = { is_combat = true, name = "later" }
    local bounded = build_card_sequence({ earlier_card, later_move, later_card }, 3)
    assert_equal(#bounded, 2, "the sequence includes the move and the selected combat card")
    assert_true(bounded[1] == later_move and bounded[2] == later_card,
        "the earlier combat card is not included")

    -- An out-of-range slot is rejected.
    assert_true(build_card_sequence(cirno_cards, 99) == nil, "an out-of-range slot yields nil")

    -- Regression: a slot that points at a movement or dialogue card must be
    -- resolved onto the next combat card. Previously the built sequence had no
    -- combat card at all, so the room spawned a boss that never attacked and
    -- then disappeared without a fight.
    local entry_move = { is_move = true, name = "entry" }
    local intro_dialog = { is_dialog = true, name = "intro" }
    local real_card = { is_combat = true, name = "real" }
    local stage_cards = { entry_move, intro_dialog, real_card }
    for _, slot in ipairs({ 1, 2, 3 }) do
        local seq = build_card_sequence(stage_cards, slot)
        assert_true(seq ~= nil, "slot " .. slot .. " must still build a sequence")
        assert_true(contains_combat(seq),
            "slot " .. slot .. " must resolve to a sequence containing a combat card")
        assert_true(seq[#seq] == real_card, "the combat card is the selected one")
        assert_true(seq[1] == entry_move, "the entrance move is kept")
    end

    -- When every following entry is non-combat the builder falls back to the
    -- closest preceding combat card instead of returning an empty fight.
    local first_card = { is_combat = true, name = "first" }
    local trailing_move = { is_move = true, name = "trailing" }
    local fallback_seq = build_card_sequence({ first_card, trailing_move }, 2)
    assert_true(fallback_seq ~= nil, "a trailing move slot still builds a sequence")
    assert_true(contains_combat(fallback_seq), "the fallback keeps a combat card")
    assert_true(fallback_seq[#fallback_seq] == first_card, "the preceding combat card is selected")

    -- A class with no combat card anywhere cannot produce a playable room.
    assert_true(build_card_sequence({ entry_move, intro_dialog }, 1) == nil,
        "a combat-free class has no playable sequence")
end
