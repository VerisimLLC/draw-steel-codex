---@meta

--- @class SoundEventInstanceLua
--- @field volume number
--- @field playing boolean
--- @field mixGroupId any
--- @field solo boolean
--- @field pitch number
--- @field delay number
--- @field time number
--- @field duration number
--- @field args any
SoundEventInstanceLua = {}

--- SetStopAfter
--- @param duration? number
function SoundEventInstanceLua:SetStopAfter(duration) end

--- Stop
function SoundEventInstanceLua:Stop() end
