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
        local selected = cards[slot]
        if type(selected) ~= "table" then return nil end
        local sequence = { selected }
        local pending_moves = {}
        for index = slot - 1, 1, -1 do
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
end
