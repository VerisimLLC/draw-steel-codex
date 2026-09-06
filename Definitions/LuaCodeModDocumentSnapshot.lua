---@meta

--- @class LuaCodeModDocumentSnapshot
LuaCodeModDocumentSnapshot = {}

--- Transaction
--- @param fn? any
function LuaCodeModDocumentSnapshot:Transaction(fn) end

--- BeginChange
function LuaCodeModDocumentSnapshot:BeginChange() end

--- CompleteChange
--- @param description? string
--- @param args? any
function LuaCodeModDocumentSnapshot:CompleteChange(description, args) end
