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

--- GetDiceSlots: Returns the 'slots' authored on an uploaded dice set (see the Dice Studio Slots section): an array of tables, each with a slotType field -- 'damage' entries carry a damageType string; 'class' entries carry a classid string and an optional subclassid string; 'monster' entries carry a groupid string (a MonsterGroup table id). Returns an empty table if the dice set has no slots or the id is unknown. The result is a copy; mutating it does not change the dice set.
--- @param assetid string  The cloud dice id (guid).
--- @return table
function dice.GetDiceSlots(assetid)
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

--- SetPreviewDragging: Sets the drag-to-spin state on a pooled dice preview -- one shown via a '#DicePreview:<key>' bgimage, e.g. the store banner's mini dice showcase (each of these renders its own idle-spinning die). Pass the same '<assetid>:<seq>' key the bgimage uses, and true when the die is grabbed / false when released: while true the die spins straight from the cursor (like the shop banner die), then eases back to its idle spin. A no-op if that preview isn't currently on screen. Does NOT affect the shared roll/banner preview scene (dice.GetPreviewScene) or the panel-anchored 'try dice' cages.
--- @param key string
--- @param dragging boolean
--- @return nil
function dice.SetPreviewDragging(key, dragging)
	-- dummy implementation for documentation purposes only
end

--- SetRollPreviewModel: Overrides the dice appearance used by subsequent rolls with the given dice-set asset id, so dice the player doesn't own yet (e.g. a shop item being previewed) can still be rolled -- the equipped-dice setting rejects unowned sets, but this bypasses it. Pass nil or an empty string to clear the override and return to the player's equipped set.
--- @param assetid string
--- @return nil
function dice.SetRollPreviewModel(assetid)
	-- dummy implementation for documentation purposes only
end

--- SetRollSlotDice: Makes subsequent rolls use the given dice-set asset id for EVERY die instead of the equipped loadout, because a dice 'slot' activation (the diceslotsequipped setting) matched the roll being prepared -- e.g. fire-damage dice for a power roll dealing fire damage. The roll dialog sets this when it opens on a matching roll and clears it when the roll completes or is cancelled. Unlike SetRollPreviewModel this is a real networked roll: each die records the set it was skinned with, so all clients replay the same look. A shop try-dice override or an active Dice Studio set takes precedence while it is up. Pass nil or an empty string to clear.
--- @param assetid string|nil  The cloud dice id (guid), or nil/'' to clear.
--- @return nil
function dice.SetRollSlotDice(assetid)
	-- dummy implementation for documentation purposes only
end
