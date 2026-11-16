local mod = dmhub.GetModLoading()

--The words of the shared game rules and the map HUD: the movement tooltip, rules editors,
--trigger names and GoblinScript help. Loads right after UIText, before any code that uses it.
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * {name} is filled in by the game (a number, a creature's name, ...). Keep every
--    one, spelled exactly as it is; you may move it anywhere in the sentence.
--  * <b>...</b>, <i>...</i> and <color=...>...</color> are formatting. Keep
--    them, in pairs.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--Code: UIText (DMHub Utils/UIText.lua).

local text = UIText.Define("GameRulesText")

----------------------------------------------------------------------------
-- THE MOVEMENT TOOLTIP: Codex Callouts
-- (Draw Steel UI/DSHud.lua)
----------------------------------------------------------------------------

--Boxed note under the movement tooltip of any creature that can teleport. It explains the
--control, not the rule. Short: one line.
text("movement.callout.hold_ctrl_to_teleport", [[Hold Ctrl while moving to teleport.]])

----------------------------------------------------------------------------
-- REMINDER TEXT EDITOR
-- (DMHub Game Rules/ModifierMovementText.lua)
----------------------------------------------------------------------------

--A choice in the Color dropdown. Text in this colour is drawn as a boxed Codex Callout
--with the Codex logo, for how to work the Codex rather than a rule. Short: a menu item.
text("remindertext.color.codex_callout", [[Codex Callout]])
