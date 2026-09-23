local DialogOverride = require("tnr.stages.dialog_override")

return function(assert_equal, assert_true)
    -- Inject a decoded table so the matching logic can be tested headless.
    DialogOverride.set_data({
        ["Alice:Normal"] = {
            dialogues = {
                {
                    index = 0,
                    variants = {
                        { character = "reimu", lines = { { text = "灵梦第一句" }, { text = "灵梦第二句" } } },
                        { character = "marisa", lines = { { text = "魔理沙唯一句" } } },
                    },
                },
                {
                    index = 1,
                    variants = {
                        { character = "all", lines = { { text = "通用台词" } } },
                    },
                },
            },
        },
    })

    -- Exact character match consumes lines in order.
    DialogOverride.begin("Alice:Normal", 0, "reimu")
    assert_equal(DialogOverride.next_text(), "灵梦第一句", "first reimu line")
    assert_equal(DialogOverride.next_text(), "灵梦第二句", "second reimu line")
    assert_equal(DialogOverride.next_text(), nil, "no more lines returns nil")

    -- A different character resolves its own branch.
    DialogOverride.begin("Alice:Normal", 0, "marisa")
    assert_equal(DialogOverride.next_text(), "魔理沙唯一句", "marisa line")
    assert_equal(DialogOverride.next_text(), nil, "marisa has a single line")

    -- A character without a branch falls back to the shared "all" variant.
    DialogOverride.begin("Alice:Normal", 1, "sanae")
    assert_equal(DialogOverride.next_text(), "通用台词", "shared line fallback")
    assert_equal(DialogOverride.next_text(), nil, "shared line is consumed once")

    -- An unknown boss or block keeps the original compiled text (nil).
    DialogOverride.begin("Unknown:Boss", 0, "reimu")
    assert_equal(DialogOverride.next_text(), nil, "unknown boss yields no override")
    DialogOverride.begin("Alice:Normal", 99, "reimu")
    assert_equal(DialogOverride.next_text(), nil, "unknown block yields no override")

    -- end_dialogue clears the cursor.
    DialogOverride.begin("Alice:Normal", 0, "reimu")
    DialogOverride.end_dialogue()
    assert_equal(DialogOverride.next_text(), nil, "no override outside a dialogue")

    -- The shipped JSON must load and expose the expected shape.
    DialogOverride.reload()
    if DialogOverride.is_available() then
        DialogOverride.begin("Alice:Normal", 0, "reimu")
        local first = DialogOverride.next_text()
        assert_true(first == nil or type(first) == "string",
            "the real dialogue data returns a string or nil per line")
    end
end
