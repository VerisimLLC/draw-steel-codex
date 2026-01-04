--- Manages state for the character builder
--- @class CharacterBuilderState
--- @field data table The root data table containing all state
local CharacterBuilderState = RegisterGameType("CharacterBuilderState")

--- Creates a new CharacterBuilderState instance
--- @return CharacterBuilderState
function CharacterBuilderState.CreateNew()
    return CharacterBuilderState.new{data = {}}
end

--- Sets a value at the specified path in the data table
--- Creates intermediate tables as needed
--- @param key string Dot-separated path (e.g., "path.to.value")
--- @param value any The value to set at the path
function CharacterBuilderState:_setKey(key, value)
    local parts = {}
    for part in key:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    local current = self.data

    -- Navigate/create path up to the last key
    for i = 1, #parts - 1 do
        if current[parts[i]] == nil then
            current[parts[i]] = {}
        end
        current = current[parts[i]]
    end

    -- Set the final value
    current[parts[#parts]] = value
end

--- Sets values in paths in the data table
--- @param items table {key = x1, value = y1} or {{key = x1, value = y1}, {key = x2, value = y2},---}
function CharacterBuilderState:Set(items)
    if items[1] ~= nil then
        for _,item in ipairs(items) do
            self:_setKey(item.key, item.value)
        end
    else
        self:_setKey(items.key, items.value)
    end
end

--- Gets a value at the specified path in the data table
--- @param key string Dot-separated path (e.g., "path.to.value")
--- @return any|nil The value at the path, or nil if any part doesn't exist
function CharacterBuilderState:Get(key)
    local parts = {}
    for part in key:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    local current = self.data

    -- Navigate through the path
    for i = 1, #parts do
        if current == nil or type(current) ~= "table" then
            return nil
        end
        current = current[parts[i]]
    end

    return current
end
