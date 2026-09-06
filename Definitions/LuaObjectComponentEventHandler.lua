---@meta

--- @class LuaObjectComponentEventHandler:LuaObjectComponent
LuaObjectComponentEventHandler = {}

--- GetPossibleEvents
--- @return any
function LuaObjectComponentEventHandler:GetPossibleEvents() end

--- GetEventEntry
--- @param eventid? string
--- @return any
function LuaObjectComponentEventHandler:GetEventEntry(eventid) end

--- SetEventEntry
--- @param eventid? string
--- @param handled? boolean
function LuaObjectComponentEventHandler:SetEventEntry(eventid, handled) end

--- TriggerEvent
--- @param eventid? string
function LuaObjectComponentEventHandler:TriggerEvent(eventid) end
