--- @class DicePreview:Panel 
--- @field dicePreviewVirtual boolean (default=false) For dice-preview cage panels (SetAsDicePreviewPanel): when true, the cage's resting preview dice are rendered into an off-screen texture and displayed as a regular image inside the panel, obeying panel ordering -- dialogs opened over the panel cover them. The dice seamlessly become real 3D dice compositing over the whole UI while hovered, dragged or rolling.
--- @field dicePreviewRestScale number (default=1) For dice-preview cage panels (SetAsDicePreviewPanel): scales the RESTING size of this cage's preview dice, like dice.SetPreviewDiceScale but scoped to this cage only. Values below 1 make the resting dice smaller so they sit neatly on a small tile and then visibly grow when hovered or thrown (hover/roll sizes are unaffected). Used by the Dice dock panel so its tuning never affects the shop or roll-dialog dice.
--- @field dicePreviewSpacing number (default=1) For dice-preview cage panels (SetAsDicePreviewPanel): scales the gap between this cage's resting dice, like dice.SetPreviewDiceSpacing but scoped to this cage only. Values below 1 pull the dice closer together, above 1 push them apart.
--- @field dicePreviewRestSpacing number (default=1) For dice-preview cage panels (SetAsDicePreviewPanel): contracts the gap between this cage's RESTING dice only, on top of dicePreviewSpacing. Values below 1 pull the resting dice toward the cage centre; on hover (and when thrown) they animate back out to the positions dicePreviewSpacing authored, in step with the hover size pop. Used by the Dice dock's Power Roll pair to rest tight but spread to the standard layout when hovered.
--- @field dicePreviewScaleSpeed number (default=1) For dice-preview cage panels (SetAsDicePreviewPanel): multiplies how fast this cage's preview dice animate between their resting and hover sizes. Cages that shrink their resting dice a lot (dicePreviewRestScale well below 1) should raise this so the hover pop stays snappy -- the underlying animation moves at a fixed rate, so a bigger size gap otherwise takes proportionally longer.
--- @field dicePreviewScreenBounds boolean (default=false) For dice-preview cage panels (SetAsDicePreviewPanel): when true, dice thrown from this cage roll out to the real screen edges instead of a tight box around the panel, like dice.SetPreviewRollScreenBounds but scoped to this cage only.
--- @field dicePreviewLiftDrop boolean (default=false) For dice-preview cage panels (SetAsDicePreviewPanel): when true, this cage's resting dice are lifted a little as they are picked up and dragged, and releasing them gently (without a hurl) drops them from that altitude so they fall and land with an impact instead of cancelling back to rest. A quick flick still tosses them into a full roll as usual. Used by the shop 'try dice' cages.
--- @field dicePreviewHoverFx boolean (default=false) For dice-preview cage panels (SetAsDicePreviewPanel): when true, this cage's dice show NO particle effects while they rest -- the die alone sits on the tile. Hovering or dragging a die re-spawns its dice set's effects, and moving the mouse off strips them again (a thrown die keeps them). Used by the Dice dock, whose resting dice render inside the panel: dice FX always composite over the whole UI, so a resting tile's effects would draw over dialogs the die itself sits behind.
DicePreview = {}

--- SetAsDicePreviewPanel: Registers (true) or unregisters (false) this panel as a dice-preview cage that resting preview dice anchor to. Multiple panels may be registered at once; each cage seeds its own dice by passing previewPanel = <panel> to dmhub.Roll{preview = true, ...} and routes its input through the DicePreview* methods on this panel.
--- @param val boolean
--- @return nil
function DicePreview:SetAsDicePreviewPanel(val)
	-- dummy implementation for documentation purposes only
end

--- DicePreviewMouseEnter: Notifies the preview dice resting on this cage panel that the mouse has entered their area. Panel-scoped equivalent of dice.MouseEnter.
--- @return nil
function DicePreview:DicePreviewMouseEnter()
	-- dummy implementation for documentation purposes only
end

--- DicePreviewMouseLeave: Notifies the preview dice resting on this cage panel that the mouse has left their area. Panel-scoped equivalent of dice.MouseLeave.
--- @return nil
function DicePreview:DicePreviewMouseLeave()
	-- dummy implementation for documentation purposes only
end

--- DicePreviewClick: Handles a click on the preview dice resting on this cage panel, executing the roll armed by dmhub.Roll{preview = true, previewPanel = <this panel>}. Panel-scoped equivalent of dice.Click.
--- @return nil
function DicePreview:DicePreviewClick()
	-- dummy implementation for documentation purposes only
end

--- DicePreviewDragThink: Updates the drag state of the preview dice resting on this cage panel each frame while dragging. Panel-scoped equivalent of dice.DragThink.
--- @return nil
function DicePreview:DicePreviewDragThink()
	-- dummy implementation for documentation purposes only
end

--- DicePreviewDragEnd: Handles the end of a drag on the preview dice resting on this cage panel, tossing them into a roll or cancelling. Panel-scoped equivalent of dice.DragEnd.
--- @return nil
function DicePreview:DicePreviewDragEnd()
	-- dummy implementation for documentation purposes only
end

--- CancelDicePreviewRoll: Cancels this cage panel's pending preview roll and clears its resting dice, leaving any other cage's dice alone. Panel-scoped equivalent of dmhub.CancelCurrentRoll.
--- @return nil
function DicePreview:CancelDicePreviewRoll()
	-- dummy implementation for documentation purposes only
end
