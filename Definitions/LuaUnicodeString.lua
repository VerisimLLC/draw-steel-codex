---@meta

--- @class LuaUnicodeString
--- @field Length number
--- @field str string
LuaUnicodeString = {}

--- Substring
--- @param beginIndex? number
--- @param endIndex? number
--- @return any
function LuaUnicodeString:Substring(beginIndex, endIndex) end

--- DeepCopy
--- @return any
function LuaUnicodeString:DeepCopy() end

--- Serialize
--- @return any
function LuaUnicodeString:Serialize() end

--- Deserialize
--- @param dict? any
function LuaUnicodeString:Deserialize(dict) end

--- Equals
--- @param other? any
--- @return boolean
function LuaUnicodeString:Equals(other) end
