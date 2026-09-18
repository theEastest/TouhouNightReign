local Immutable = require("tnr.core.immutable")

local RelicDefinition = {}
local methods = {}

function RelicDefinition.new(spec)
    spec = spec or {}
    assert(type(spec.relic_id) == "string" and spec.relic_id ~= "", "relic_id is required")
    local data = {
        relic_id = spec.relic_id,
        display_name = spec.name or spec.display_name or spec.relic_id,
        tags = Immutable.copy(spec.tags or {}),
        metadata = Immutable.copy(spec.metadata or {}),
        upgrade_from = spec.upgrade_from,
        upgrade_to = spec.upgrade_to,
        character_relic = spec.character_relic == true,
    }
    return Immutable.freeze(data, methods)
end

function methods:to_table()
    return Immutable.copy(self)
end

return RelicDefinition
