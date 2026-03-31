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

--- Destroy
--- @return nil
function LuaTargetingMarkers:Destroy()
	-- dummy implementation for documentation purposes only
end
