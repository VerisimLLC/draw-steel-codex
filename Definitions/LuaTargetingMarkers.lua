---@meta

--- @class LuaTargetingMarkers
LuaTargetingMarkers = {}

--- AdoptIntoCoroutine
function LuaTargetingMarkers:AdoptIntoCoroutine() end

--- Add a floating text label to the targeting arrow. Category can be 'buff' (green), 'debuff' (red), or 'neutral' (white, default). Call multiple times for multiple labels.
--- @param text string
--- @param category string
function LuaTargetingMarkers:AddLabel(text, category) end

--- Remove a label by its text. Returns true if a label was found and removed.
--- @param text string
--- @return boolean
function LuaTargetingMarkers:RemoveLabel(text) end

--- Remove all labels from the targeting arrow.
function LuaTargetingMarkers:ClearLabels() end

--- Briefly flash all label rows on the targeting arrow red, to draw attention. Useful as feedback when a player tries to click an invalid target.
function LuaTargetingMarkers:FlashLabels() end

--- Animate the targeting arrow away from its current target and onto newTarget, bending as it sweeps. The retarget is networked: all connected clients see the same animation. duration is the sweep time in seconds (default 0.5).
--- @param newTarget CharacterToken
--- @param duration number
function LuaTargetingMarkers:Retarget(newTarget, duration) end

--- DestroyLineOfSight
--- @deprecated
function LuaTargetingMarkers:DestroyLineOfSight() end

--- Destroy
function LuaTargetingMarkers:Destroy() end
