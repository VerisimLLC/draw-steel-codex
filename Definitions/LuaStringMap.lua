---@meta

--- @class LuaStringMap
--- @field wrapper any
LuaStringMap = {}

--- Create
--- @overload fun(t?: any): LuaStringMap
--- @return LuaStringMap
function LuaStringMap.Create() end

--- Init
--- @overload fun()
--- @param t? any
function LuaStringMap:Init(t) end

--- Set
--- @param key? string
--- @param value? any
function LuaStringMap:Set(key, value) end

--- Get
--- @param key? string
--- @return any
function LuaStringMap:Get(key) end

--- Clear
function LuaStringMap:Clear() end
