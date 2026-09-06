---@meta

--- @class LuaPartyInfo
--- @field id any
--- @field valid any
--- @field type any
--- @field properties any
LuaPartyInfo = {}

--- BeginChanges
function LuaPartyInfo:BeginChanges() end

--- CompleteChanges
--- @param description? string
function LuaPartyInfo:CompleteChanges(description) end
