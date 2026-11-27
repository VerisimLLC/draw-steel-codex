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

---Boxed note for a creature that can move vertically right now (flying, climbing at a wall,
---swimming, burrowing). {source} is what gives it that ability (Climb, Fly...); {up} and
---{down} are the player's own Fly Token Up/Down keys with an arrow glyph, e.g. "Alt + [up arrow]".
---Short: one line.
text("movement.callout.hold_to_move_vertically", [[{source}: Hold {up} or {down} to change height.]])
---What gives the creature vertical movement, shown before the colon. One word each.
text("movement.callout.vertical_source.fly", [[Fly]])
text("movement.callout.vertical_source.climb", [[Climb]])
text("movement.callout.vertical_source.swim", [[Swim]])
text("movement.callout.vertical_source.burrow", [[Burrow]])
text("movement.callout.vertical_source.cling", [[Cling]])

--Boxed note shown when a player grabs a creature that is locked into a saddle (which drags
--its mount instead). {lock} is drawn as the padlock icon that sits on the rider's token; keep
--it in the sentence where the icon should appear. {name} is the rider's name; with several
--riders no names are listed (the line would run off the box). Short: one or two lines.
text("movement.callout.click_lock_to_dismount.one", [[To dismount: Click the {lock} on {name}'s token.]])
text("movement.callout.click_lock_to_dismount.other", [[To dismount: Click the {lock} on a mounted creature's token.]])

----------------------------------------------------------------------------
-- REMINDER TEXT EDITOR
-- (DMHub Game Rules/ModifierMovementText.lua)
----------------------------------------------------------------------------

--A choice in the Color dropdown. Text in this colour is drawn as a boxed Codex Callout
--with the Codex logo, for how to work the Codex rather than a rule. Short: a menu item.
text("remindertext.color.codex_callout", [[Codex Callout]])

----------------------------------------------------------------------------
-- THE MOVEMENT TOOLTIP: teleporting as movement
-- (Draw Steel UI/DSHud.lua)
----------------------------------------------------------------------------

--Red warning under a Ctrl-drag teleport that goes farther than the creature's movement left
--this turn. Short: one line.
text("movement.teleport_beyond_remaining", [[This teleport is farther than your remaining movement.]])

----------------------------------------------------------------------------
-- RELOCATE CREATURE BEHAVIOR EDITOR
-- (DMHub Game Rules/AbilityRelocateCreature.lua)
----------------------------------------------------------------------------

--A checkbox in the ability editor. Short: a checkbox label.
text("relocate.editor.teleport_counts_as_movement", [[Teleport Counts as Movement]])
--Its tooltip.
text("relocate.editor.teleport_counts_as_movement_tooltip", [[If set, the teleport spends the creature's movement equal to the distance and fires the Teleport as Movement trigger, as if it had held Ctrl while moving.]])

----------------------------------------------------------------------------
-- THE "TELEPORT AS MOVEMENT" TRIGGER
-- (Draw Steel Core Rules/MCDMRules.lua, Draw Steel Ability Editor/NewTriggeredAbilityEditor.lua,
--  DMHub Utils/GoblinScriptProse.lua)
----------------------------------------------------------------------------

--The trigger's name in the trigger pickers. Short.
text("trigger.teleportmove.name", [[Teleport as Movement]])
--Its description in the trigger picker.
text("trigger.teleportmove.description", [[Fires when the creature teleports as its own movement (holding Ctrl while moving), not when an ability teleports it.]])
--Help for the Path value the trigger provides.
text("trigger.teleportmove.path", [[The path from the creature's origin to its teleport destination.]])
--How the trigger reads in a sentence describing an ability. {subject} is who teleports;
--{s} adds an "s" when it is one creature ("the hero teleports"). Keep both.
text("trigger.teleportmove.prose", [[when {subject} teleport{s} as part of moving]])

----------------------------------------------------------------------------
-- GOBLINSCRIPT HELP: teleport departure symbols
-- (Draw Steel Core Rules/MCDMSymbols.lua)
----------------------------------------------------------------------------

text("symbol.teleportorigindistance.desc", [[Given a creature, returns how many squares it is from the space this creature teleported away from on its latest teleport. 1 means it was adjacent to the departure point. Returns 999 if this creature has not teleported or the creature given is this creature.]])
text("symbol.alliesadjacenttoteleportorigin.desc", [[The number of living allies, not counting this creature, that are adjacent to the space this creature teleported away from on its latest teleport.]])
text("symbol.unoccupiedadjacentspaces.desc", [[The number of squares adjacent to this creature where a creature could appear: on the map, not occupied by a creature or object, and not blocked by walls or solid terrain. Zero means nothing can be placed next to it.]])

----------------------------------------------------------------------------
-- INVOKE ABILITY BEHAVIOR EDITOR
-- (DMHub Game Rules/AbilityInvokeAbility.lua)
----------------------------------------------------------------------------

--A choice in the Range Origin dropdown: measure the invoked ability's range from the
--creature that used the parent ability (e.g. land a teleported ally next to the shadow
--who brought it). Short: a menu item, alongside "Parent's Primary Target".
text("invoke.editor.range_origin.parent_caster", [[Parent's Caster]])

----------------------------------------------------------------------------
-- THE MOVEMENT PANEL in the Move drawer of the action bar
-- (DrawSteelActionBar/DrawSteelActionBar.lua, Draw Steel Core Rules/MCDMCreature.lua)
----------------------------------------------------------------------------

--Heading under the panel, like the headings under each group of abilities.
text("movemode.heading", [[Movement]])

--Under the current movement mode's name. {speed} is a number of squares.
text("movemode.speed", [[Speed {speed}]])
--The same, for a creature swimming without a swim speed: each square costs an extra square.
text("movemode.speed_doubled", [[Speed {speed}, each square costs 2]])

--Labels over the number next to the up/down buttons: height above the ground, or
--how far down the creature is under water or underground.
text("movemode.altitude", [[Altitude]])
text("movemode.depth", [[Depth]])

--Tooltips on the up/down buttons, and why one of them can't be used.
text("movemode.up", [[Up 1 square]])
text("movemode.down", [[Down 1 square]])
text("movemode.at_surface", [[You are at the surface]])
text("movemode.on_ground", [[You are on the ground]])

--Tooltip on a movement mode the creature can't switch to right now: the reason.
text("movemode.reason.cannot_walk", [[You cannot walk]])
text("movemode.reason.cannot_fly", [[You cannot fly]])
text("movemode.reason.cannot_burrow", [[You cannot burrow]])
text("movemode.reason.not_in_water", [[You can only swim when in water]])
text("movemode.reason.nothing_to_climb", [[There is nothing to climb]])
text("movemode.reason.prone", [[You cannot climb while prone]])
text("movemode.reason.in_air", [[You are in the air]])
text("movemode.reason.in_deep_water", [[You are in deep water]])
text("movemode.reason.underwater", [[You are underwater]])
text("movemode.reason.underground", [[You are underground]])

----------------------------------------------------------------------------
-- THE PERSISTENT MAGIC DIALOG: start of the turn of a hero with persistent abilities
-- (Draw Steel Ability Behaviors/AbilityPersistentCast.lua)
----------------------------------------------------------------------------

--Under the dialog's title.
text("persistence.instruction", [[Select abilities to persist.]])

--What an ability costs to keep up, next to its name. {resource} is e.g. "Essence".
text("persistence.cost", [[{cost} {resource}]])

--At the right of each ability's row: whether it will be kept up or end.
text("persistence.persisting", [[Persisting]])
text("persistence.ending", [[Ending]])

--Shown under strict resource rules while the kept abilities cost more than the hero
--gains; the dialog can't be confirmed until enough are ended.
text("persistence.must_end", [[You must end some abilities so you do not lose essence]])

--The dialog's button.
text("persistence.confirm", [[Confirm]])

----------------------------------------------------------------------------
-- TRIGGERS THAT ACT DURING A MOVE: the Tactician's Overwatch
-- (Draw Steel Ability Behaviors/AbilityMidMoveTriggers.lua)
----------------------------------------------------------------------------

--Floats over a creature put back along its path because being slowed cut its move short.
text("midmove.cut_short.float", [[Stopped]])

--Bottom of the screen while the Tactician picks who strikes. {target} is the moving
--enemy's name, or the unnamed_target text when the player can't see its name.
text("midmove.direct_ally.choose", [[Choose an ally to free strike {target}]])
text("midmove.direct_ally.no_allies", [[No ally can free strike {target}]])
text("midmove.direct_ally.unnamed_target", [[the moving enemy]])

--An ally's button when they can't reach the enemy from where they stand. {name} is the ally.
text("midmove.direct_ally.out_of_reach", [[{name} (out of reach)]])
