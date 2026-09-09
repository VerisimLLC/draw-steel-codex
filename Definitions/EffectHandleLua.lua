---@meta

--- @class EffectHandleLua
EffectHandleLua = {}

--- Stop emission immediately; live particles fade out naturally.
function EffectHandleLua:Stop() end

--- Move the effect to a new location.
--- @param pos Loc
function EffectHandleLua:Position(pos) end

--- Resize the effect.
--- @param scale? number
function EffectHandleLua:Scale(scale) end

--- Rotate the effect, in degrees. Sets the effect's local rotation about the Z axis (an in-plane spin on the top-down map -- useful for aiming a directional effect at a target). Replaces any prior rotation rather than accumulating.
--- @param degrees? number
function EffectHandleLua:Rotate(degrees) end
