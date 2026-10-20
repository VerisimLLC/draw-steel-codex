---@meta

--- @class SoundEventInstanceLua
--- @field eventVolume number (Read-only) The volume the sound event computed for this play: the event's volume x args.volume x any localVolume/controlledVolume multiplier x the mix-group sliders. Separate from volume, which is an extra multiplier Lua can set.
--- @field volume number
--- @field playing boolean
--- @field mixGroupId any
--- @field solo boolean
--- @field loop boolean Whether this instance starts its clip again each time it reaches the end, until stopped. asset:Play() starts with it off; scene sounds (SceneElements.lua) turn it on for a looping clip.
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
