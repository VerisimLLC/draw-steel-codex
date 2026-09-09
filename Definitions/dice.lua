---@meta

--- The main interface for registering and managing dice sets, video effects, and dice preview interactions.
--- @class dice
--- @field defaultDiceSet DiceSetLua The default dice set used when no specific set is selected.
--- @field effects table<string, DiceVideoEffectLua> A table mapping effect id to its DiceVideoEffectLua instance.
--- @field diceSets table<string, DiceSetLua> A table mapping dice set id to its DiceSetLua instance.
dice = {}

--- Registers a new video effect from a table definition.
--- @param table table The video effect properties including id, video, blend, scale, etc.
function dice:Effect(table) end

--- Registers a new dice set from a table definition. Currently disabled.
--- @param table table The dice set properties including id, model, color, etc.
function dice:Set(table) end

--- Returns a list of dice sets available to the current user, including owned dice from the shop.
--- @return table
function dice.GetAvailableDice() end

--- Returns a list of all dice sets registered in the system, regardless of ownership.
--- @return table
function dice.GetAllDice() end

--- Returns the 'slots' authored on an uploaded dice set (see the Dice Studio Slots section): an array of tables, each with a slotType field -- 'damage' entries carry a damageType string; 'class' entries carry a classid string and an optional subclassid string; 'monster' entries carry a groupid string (a MonsterGroup table id). Returns an empty table if the dice set has no slots or the id is unknown. The result is a copy; mutating it does not change the dice set.
--- @param assetid string  The cloud dice id (guid).
--- @return table
function dice.GetDiceSlots(assetid) end

--- Returns a dice preview scene object for rendering dice in a UI context.
--- @return LuaDicePreviewScene
function dice.GetPreviewScene() end

--- Notifies all preview dice that the mouse has entered their area.
function dice.MouseEnter() end

--- Notifies all preview dice that the mouse has left their area.
function dice.MouseLeave() end

--- Updates the mouse hover state on all preview dice each frame while hovering.
function dice.MouseHoverThink() end

--- Handles a click event on the preview dice.
function dice.Click() end

--- Updates the drag state on all preview dice each frame while dragging.
function dice.DragThink() end

--- Handles the end of a drag operation on all preview dice.
function dice.DragEnd() end

--- Sets whether preview dice bounce off the actual screen edges instead of the default playfield box. When true, a tossed die rolls across the whole screen and only the screen edges and the floor act as boundaries. This overrides the tight dice-cage box even when a preview panel (SetAsDicePreviewPanel) is registered, so the shop 'try dice' feature can anchor a resting die to its panel yet still roll out across the whole screen. The in-game roll dialog leaves this false, keeping its tight embedded cage. The shop should set this true while the try-dice UI is shown and false when it closes.
--- @param val? boolean
function dice.SetPreviewRollScreenBounds(val) end

--- Scales the gap between resting dice on an embedded preview panel (e.g. the shop 'try dice' pair). 1 is the default spacing; values below 1 pull the dice closer together, above 1 push them apart. Only affects panel-anchored preview dice, not the in-game roll dialog. The shop should set this while its try-dice UI is shown and reset it to 1 when the UI closes.
--- @param scale? number
function dice.SetPreviewDiceSpacing(scale) end

--- Scales the RESTING size of embedded preview dice (e.g. the Dice dock panel's tiles). 1 is the default size; values below 1 make the resting dice smaller so they sit neatly on a small tile and then visibly grow when hovered or thrown (the hover/roll sizes are unaffected). Only affects panel-anchored preview dice, not the in-game roll dialog. Set it while the panel is shown and reset it to 1 when the panel closes.
--- @param scale? number
function dice.SetPreviewDiceScale(scale) end

--- Sets the drag-to-spin state on a pooled dice preview -- one shown via a '#DicePreview:<key>' bgimage, e.g. the store banner's mini dice showcase (each of these renders its own idle-spinning die). Pass the same '<assetid>:<seq>' key the bgimage uses, and true when the die is grabbed / false when released: while true the die spins straight from the cursor (like the shop banner die), then eases back to its idle spin. A no-op if that preview isn't currently on screen. Does NOT affect the shared roll/banner preview scene (dice.GetPreviewScene) or the panel-anchored 'try dice' cages.
--- @param key? string
--- @param dragging? boolean
function dice.SetPreviewDragging(key, dragging) end

--- Overrides the dice appearance used by subsequent rolls with the given dice-set asset id, so dice the player doesn't own yet (e.g. a shop item being previewed) can still be rolled -- the equipped-dice setting rejects unowned sets, but this bypasses it. Pass nil or an empty string to clear the override and return to the player's equipped set.
--- @param assetid? string
function dice.SetRollPreviewModel(assetid) end

--- Makes subsequent rolls use the given dice-set asset id for EVERY die instead of the equipped loadout, because a dice 'slot' activation (the diceslotsequipped setting) matched the roll being prepared -- e.g. fire-damage dice for a power roll dealing fire damage. The roll dialog sets this when it opens on a matching roll and clears it when the roll completes or is cancelled. Unlike SetRollPreviewModel this is a real networked roll: each die records the set it was skinned with, so all clients replay the same look. A shop try-dice override or an active Dice Studio set takes precedence while it is up. Pass nil or an empty string to clear.
--- @param assetid string|nil  The cloud dice id (guid), or nil/'' to clear.
--- @return nil
function dice.SetRollSlotDice(assetid) end

--- Makes subsequent rolls use the given dice LOADOUT instead of the player's equipped one -- the same three-part shape as the equipped loadout, so a roll can mix sets. Used by the roll dialog when the token being rolled for has customized dice of its own (see the creature 'diceLoadout' property). The loadout must be fully resolved before it is passed: an empty model2/modelD6 means 'use model for those dice' (exactly as with the equipped loadout), NOT 'inherit the account setting', and the CALLER must have already dropped any set the rolling player does not own -- this is not a way to roll dice you have not bought. Like SetRollSlotDice (which is just this with only a primary set) it is a real networked roll: each die records the set it was skinned with, so all clients replay the same look. A shop try-dice override or an active Dice Studio set takes precedence while it is up. Pass nil or an empty model to clear.
--- @param model string|nil  The cloud dice id (guid) for the first power d10 and every die another field does not override, or nil/'' to clear the whole override.
--- @param model2 string|nil  The cloud dice id for the second d10 -- any roll with multiple d10s alternates between model and model2. nil/'' = use model.
--- @param modelD6 string|nil  The cloud dice id for d6- and d3-shaped dice. nil/'' = use model.
--- @return nil
function dice.SetRollLoadout(model, model2, modelD6) end
