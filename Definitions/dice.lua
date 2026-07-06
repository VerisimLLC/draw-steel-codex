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

--- SetPreviewRollScreenBounds: Sets whether preview dice bounce off the actual screen edges instead of the default playfield box. When true, a tossed die rolls across the whole screen and only the screen edges and the floor act as boundaries. This overrides the tight dice-cage box even when a preview panel (SetAsDicePreviewPanel) is registered, so the shop 'try dice' feature can anchor a resting die to its panel yet still roll out across the whole screen. The in-game roll dialog leaves this false, keeping its tight embedded cage. The shop should set this true while the try-dice UI is shown and false when it closes.
--- @param val boolean
--- @return nil
function dice.SetPreviewRollScreenBounds(val)
	-- dummy implementation for documentation purposes only
end

--- SetPreviewDiceSpacing: Scales the gap between resting dice on an embedded preview panel (e.g. the shop 'try dice' pair). 1 is the default spacing; values below 1 pull the dice closer together, above 1 push them apart. Only affects panel-anchored preview dice, not the in-game roll dialog. The shop should set this while its try-dice UI is shown and reset it to 1 when the UI closes.
--- @param scale number
--- @return nil
function dice.SetPreviewDiceSpacing(scale)
	-- dummy implementation for documentation purposes only
end

--- SetPreviewDiceScale: Scales the RESTING size of embedded preview dice (e.g. the Dice dock panel's tiles). 1 is the default size; values below 1 make the resting dice smaller so they sit neatly on a small tile and then visibly grow when hovered or thrown (the hover/roll sizes are unaffected). Only affects panel-anchored preview dice, not the in-game roll dialog. Set it while the panel is shown and reset it to 1 when the panel closes.
--- @param scale number
--- @return nil
function dice.SetPreviewDiceScale(scale)
	-- dummy implementation for documentation purposes only
end

--- SetRollPreviewModel: Overrides the dice appearance used by subsequent rolls with the given dice-set asset id, so dice the player doesn't own yet (e.g. a shop item being previewed) can still be rolled -- the equipped-dice setting rejects unowned sets, but this bypasses it. Pass nil or an empty string to clear the override and return to the player's equipped set.
--- @param assetid string
--- @return nil
function dice.SetRollPreviewModel(assetid)
	-- dummy implementation for documentation purposes only
end
