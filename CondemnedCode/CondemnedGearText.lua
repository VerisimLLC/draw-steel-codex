local mod = dmhub.GetModLoading()

--The Condemned, Experimental Gear (CondemnedGear.lua): the words of the window where
--heroes choose their experimental gear and grenades before the mission, the Director's
--party table and Hand out, and the Gearing Up block in the Campaign panel.
--Item names, flavour, ability cards and By Level text come from the items themselves.
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * {name} is filled in by the game (a hero's name, a number, ...). Keep every
--    one, spelled exactly as it is; you may move it anywhere in the sentence.
--  * Two entries ending .one and .other are the same line for a count of one
--    and for any other count.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("CondemnedGearText")

----------------------------------------------------------------------------
-- THE WINDOW
----------------------------------------------------------------------------

text("condemned.gear.title", [[Experimental Gear]])
--Under the title while someone chooses for one hero from the party table.
text("condemned.gear.choosing_for", [[Choosing for {name}]])
text("condemned.gear.return_to_party", [[Return to Party]])
text("condemned.gear.close", [[Close]])

----------------------------------------------------------------------------
-- CHOOSING
----------------------------------------------------------------------------

text("condemned.gear.gear", [[Gear]])
text("condemned.gear.grenades", [[Grenades]])
--Beside each heading: how many are chosen out of how many each hero may take.
text("condemned.gear.count", [[{n} / {max}]])
--On a gear card the hero has chosen.
text("condemned.gear.chosen", [[Chosen]])
text("condemned.gear.over_limit", [[Over limit]])
text("condemned.gear.over_limit_tip", [[The Director lowered the allowance. Put something back.]])
text("condemned.gear.grenades_full_tip", [[You have {max} grenades. Put one back to choose another.]])

----------------------------------------------------------------------------
-- THE ITEM PANE
----------------------------------------------------------------------------

--Heading over what the item changes on the hero: once chosen, and before.
text("condemned.gear.giving_you", [[Giving you]])
text("condemned.gear.would_change", [[Choosing it would change]])
text("condemned.gear.you_gain", [[You gain]])
text("condemned.gear.by_level", [[By Level]])
text("condemned.gear.choose", [[Choose]])
text("condemned.gear.put_back", [[Put back]])
--When a hero may take one gear and has one: trade it for the item shown.
text("condemned.gear.swap", [[Swap for this]])
text("condemned.gear.swap_tip", [[Puts back {name}]])
text("condemned.gear.gear_full_tip", [[You have {n} of {max} gear. Put one back to choose this.]])
text("condemned.gear.choose_one", [[Choose one]])
text("condemned.gear.n_chosen", [[{n} chosen]])
text("condemned.gear.handed_out", [[Handed out]])

----------------------------------------------------------------------------
-- THE PARTY TABLE (the Director, and a player with several heroes)
----------------------------------------------------------------------------

text("condemned.gear.each_hero_takes", [[Each hero takes]])
--After the two -/+ counts: "Each hero takes [1] gear [3] grenades".
text("condemned.gear.allow_gear", [[gear]])
text("condemned.gear.allow_grenades", [[grenades]])
--The info icon's tooltip beside the counts: what the book allows.
text("condemned.gear.book_tip", [[The adventure allows one experimental gear item and three grenades per player.]])
text("condemned.gear.reset", [[Reset]])
text("condemned.gear.col_hero", [[Hero]])
text("condemned.gear.col_gear", [[Gear]])
text("condemned.gear.col_grenades", [[Grenades]])
--Under each hero's name.
text("condemned.gear.hero_sub", [[{class} - {player}]])
text("condemned.gear.no_gear", [[No gear]])
text("condemned.gear.no_grenades", [[No grenades]])
--A hero's status pill.
text("condemned.gear.status_done", [[Done]])
text("condemned.gear.status_choosing", [[Choosing]])
text("condemned.gear.status_nothing", [[Nothing yet]])
--Above the table for a player who has several heroes.
text("condemned.gear.own_list_hint", [[Click a hero to choose their gear.]])

----------------------------------------------------------------------------
-- HAND OUT (the Director)
----------------------------------------------------------------------------

text("condemned.gear.tally", [[{done} of {total} heroes done]])
text("condemned.gear.hand_out", [[Hand out]])
text("condemned.gear.hand_out_tip", [[Gives each hero their choices and closes this panel for everyone.]])
text("condemned.gear.not_done", [[Not everyone is done.]])
text("condemned.gear.not_done_over", [[{name}: over the limit]])
text("condemned.gear.not_done_nothing", [[{name}: nothing chosen]])
text("condemned.gear.not_done_choosing", [[{name}: still choosing]])
text("condemned.gear.hand_out_anyway", [[Hand out anyway]])
text("condemned.gear.keep_open", [[Keep it open]])
text("condemned.gear.fix_over_first", [[Fix Over limit first, or raise the allowance.]])
--Under the table after Hand out, and the toast.
text("condemned.gear.handed_out_to.one", [[Handed out to {count} hero.]])
text("condemned.gear.handed_out_to.other", [[Handed out to {count} heroes.]])
--Toast when another change to a hero got in first.
text("condemned.gear.refused", [[A hero changed while handing out, so nothing was given. Press Hand out again.]])
--Hand out's tooltip while the last Hand out is still being saved.
text("condemned.gear.waiting", [[Waiting on the last hand out.]])

----------------------------------------------------------------------------
-- OPENING AND REOPENING
----------------------------------------------------------------------------

text("condemned.gear.opened_for_all", [[Opened for every player]])
--The players' link back to the window while it is open.
text("condemned.gear.reopen_label", [[Experimental Gear]])
text("condemned.gear.reopen_button", [[Open]])
--A player with no hero of their own.
text("condemned.gear.director_chooses", [[The Director is choosing gear for your hero.]])

----------------------------------------------------------------------------
-- THE CAMPAIGN PANEL, ABBEY TAB
----------------------------------------------------------------------------

text("condemned.gear.gearing_up", [[Gearing Up]])
text("condemned.gear.gearing_up_body", [[One piece of experimental gear and three grenades each.]])
text("condemned.gear.open_button", [[Open Experimental Gear]])
text("condemned.gear.pill_open", [[Open]])
text("condemned.gear.heroes_done", [[{done} of {total} heroes are done.]])
text("condemned.gear.show_it", [[Show it]])
text("condemned.gear.see_what_took", [[See what each hero took]])
