--- @class LuaTargetingMarkers 
LuaTargetingMarkers = {}

--- AdoptIntoCoroutine
--- @return nil
function LuaTargetingMarkers:AdoptIntoCoroutine()
	-- dummy implementation for documentation purposes only
end

--- AddLabel: Add a floating text label to the targeting arrow. Category can be 'buff' (green), 'debuff' (red), or 'neutral' (white, default). Call multiple times for multiple labels.
--- @param text string
--- @param category? string
function LuaTargetingMarkers:AddLabel(text, category)
	-- dummy implementation for documentation purposes only
end

--- RemoveLabel: Remove a label by its text. Returns true if a label was found and removed.
--- @param text string
function LuaTargetingMarkers:RemoveLabel(text)
	-- dummy implementation for documentation purposes only
end

--- ClearLabels: Remove all labels from the targeting arrow.
--- @return nil
function LuaTargetingMarkers:ClearLabels()
	-- dummy implementation for documentation purposes only
end

--- FlashLabels: Briefly flash all label rows on the targeting arrow red, to draw attention. Useful as feedback when a player tries to click an invalid target.
--- @return nil
function LuaTargetingMarkers:FlashLabels()
	-- dummy implementation for documentation purposes only
end

--- Retarget: Animate the targeting arrow away from its current target and onto newTarget, bending as it sweeps. The retarget is networked: all connected clients see the same animation. duration is the sweep time in seconds (default 0.5).
--- @param newTarget CharacterToken
--- @param duration? number
function LuaTargetingMarkers:Retarget(newTargetArg, duration)
	-- dummy implementation for documentation purposes only
end

--- Destroy
--- @return nil
function LuaTargetingMarkers:Destroy()
	-- dummy implementation for documentation purposes only
end
