local Preflight = {}

local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    local ok = os.rename(path, path)
    if ok then return true end
    return false
end

local function add(result, kind, path, required)
    result[#result + 1] = {
        kind = kind,
        path = path,
        required = required ~= false,
        present = exists(path),
    }
end

function Preflight.run(root, representatives)
    root = root or "."
    representatives = representatives or {}
    local result = {
        root = root,
        representatives = representatives,
        checks = {},
        ok = true,
    }
    -- These are the files that must exist for the curated native rooms to be
    -- constructible. Legacy classes are runtime identifiers, while the
    -- directories below are the concrete resource roots loaded by bootstrap.
    add(result.checks, "legacy_root", root .. "/game/legacy", true)
    add(result.checks, "asset_root", root .. "/game/assets", true)
    add(result.checks, "native_entry", root .. "/game/scripts/legacy_native_main.lua", true)
    add(result.checks, "content_catalog", root .. "/game/scripts/tnr/stages/content_catalog.lua", true)
    for _, check in ipairs(result.checks) do
        if check.required and not check.present then result.ok = false end
    end
    return result
end

return Preflight
