--- @class dice The main interface for registering and managing dice sets, video effects, and dice preview interactions.
--- @field defaultDiceSet any The default dice set used when no specific set is selected.
dice = {}

--- Effect: Registers a new video effect from a table definition.
--- @param table table The video effect properties including id, video, blend, scale, etc.
function dice:Effect(table)
	-- dummy implementation for documentation purposes only
end

--- Set: Registers a new dice set from a table definition. Currently disabled.
--- @param table table The dice set properties including id, model, color, etc.
function dice:Set(table)
	-- dummy implementation for documentation purposes only
end

--- GetAvailableDice: Returns a list of dice sets available to the current user, including owned dice from the shop.
--- @return table
function dice.GetAvailableDice()
	-- dummy implementation for documentation purposes only
end

--- GetAllDice: Returns a list of all dice sets registered in the system, regardless of ownership.
--- @return table
function dice.GetAllDice()
	-- dummy implementation for documentation purposes only
end

--- GetPreviewScene: Returns a dice preview scene object for rendering dice in a UI context.
--- @return LuaDicePreviewScene
function dice.GetPreviewScene()
	-- dummy implementation for documentation purposes only
end

--- MouseEnter: Notifies all preview dice that the mouse has entered their area.
--- @return nil
function dice.MouseEnter()
	-- dummy implementation for documentation purposes only
end

--- MouseLeave: Notifies all preview dice that the mouse has left their area.
--- @return nil
function dice.MouseLeave()
	-- dummy implementation for documentation purposes only
end

--- MouseHoverThink: Updates the mouse hover state on all preview dice each frame while hovering.
--- @return nil
function dice.MouseHoverThink()
	-- dummy implementation for documentation purposes only
end

--- Click: Handles a click event on the preview dice.
--- @return nil
function dice.Click()
	-- dummy implementation for documentation purposes only
end

--- DragThink: Updates the drag state on all preview dice each frame while dragging.
--- @return nil
function dice.DragThink()
	-- dummy implementation for documentation purposes only
end

--- DragEnd: Handles the end of a drag operation on all preview dice.
--- @return nil
function dice.DragEnd()
	-- dummy implementation for documentation purposes only
end
