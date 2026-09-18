-- Shared list scrolling model for menus and inventory-style views.
-- It deliberately contains no engine calls so keyboard behavior can be tested
-- independently from rendering.
local ScrollState = {}
ScrollState.__index = ScrollState

local INITIAL_DELAY = 12
local REPEAT_RATE = 4

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function ScrollState.new(item_count, visible_count, cursor)
    local self = setmetatable({
        item_count = math.max(0, tonumber(item_count) or 0),
        visible_count = math.max(1, tonumber(visible_count) or 1),
        cursor = math.max(1, tonumber(cursor) or 1),
        hold_direction = 0,
        hold_frames = 0,
    }, ScrollState)
    self.cursor = clamp(self.cursor, 1, math.max(1, self.item_count))
    return self
end

function ScrollState:set_count(item_count, visible_count)
    self.item_count = math.max(0, tonumber(item_count) or 0)
    self.visible_count = math.max(1, tonumber(visible_count) or self.visible_count or 1)
    self.cursor = clamp(self.cursor, 1, math.max(1, self.item_count))
end

function ScrollState:set_cursor(cursor)
    self.cursor = clamp(tonumber(cursor) or 1, 1, math.max(1, self.item_count))
    return self.cursor
end

function ScrollState:_move_once(direction)
    if self.item_count <= 0 or direction == 0 then return self.cursor end
    self.cursor = ((self.cursor - 1 + direction) % self.item_count) + 1
    return self.cursor
end

-- Returns the cursor after applying a direction for one frame. Initial press
-- moves immediately; holding repeats after a short delay at a stable rate.
function ScrollState:update(direction)
    direction = direction or 0
    if direction == 0 then
        self.hold_direction = 0
        self.hold_frames = 0
        return self.cursor
    end
    direction = direction > 0 and 1 or -1
    if direction ~= self.hold_direction then
        self.hold_direction = direction
        self.hold_frames = 1
        return self:_move_once(direction)
    end
    self.hold_frames = self.hold_frames + 1
    if self.hold_frames > INITIAL_DELAY
            and (self.hold_frames - INITIAL_DELAY) % REPEAT_RATE == 0 then
        return self:_move_once(direction)
    end
    return self.cursor
end

function ScrollState:first_visible()
    local overflow = math.max(0, self.item_count - self.visible_count)
    return clamp(self.cursor - self.visible_count + 1, 1, overflow + 1)
end

function ScrollState:set_from_track(normalized)
    if self.item_count <= self.visible_count then
        return self.cursor
    end
    self.cursor = math.floor(clamp(tonumber(normalized) or 0, 0, 1) * (self.item_count - 1) + 0.5) + 1
    return self.cursor
end

return ScrollState
