---@meta

--- @class LuaPartyInfo
--- @field id any
--- @field valid any
--- @field type any
--- @field properties any
--- @field partyid string
--- @field partyDetails any
LuaPartyInfo = {}

--- BeginChanges
function LuaPartyInfo:BeginChanges() end

--- CompleteChanges
--- @param description? string
function LuaPartyInfo:CompleteChanges(description) end
