---@meta

--- @class LuaObjectComponentKeyFrame:LuaObjectComponent
--- @field keyFrames any
LuaObjectComponentKeyFrame = {}

--- RecreateResetState
function LuaObjectComponentKeyFrame:RecreateResetState() end

--- RestoreKeyFrame
--- @param index? number
function LuaObjectComponentKeyFrame:RestoreKeyFrame(index) end

--- DeleteKeyFrame
--- @param index? number
function LuaObjectComponentKeyFrame:DeleteKeyFrame(index) end
