local NetworkMenu = {}
NetworkMenu.__index = NetworkMenu

local DEFAULT_PORT = "27123"

local function trim(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

local function append_filtered(current, text, pattern, maximum_length)
    local accepted = {}
    for character in tostring(text or ""):gmatch(".") do
        if character:match(pattern) then accepted[#accepted + 1] = character end
    end
    return (current .. table.concat(accepted)):sub(1, maximum_length)
end

function NetworkMenu.new()
    return setmetatable({
        mode = nil, cursor = 1, ip = "localhost", port = DEFAULT_PORT, seed = "",
        status = nil, status_is_error = false, replace_on_input = {},
    }, NetworkMenu)
end

function NetworkMenu:is_open() return self.mode == "host" or self.mode == "client" end

function NetworkMenu:open(mode)
    assert(mode == "host" or mode == "client", "invalid network menu mode")
    self.mode, self.cursor, self.status, self.status_is_error = mode, 1, nil, false
    self.replace_on_input = { [1] = true, [2] = true, [3] = true }
    if self.port == "" then self.port = DEFAULT_PORT end
    if self.ip == "" then self.ip = "localhost" end
    return self
end

function NetworkMenu:close()
    self.mode, self.cursor, self.status, self.status_is_error = nil, 1, nil, false
    self.replace_on_input = {}
end

function NetworkMenu:get_fields()
    if self.mode == "host" then
        return {
            { id = "port", label = "PORT", value = self.port, placeholder = DEFAULT_PORT },
            { id = "seed", label = "SEED", value = self.seed, placeholder = "blank = random" },
        }
    end
    return {
        { id = "ip", label = "SERVER IP", value = self.ip, placeholder = "localhost" },
        { id = "port", label = "PORT", value = self.port, placeholder = DEFAULT_PORT },
    }
end

function NetworkMenu:get_item_count() return #self:get_fields() + 1 end
function NetworkMenu:get_action_label() return self.mode == "host" and "START LISTENING" or "CONNECT" end

function NetworkMenu:move_cursor(direction)
    if direction == 0 then return end
    local count = self:get_item_count()
    self.cursor = ((self.cursor - 1 + direction) % count) + 1
end

function NetworkMenu:append_text(text)
    local field = self:get_fields()[self.cursor]
    if not field then return end
    local replace = self.replace_on_input[self.cursor] == true
    self.replace_on_input[self.cursor] = false
    if field.id == "ip" then
        self.ip = append_filtered(replace and "" or self.ip, text, "[A-Za-z0-9%.:%-]", 253)
    elseif field.id == "port" then
        self.port = append_filtered(replace and "" or self.port, text, "%d", 5)
    elseif field.id == "seed" then
        self.seed = append_filtered(replace and "" or self.seed, text, "%d", 10)
    end
end

function NetworkMenu:backspace()
    local field = self:get_fields()[self.cursor]
    if not field then return end
    if self.replace_on_input[self.cursor] then
        if field.id == "ip" then self.ip = ""
        elseif field.id == "port" then self.port = ""
        else self.seed = "" end
        self.replace_on_input[self.cursor] = false
        return
    end
    if field.id == "ip" then self.ip = self.ip:sub(1, math.max(0, #self.ip - 1))
    elseif field.id == "port" then self.port = self.port:sub(1, math.max(0, #self.port - 1))
    elseif field.id == "seed" then self.seed = self.seed:sub(1, math.max(0, #self.seed - 1)) end
end

function NetworkMenu:set_error(message)
    self.status, self.status_is_error = tostring(message or "connection failed"), true
end

function NetworkMenu:validate()
    local port = tonumber(trim(self.port))
    if not port or port % 1 ~= 0 or port < 1 or port > 65535 then
        return nil, "port must be an integer from 1 to 65535"
    end
    local host = self.mode == "host" and "0.0.0.0" or trim(self.ip)
    if self.mode == "client" then
        if host == "" then return nil, "enter server IP or localhost" end
        if not host:match("^[A-Za-z0-9%.:%-]+$") then return nil, "server address contains unsupported characters" end
    end
    local seed
    if self.mode == "host" and trim(self.seed) ~= "" then
        seed = tonumber(trim(self.seed))
        if not seed or seed % 1 ~= 0 or seed < 1 or seed > 2147483647 then
            return nil, "seed must be an integer from 1 to 2147483647"
        end
        seed = math.floor(seed)
    end
    return { mode = self.mode, host = host, port = port, seed = seed }
end

function NetworkMenu:confirm()
    local field_count = #self:get_fields()
    if self.mode == "host" and self.cursor == 1 and trim(self.seed) == "" then
        local config, err = self:validate()
        if not config then self:set_error(err); return nil, err end
        return config
    end
    if self.cursor < field_count then
        -- Validate fields already entered before advancing. This keeps the
        -- original one-step invalid-port feedback while allowing the host's
        -- optional seed field to remain blank.
        local _, err = self:validate()
        if err then self:set_error(err); return nil, err end
        self.cursor = self.cursor + 1
        return nil
    end
    local config, err = self:validate()
    if not config then self:set_error(err); return nil, err end
    return config
end

return NetworkMenu
