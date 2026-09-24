-- Shared registry for the title screen assets.
--
-- The game runs project scripts in a sandbox where the global table differs
-- from the one the boot harness sees, so sizes cannot be published on `_G`.
-- A required module is the one table both sides are guaranteed to share.
local TitleAssets = {
    bg = nil,
    logo = nil,
    icons = {},
    ready = false,
}

function TitleAssets.set(name, width, height)
    if not name or not width or not height then return end
    local entry = { width = width, height = height }
    if name == "tnr-title-bg" then
        TitleAssets.bg = entry
    elseif name == "tnr-title-logo" then
        TitleAssets.logo = entry
    else
        TitleAssets.icons[name] = entry
    end
end

function TitleAssets.get(name)
    if name == "tnr-title-bg" then return TitleAssets.bg end
    if name == "tnr-title-logo" then return TitleAssets.logo end
    return TitleAssets.icons[name]
end

return TitleAssets
