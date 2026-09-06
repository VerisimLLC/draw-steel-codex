---@meta

--- @class LuaCodeModDocumentSnapshot
--- @field modid string
--- @field docid string
--- @field path string
--- @field data any
--- @field isnew boolean
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
