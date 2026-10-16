---@meta

--- @class LuaTargetableObject:LuaObjectComponent
LuaTargetableObject = {}

--- Turns the object to face a world position while an ability is being aimed (a ballista tracking its target). Local only: nothing is saved or sent. It turns at the component's Turn Speed, using its Facing to know which way the art points. End with ClearAim, or CommitAim to keep the facing.
--- @param x? number
--- @param y? number
function LuaTargetableObject:AimAt(x, y) end

--- Stops aiming: the object turns back to its saved rotation.
function LuaTargetableObject:ClearAim() end

--- Saves the direction the object is aiming as its rotation, so it keeps facing that way for everyone, then stops aiming. Other clients see it turn at its Turn Speed.
function LuaTargetableObject:CommitAim() end

--- OnDeath
function LuaTargetableObject:OnDeath() end
