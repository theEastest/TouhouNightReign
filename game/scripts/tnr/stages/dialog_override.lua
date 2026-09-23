-- Runtime dialogue override.
--
-- The reference export hard-codes every boss conversation inside the compiled
-- card scripts. To make the text editable without touching code, the same
-- conversations are extracted to `dialog_text.json` (see
-- tools/extract_dialogs.py) and this module replaces the text passed to
-- `boss.dialog.sentence` with the JSON value.
--
-- Matching is positional and stable:
--   boss class  -> the legacy boss class currently running
--   block index -> the Nth `boss.dialog.New` block inside that class
--   character   -> the active player character (reimu / marisa / sanae / wuer)
--   line index  -> the Nth sentence emitted in that character's branch
--
-- If the JSON has no matching entry the original compiled text is kept, so a
-- partial or missing file never breaks a conversation.

local DialogText = {}

local loaded = nil
local load_attempted = false

local function load_json()
    if load_attempted then return loaded end
    load_attempted = true
    local ok_text, text = pcall(function()
        if lstg and type(lstg.LoadTextFile) == "function" then
            return lstg.LoadTextFile("scripts/tnr/stages/dialog_text.json")
        end
        return nil
    end)
    if not ok_text or type(text) ~= "string" or text == "" then
        -- Fall back to a direct file read for headless/development runs.
        local file = io and io.open and (io.open("scripts/tnr/stages/dialog_text.json", "rb")
            or io.open("game/scripts/tnr/stages/dialog_text.json", "rb"))
        if file then
            text = file:read("*a")
            file:close()
        end
    end
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local ok_decode, data = pcall(function()
        local cjson = require("cjson")
        return cjson.decode(text)
    end)
    if not ok_decode or type(data) ~= "table" then
        return nil
    end
    loaded = data
    return loaded
end

function DialogText.reload()
    loaded = nil
    load_attempted = false
    return load_json() ~= nil
end

--- Inject a decoded table directly (used by tests and hot-reload tooling).
function DialogText.set_data(data)
    loaded = data
    load_attempted = true
end

--- Is there an override table available?
function DialogText.is_available()
    return load_json() ~= nil
end

-- Active context set by the room layer before a dialogue card runs.
local context = {
    boss = nil,
    block = nil,
    character = nil,
    line = 0,
}

--- Reset the positional cursor. Called when a dialogue card starts.
function DialogText.begin(boss, block_index, character)
    context.boss = boss
    context.block = block_index
    context.character = character
    context.line = 0
end

function DialogText.set_character(character)
    context.character = character
    context.line = 0
end

function DialogText.end_dialogue()
    context.boss = nil
    context.block = nil
    context.line = 0
end

--- Return the override text for the next sentence, or nil to keep the
--- original compiled text.
function DialogText.next_text()
    local data = load_json()
    if not data or not context.boss or context.block == nil then return nil end
    local boss = data[context.boss]
    if not boss or type(boss.dialogues) ~= "table" then return nil end
    local chosen
    for _, dialogue in ipairs(boss.dialogues) do
        if dialogue.index == context.block then chosen = dialogue break end
    end
    if not chosen then return nil end
    local variants = chosen.variants or {}
    -- Prefer the active character's branch; fall back to the shared "all"
    -- branch when the character has no dedicated conversation.
    local function lines_for(character)
        for _, variant in ipairs(variants) do
            if variant.character == character then return variant.lines end
        end
        return nil
    end
    local lines = context.character and lines_for(context.character) or nil
    if not lines then lines = lines_for("all") end
    if not lines then return nil end
    context.line = context.line + 1
    local entry = lines[context.line]
    if not entry then return nil end
    return entry.text
end

return DialogText
