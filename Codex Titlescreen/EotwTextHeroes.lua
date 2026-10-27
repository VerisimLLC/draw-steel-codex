local mod = dmhub.GetModLoading()

--Encounter of the Week: the words of the heroes -- the hero builder, the hero sheet and the hero cards.
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * {name} is filled in by the game (a hero's name, a number, ...). Keep every
--    one, spelled exactly as it is; you may move it anywhere in the sentence.
--  * <b>...</b>, <i>...</i> and <color=...>...</color> are formatting. Keep
--    them, in pairs.
--  * A line break inside [[ ]] is a line break on screen.
--  * Two entries ending .one and .other are the same line for a count of one
--    and for any other count.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("EotwTextHeroes")

----------------------------------------------------------------------------
-- THE HERO BUILDER: the header and the steps
-- (Codex Titlescreen/EotwBuilder.lua, Codex Titlescreen/EotwBuild.lua)
----------------------------------------------------------------------------

--The big heading at the top left of the builder, when the screen that opens
--it gives none.
text("builder.header.title", [[Create Your Hero]])
--The small line under that heading.
text("builder.header.subtitle", [[Level 1 hero for Blackbottom]])
--The button at the top right. Short: a button. It reads "Save and Close"
--until every step is done, then "Finish".
text("builder.header.save_close_button", [[Save and Close]])
text("builder.header.finish_button", [[Finish]])
--Its tooltip while the hero is unfinished, and once it is complete.
text("builder.header.save_close_tooltip", [[Keep this hero as a draft and come back to it later from the Hero's Guild.]])
text("builder.header.finish_tooltip", [[Your hero is complete. Finish and add them to your roster.]])

--The names of the seven steps, in order. Each is the step's tab along the
--top and the big heading of its page. Short: a tab title.
--The step names also appear in lower case inside other lines (for example
--"your current ancestry"), so keep them plain nouns.
text("builder.steps.ancestry.title", [[Ancestry]])
text("builder.steps.culture.title", [[Culture]])
text("builder.steps.career.title", [[Career]])
text("builder.steps.class.title", [[Class]])
text("builder.steps.skills.title", [[Skills & Languages]])
text("builder.steps.complication.title", [[Complication]])
text("builder.steps.appearance.title", [[Appearance]])

--The name of the main pick on the steps that have one. It is shown in
--lower case in "Choose your {pick}" and "Your {pick}" below.
text("builder.steps.ancestry.base", [[Ancestry]])
text("builder.steps.career.base", [[Career]])
text("builder.steps.class.base", [[Class]])
text("builder.steps.complication.base", [[Complication]])

--The small coloured line under each step's tab. Short: a few words.
text("builder.stepper.needs_attention", [[Needs attention]])
text("builder.stepper.optional", [[Optional]])
text("builder.stepper.done", [[Done]])
text("builder.stepper.not_started", [[Not started]])
--{count} is how many of the step's choices are still to make.
text("builder.stepper.left", [[{count} left]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the hero so far (the column on the left)
----------------------------------------------------------------------------

--The labels of the lines under the hero card. Short: a label.
text("builder.summary.culture", [[Culture]])
text("builder.summary.career", [[Career]])
text("builder.summary.kit", [[Kit]])
text("builder.summary.complication", [[Complication]])
--The Complication line when the player chose to take none.
text("builder.summary.no_complication", [[None]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: a step's main pick (Ancestry, Career, Class, Complication)
----------------------------------------------------------------------------

--The heading over the main pick cards. {pick} is the step's main pick in
--lower case, such as "ancestry".
text("builder.base.heading", [[Choose your {pick}]])
--The same heading once the pick is fixed (a hero being rebuilt keeps its
--ancestry and class).
text("builder.base.heading_locked", [[Your {pick}]])
--The note under that heading when the pick is fixed. {pick} as above.
text("builder.base.locked_note", [[Your {pick} is chosen when the hero is created and can't be changed.]])
--The small coloured word beside the heading. Short.
text("builder.base.status.optional", [[Optional]])
text("builder.base.status.done", [[Done]])
text("builder.base.status.choose_one", [[Choose one]])

--The dialog when the player picks a different main pick after making
--choices under the old one. {step} is the step's name; in the message it is
--in lower case.
text("builder.change_confirm.title", [[Change {step}?]])
text("builder.change_confirm.message", [[This clears the choices you made for your current {step}.]])
--Its confirm button. Short: a button.
text("builder.change_confirm.button", [[Change]])

--The buttons of every small confirm dialog in the builder. Short: buttons.
text("builder.confirm.confirm_button", [[Confirm]])
text("builder.confirm.cancel_button", [[Cancel]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the picks pane (the column on the right), listing what
-- the player has chosen on the current step
----------------------------------------------------------------------------

--The pane's heading. {step} is the step's name, such as "Class".
text("builder.picks.heading", [[Your {step}]])
--Under a choice that has nothing picked yet. Short.
text("builder.picks.not_chosen", [[Not chosen yet]])
--Skills & Languages: the headings over what the player picked on that
--step, and over what the hero already has from other steps. Short.
text("builder.picks.skills_chosen", [[Skills you chose]])
text("builder.picks.languages_chosen", [[Languages you chose]])
text("builder.picks.skills_known", [[Skills you already have]])
text("builder.picks.languages_known", [[Languages you already speak]])
--How many more skills (or languages) are still to choose. {count} is the number.
text("builder.picks.left_to_choose", [[{count} more to choose]])
--The hero's native language in that list. {language} is its name.
text("builder.picks.native", [[{language} (native)]])
--Appearance: the labels, and what they show. Short.
text("builder.picks.name", [[Name]])
text("builder.picks.portrait", [[Portrait]])
text("builder.picks.anthem", [[Anthem]])
text("builder.picks.chosen", [[Chosen]])
text("builder.picks.none", [[None]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the (i) popups showing an item in full
----------------------------------------------------------------------------

--A section heading in a subclass's (or a Conduit domain's) details, over
--what it grants at 1st level.
text("builder.detail.subclass_first_level", [[At 1st level]])
--The name of a feature that has none.
text("builder.detail.feature_fallback", [[Feature]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the Culture step
----------------------------------------------------------------------------

--The heading over the aspect choices, under the typical cultures.
text("builder.culture.own_culture_heading", [[Or build your own culture from three aspects]])
--In a typical culture's details: the line before its three aspects.
text("builder.culture.detail.sets", [[Taking this culture sets:]])
--The last line of those details. {language} is the culture's language.
text("builder.culture.detail.language", [[**Language:** {language}]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the choices on a step's page
----------------------------------------------------------------------------

--The heading over a step's choice blocks.
text("builder.choice.heading", [[Your choices]])
--The small coloured line beside a choice's name.
text("builder.choice.status.stale", [[A pick here is no longer valid. Choose again, or use Fill in the rest.]])
text("builder.choice.status.exhausted", [[Nothing left to choose]])
text("builder.choice.status.done", [[Done]])
--{count} is the points left, {points} what they are called (from the rules).
text("builder.choice.status.points_to_spend", [[{count} {points} to spend]])
--Before any pick: one, or {count} picks to make.
text("builder.choice.status.choose.one", [[Choose one]])
text("builder.choice.status.choose.other", [[Choose {count}]])
--After some picks: {count} is how many are left.
text("builder.choice.status.choose_more", [[Choose {count} more]])
--The description of a treasure choice (a complication's "a trinket of your
--choice"). {prompt} is the rules' own wording, without a full stop.
text("builder.choice.treasure_grant_prompt", [[{prompt}. It goes straight into your hero's gear.]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the Class step's characteristics
----------------------------------------------------------------------------

--The name under a characteristic set by the class, which cannot be swapped.
--{name} is the characteristic, such as Might.
text("builder.class.characteristic_fixed", [[{name} (fixed)]])
--The hint under the characteristic boxes.
text("builder.class.characteristics_hint", [[Drag one characteristic onto another to swap their values. Characteristics marked fixed are set by your class.]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: what a step grants in skills and languages (the info box
-- on the Ancestry, Culture, Career, Class and Complication pages)
----------------------------------------------------------------------------

--The box's heading. Short.
text("builder.grants.heading", [[Skills & Languages]])
--The line listing what the step gives outright. {list} is the names, such as
--"Sneak (skill), Caelian (language)".
text("builder.grants.you_gain", [[**You gain:** {list}]])
--One name in that list. {name} is the skill or language.
text("builder.grants.fixed_skill", [[{name} (skill)]])
text("builder.grants.fixed_language", [[{name} (language)]])
--The name of a skill or language choice that has none.
text("builder.grants.choice_fallback", [[Choice]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the Skills & Languages step
----------------------------------------------------------------------------

--The page's introduction, under its heading.
text("builder.skills.intro", [[Pick your skills. We'll let you know which ones your ancestry, culture, career, and class allow.]])

--The list of choices at the top of the page. Each row names where the
--choice comes from: {step} is the step's name.
text("builder.skills.summary.source_skill", [[{step} (skill)]])
text("builder.skills.summary.source_language", [[{step} (language)]])
--The coloured word at the end of a row. Short. {count} is the picks left.
text("builder.skills.summary.done", [[Done]])
text("builder.skills.summary.left", [[{count} left]])
--Shown instead of the list when there is nothing to pick.
text("builder.skills.summary.none", [[You have no skills or languages to pick yet. They come from your ancestry, culture, career and class.]])

--The section headings over the cards.
text("builder.skills.skills_heading", [[Skills]])
text("builder.skills.languages_heading", [[Languages]])
--The line under the Languages heading. {language} is the native language.
text("builder.skills.native_language", [[Your native language is **{language}**, from your culture.]])
text("builder.skills.native_language_missing", [[Choose your native language on the Culture step.]])

--Added to a dead language's card, as in "Low Rhyvian (Sky elf; dead)".
--Short: one word.
text("builder.skills.card.dead", [[dead]])

--The details in a skill or language card's (i) popup.
--{category} is the skill's group, such as Exploration.
text("builder.skills.detail.category", [[*{category} skill*]])
text("builder.skills.detail.dead", [[*A dead language: no one speaks it any more, but its writing can still be read.*]])
--{speakers} is who speaks it, such as "Goblins, Radenwights".
text("builder.skills.detail.spoken_by", [[**Spoken by:** {speakers}]])
text("builder.skills.detail.once_spoken_by", [[**Once spoken by:** {speakers}]])
text("builder.skills.detail.native", [[**Your native language** (chosen with your culture).]])
--For one the hero already has. {source} is where from, such as "your career
--(Agent)" (see below).
text("builder.skills.detail.known_skill", [[**You know this skill already** from {source}.]])
text("builder.skills.detail.known_language", [[**You know this language already** from {source}.]])
--{source} when the game cannot tell where it comes from.
text("builder.skills.detail.source_fallback", [[another of your features]])
text("builder.skills.detail.picked", [[**Picked.** Click to drop it.]])
text("builder.skills.detail.available", [[**Available.** Click to pick it.]])
text("builder.skills.detail.unavailable", [[**Not available:** none of your remaining choices can take it.]])
--{choices} is the names of the choices it could fill.
text("builder.skills.detail.pools", [[Can be picked for: {choices}]])
--{features} is the names of the abilities that give a benefit with it.
text("builder.skills.detail.special", [[**Special:** your {features} gives you a benefit with this skill.]])
--One of those names when the ability has none.
text("builder.skills.special_fallback", [[A special ability]])

--Where a skill or language the hero already has comes from: the {source}
--above. {step} is the step's name in lower case, {item} the pick made
--there, as in "your career (Agent)".
text("builder.skills.source.step", [[your {step}]])
text("builder.skills.source.step_item", [[your {step} ({item})]])
text("builder.skills.source.culture", [[your culture]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the Complication step
----------------------------------------------------------------------------

--The first card on the page, for taking no complication. Short: a card.
text("builder.complication.none.card", [[No Complication]])
--Its heading, in its (i) popup and in the picks pane.
text("builder.complication.none.title", [[No Complication]])
--The picks pane while it is the hero's choice.
text("builder.complication.none.detail", [[Your hero takes no complication.]])
--Its (i) popup on the card.
text("builder.complication.none.preview", [[Take no complication. Complications are optional: each gives a benefit and a drawback.]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the Appearance step
----------------------------------------------------------------------------

--The page's introduction, under its heading.
text("builder.appearance.intro", [[Give your hero a name and a face, and if you like a frame for their token and an anthem.]])

--Name.
text("builder.appearance.name_heading", [[Name]])
--The grey text in the empty name box.
text("builder.appearance.name_placeholder", [[Your hero's name]])
--The button beside the name box. Short: a button.
text("builder.appearance.suggest_name_button", [[Suggest a Name]])
--Shown at the bottom of the screen when the ancestry has no names to suggest.
text("builder.appearance.no_name_list", [[This ancestry has no name list. Type a name instead.]])
--The name "Fill in the Rest" gives a hero when the ancestry has no names
--to suggest. {ancestry} and {class} are the hero's (or the two words below
--when not chosen yet), as in "Dwarf Fury".
text("builder.appearance.fallback_name", [[{ancestry} {class}]])
text("builder.appearance.fallback_ancestry", [[Nameless]])
text("builder.appearance.fallback_class", [[Hero]])

--Portrait.
text("builder.appearance.portrait_heading", [[Portrait]])
--The tooltip on the framed portrait preview.
text("builder.appearance.preview_tooltip", [[Drag to move the portrait within its frame. Scroll to zoom.]])
text("builder.appearance.portrait_hint", [[Your class's art is your portrait until you choose another. Click the image to the right to pick or upload your own.]])
--The art buttons. Short: buttons.
text("builder.appearance.class_art_button", [[Use Class Art]])
text("builder.appearance.ancestry_art_button", [[Use Ancestry Art]])
--Shown at the bottom of the screen when a button has no art to use.
text("builder.appearance.class_art_missing", [[Choose a class first: its art is the default portrait.]])
text("builder.appearance.ancestry_art_missing", [[Choose an ancestry with art first.]])
--The tooltip on the image to pick a portrait.
text("builder.appearance.portrait_picker_tooltip", [[Choose a portrait from the library, or upload your own.]])
--The label over the zoom slider. Short: a label.
text("builder.appearance.zoom_label", [[Zoom]])
--Short: a button.
text("builder.appearance.reset_placement_button", [[Reset Placement]])

--Frame.
text("builder.appearance.frame_heading", [[Frame]])
text("builder.appearance.frame_hint", [[The frame around your hero's token.]])

--Anthem.
text("builder.appearance.anthem_heading", [[Anthem]])
--The label over the volume slider. Short: a label.
text("builder.appearance.volume_label", [[Volume]])
text("builder.appearance.anthem_hint", [[Music that plays when your hero takes their turn.]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the footer
----------------------------------------------------------------------------

--The buttons at the bottom right. Short: buttons.
text("builder.footer.back_button", [[Back]])
text("builder.footer.fill_button", [[Fill in the Rest]])
--The same button after one click, offering to fill every other step too.
text("builder.footer.fill_all_button", [[For All Tabs?]])
--Its tooltips, before and after that first click.
text("builder.footer.fill_tooltip", [[Fill every choice on this page you have not made yet automatically. Your own choices are kept.]])
text("builder.footer.fill_all_tooltip", [[Fill every choice you have not made yet on all tabs too, completing the hero. Your own choices are kept.]])
--The last button: "Next" when the step is done, "Skip for Now" when not,
--"Finish" on the last step.
text("builder.footer.next_button", [[Next]])
text("builder.footer.skip_button", [[Skip for Now]])
text("builder.footer.finish_button", [[Finish]])

--Messages at the bottom left.
--After Fill in the Rest. {count} is the number of choices filled.
text("builder.footer.filled.one", [[Filled {count} choice.]])
text("builder.footer.filled.other", [[Filled {count} choices.]])
text("builder.footer.filled_all.one", [[Filled {count} choice across all tabs.]])
text("builder.footer.filled_all.other", [[Filled {count} choices across all tabs.]])
text("builder.footer.nothing_to_fill", [[Nothing left to fill on this page.]])
text("builder.footer.nothing_to_fill_all", [[Nothing left to fill.]])
--On Finish with steps unfinished. {steps} is their names, such as
--"Class, Appearance".
text("builder.footer.still_to_do", [[Still to do: {steps}.]])
--When something fails. {error} is the technical error.
text("builder.footer.error", [[Something went wrong: {error}]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the card while the Hero loads
----------------------------------------------------------------------------

--The Hero's name when the game cannot find it.
text("herosheet.card.hero_fallback", [[Hero]])
--The big name line while the Hero loads, and if they never do. {hero} is the Hero's name.
text("herosheet.card.loading", [[Loading {hero}...]])
text("herosheet.card.failed", [[{hero} could not load.]])
--The button under "could not load". Short: a button.
text("herosheet.card.try_again", [[Try again]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the card (name, titles, Level and XP)
----------------------------------------------------------------------------

--The hover on a title under the name. {dot} is a small middle dot; {echelon}
--is like "1st" (below).
text("herosheet.card.title_echelon", [[Title {dot} {echelon} echelon]])
--How a title's echelon reads: 1st, 2nd, 3rd, then {n}th.
text("herosheet.ordinal.first", [[1st]])
text("herosheet.ordinal.second", [[2nd]])
text("herosheet.ordinal.third", [[3rd]])
text("herosheet.ordinal.nth", [[{n}th]])
--The title hover's deed line. {deed} is how the title is earned.
text("herosheet.card.title_earned", [[<b>Earned:</b> {deed}]])

--The line under the name, like "Level 3 Human Fury". The subclass follows it
--after a dot when there is one.
text("herosheet.card.subtitle", [[Level {level} {ancestry} {class}]])

--At Level 10: the hover on the banked Victories beside the epic resource.
--{count} is the Victories, {resource} the epic resource's name.
text("herosheet.card.epic_banked_tip.one", [[{count} Victory becomes {count} XP and {count} {resource} at the next respite.]])
text("herosheet.card.epic_banked_tip.other", [[{count} Victories become {count} XP and {count} {resource} at the next respite.]])
--At Level 10: the short line beside it. {gain} is like +2.
text("herosheet.card.epic_banked", [[{gain} at the next respite]])

--The hover on the XP bar. {xp} is the XP into this Level, {per} the XP a
--Level takes, {level} the next Level.
text("herosheet.card.xp_ready_tip", [[{xp} XP: enough for Level {level}.]])
text("herosheet.card.xp_tip", [[{xp} of {per} XP to Level {level}.]])
--Added to the XP bar hover when Victories are banked. {count} is the Victories.
text("herosheet.card.xp_banked_tip.one", [[{count} Victory becomes {count} XP at the next respite.]])
text("herosheet.card.xp_banked_tip.other", [[{count} Victories become {count} XP at the next respite.]])
--Added after that when the next respite would reach the next Level.
text("herosheet.card.xp_banked_reach_tip", [[Enough for Level {level}.]])

--Under the XP bar, only on your own Hero: ready to Level now, or after a respite.
text("herosheet.card.ready_line", [[Head to the Training Grounds to Level your Hero.]])
text("herosheet.card.respite_line", [[A respite would Level this Hero.]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the card (Stamina and vitals)
----------------------------------------------------------------------------

--The line under the Stamina bar, left side: the Hero's state, or where Winded
--starts. {winded} is the Winded Stamina value.
text("herosheet.card.stamina_dead", [[<b>Dead</b>]])
text("herosheet.card.stamina_dying", [[<b>Dying</b>]])
text("herosheet.card.stamina_winded", [[<b>Winded</b> at {winded}]])
text("herosheet.card.stamina_winded_at", [[Winded at <b>{winded}</b>]])
--The same line, right side. {dead} is the (negative) Stamina where the Hero dies.
text("herosheet.card.stamina_dead_at", [[Dead at <b>{dead}</b>]])

--The label beside the Recoveries ring.
text("herosheet.card.recoveries", [[Recoveries]])
--The line under it. {max} is the most Recoveries, {dot} a small middle dot,
--{value} the Stamina each regains, like +6.
text("herosheet.card.recoveries_sub", [[of {max} {dot} {value} each]])
--The hover on the ring and label. {value} is the Stamina a Recovery regains.
text("herosheet.card.recovery_tip", [[Each Recovery regains {value} Stamina.]])
--The ring's hover when your Hero can spend one now (in town).
text("herosheet.card.recovery_spend_tip", [[Click to spend a Recovery: regain {value} Stamina.]])

--The word after the Victories number.
text("herosheet.card.victories_word.one", [[Victory]])
text("herosheet.card.victories_word.other", [[Victories]])
--The hover on Victories. {victories} is the number, {resource} the heroic
--resource's name (Focus, Wrath...).
text("herosheet.card.victories_tip", [[Starts each combat with {victories} extra {resource}. Victories become XP at the next respite.]])
--The heroic resource's name when the game cannot find it.
text("herosheet.card.resource_fallback", [[Heroic Resource]])

--The hover on the surge icons. {count} is the surges, {damage} the damage each adds.
text("herosheet.card.surges_tip.one", [[{count} surge. Each adds {damage} damage, up to 3 per roll. 2 raise a potency by 1.]])
text("herosheet.card.surges_tip.other", [[{count} surges. Each adds {damage} damage, up to 3 per roll. 2 raise a potency by 1.]])

----------------------------------------------------------------------------
-- THE HERO SHEET: a fallen Hero's epitaph (from the Graveyard)
----------------------------------------------------------------------------

--In place of the vitals. {encounter} is where they fell, {week} the week
--number, {who} the player who played them (or "you", below).
text("herosheet.card.epitaph", [[Fell in <b>{encounter}</b>
Played by {who}]])
text("herosheet.card.epitaph_week", [[Fell in <b>{encounter}</b>, week {week}
Played by {who}]])
--{who} when it was your own Hero.
text("herosheet.card.epitaph_you", [[you]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the top bar
----------------------------------------------------------------------------

--The label before the Hero thumbnails: in a game, in town on your own
--roster, and in town on another player's Hero. Short: a label.
text("herosheet.topbar.this_encounter", [[This encounter]])
text("herosheet.topbar.your_roster", [[Your roster]])
text("herosheet.topbar.your_party", [[Your party]])
--The label on a fallen Hero's sheet.
text("herosheet.topbar.graveyard", [[The Graveyard]])

--The hover on a thumbnail. {hero} is the Hero's name, {level} their Level,
--{player} the player who owns them.
text("herosheet.topbar.thumb_own", [[{hero}, Level {level}]])
text("herosheet.topbar.thumb_other", [[{hero}, {player}'s Hero]])

--The gold bar in a game when you are needed. {hero} is one of your Heroes.
text("herosheet.topbar.needed_trigger", [[{hero} has a trigger waiting]])
text("herosheet.topbar.needed_save", [[{hero} has a save to make]])
text("herosheet.topbar.needed_roll", [[{hero} has a roll to make]])
text("herosheet.topbar.needed_story", [[The story continues]])
text("herosheet.topbar.needed_act", [[The Heroes can act]])

--The Close button, and the key shown beside it. Short: a button.
text("herosheet.topbar.close", [[Close]])
text("herosheet.topbar.esc", [[Esc]])

--The chip while the Hero is away with a party. {party} is the party's name.
text("herosheet.topbar.away", [[Away: {party}]])
text("herosheet.topbar.away_note", [[Changes are off until the party ends.]])
--The chip in a Proving Pits game.
text("herosheet.topbar.practice", [[Proving Pits: practice only]])
--Your own Hero's buttons in town. Short: buttons.
text("herosheet.topbar.change_appearance", [[Change Appearance]])
text("herosheet.topbar.edit_builder", [[Edit in Builder]])
text("herosheet.topbar.edit_builder_tip", [[Change any of this Hero's choices while they are in Blackbottom.]])
--The hover on those buttons while the Hero is away with a party.
text("herosheet.topbar.away_tip", [[Not while away with a party.]])
--The title of the builder that Change Appearance opens.
text("herosheet.topbar.change_appearance_title", [[Change Appearance]])
--On another player's Hero: whose it is. {player} is their name.
text("herosheet.topbar.owner_chip", [[{player}'s Hero]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the Kit card
----------------------------------------------------------------------------

--The card's heading. Short: a heading.
text("herosheet.kit.header", [[Kit]])
--When the Hero has no kit, and when a kit-like choice (a Prayer, a Ward...)
--is not made yet.
text("herosheet.kit.no_kit", [[No kit]])
text("herosheet.kit.none_chosen", [[None chosen]])

--The kit's gear line, like "Heavy armor, medium weapon, shield". The parts
--are joined with commas. {armor} is the armor kind (several are joined with
--" or ", below), {weapon} a weapon kind in lower case.
text("herosheet.kit.gear_armor", [[{armor} armor]])
text("herosheet.kit.gear_no_armor", [[No armor]])
text("herosheet.kit.gear_shield", [[shield]])
text("herosheet.kit.gear_weapon", [[{weapon} weapon]])
--Joins two armor kinds ("Light or Medium"). Keep the spaces either side.
text("herosheet.kit.gear_or", [[ or ]])

--The kit's bonus labels. Short: labels in a two-column grid.
text("herosheet.kit.bonus.stamina", [[Stamina]])
text("herosheet.kit.bonus.speed", [[Speed]])
text("herosheet.kit.bonus.stability", [[Stability]])
text("herosheet.kit.bonus.disengage", [[Disengage]])
text("herosheet.kit.bonus.melee_distance", [[Melee distance]])
text("herosheet.kit.bonus.ranged_distance", [[Ranged distance]])
text("herosheet.kit.bonus.area", [[Area]])
text("herosheet.kit.bonus.melee_damage", [[Melee damage]])
text("herosheet.kit.bonus.ranged_damage", [[Ranged damage]])

--With two kits (a Tactician), the hover on a bonus. {kit} is the kit it
--comes from; {other_kit} the other kit and {other} its value for this bonus.
text("herosheet.kit.bonus_from", [[From {kit}.]])
text("herosheet.kit.bonus_from_both", [[From {kit}. {other_kit} gives {other}.]])
--Under a two-kit card. {kit} is the kit the melee damage comes from.
text("herosheet.kit.melee_from", [[Melee damage from {kit}. Change it during a respite.]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the Treasures card
----------------------------------------------------------------------------

--The card's heading. Short: a heading.
text("herosheet.treasures.header", [[Treasures]])
--The button beside it that jumps to the first treasure to equip. {count} is
--how many.
text("herosheet.treasures.to_equip", [[{count} to equip]])
--The hover on that button while the Hero is away with a party.
text("herosheet.treasures.away_tip", [[Not while away with a party.]])

--The sub-headings. Short: small labels.
text("herosheet.treasures.leveled", [[Leveled treasures]])
text("herosheet.treasures.trinkets", [[Trinkets]])
text("herosheet.treasures.consumables", [[Consumables]])
--Beside Leveled treasures. {carried} is how many the Hero has.
text("herosheet.treasures.leveled_count", [[{carried} of 3 carried]])
--Under a sub-heading with nothing in it.
text("herosheet.treasures.none", [[None]])

--The buttons and tags on a treasure row. Short: small buttons.
text("herosheet.treasures.equip", [[Equip]])
text("herosheet.treasures.unequip", [[Unequip]])
text("herosheet.treasures.equipped", [[Equipped]])
text("herosheet.treasures.carried", [[Carried]])
--The hover on the tag of an ancestry item (a Dwarf's Runic Carving).
text("herosheet.treasures.ancestry_tip", [[Part of the Hero's ancestry.]])

--The hover on Equip when it cannot be done. {cap} is the most leveled
--treasures a Hero can equip.
text("herosheet.treasures.equip_cap", [[{cap} leveled treasures are equipped. Unequip one first.]])
text("herosheet.treasures.equip_full", [[No free slot for this treasure.]])

--The hover on Equip / Unequip: one line per stat it would change. {stat} is
--the stat's name (below, or a characteristic), {from} and {to} its values.
text("herosheet.treasures.preview_equip", [[Equipping changes {stat} {from} -> {to}.]])
text("herosheet.treasures.preview_unequip", [[Unequipping changes {stat} {from} -> {to}.]])
--The stat names in those lines.
text("herosheet.treasures.preview_stat.stamina", [[Stamina]])
text("herosheet.treasures.preview_stat.speed", [[Speed]])
text("herosheet.treasures.preview_stat.disengage", [[Disengage]])
text("herosheet.treasures.preview_stat.stability", [[Stability]])

--The chip on a weapon or armor treasure the kit cannot use. Short: a chip.
text("herosheet.treasures.no_benefit", [[No benefit]])
--Its hover, by reason. {armor} is the armor the kit uses, in lower case.
text("herosheet.treasures.no_benefit.no_kit", [[Without a kit, this gives no benefit.]])
text("herosheet.treasures.no_benefit.weapon", [[The kit does not use this weapon, so this gives no benefit.]])
text("herosheet.treasures.no_benefit.no_armor", [[The kit uses no armor, so this gives no benefit.]])
text("herosheet.treasures.no_benefit.armor", [[The kit uses {armor} armor, so this gives no benefit.]])
--Under the treasure's own card, on such a treasure.
text("herosheet.treasures.card_warning", [[Weapon and armor treasures only help when the kit uses that kind of gear.]])

----------------------------------------------------------------------------
-- THE HERO SHEET: the stats band
----------------------------------------------------------------------------

--The heading over the characteristic tiles, and the tile names while the
--Hero loads. Short: a heading and tile labels.
text("herosheet.stats.characteristics", [[Characteristics]])
text("herosheet.stats.might", [[Might]])
text("herosheet.stats.agility", [[Agility]])
text("herosheet.stats.reason", [[Reason]])
text("herosheet.stats.intuition", [[Intuition]])
text("herosheet.stats.presence", [[Presence]])

--The stat labels beside the tiles. Short: small labels.
text("herosheet.stats.size", [[Size]])
text("herosheet.stats.speed", [[Speed]])
text("herosheet.stats.disengage", [[Disengage]])
text("herosheet.stats.stability", [[Stability]])
text("herosheet.stats.potency", [[Potency]])
text("herosheet.stats.weak", [[Weak]])
text("herosheet.stats.average", [[Average]])
text("herosheet.stats.strong", [[Strong]])
text("herosheet.stats.wealth", [[Wealth]])
text("herosheet.stats.renown", [[Renown]])

--The hover on a stat (and on the Stamina bar and Recoveries): the first line,
--then one line per thing that changes it. {base} is the base value.
text("herosheet.stats.source_base", [[Base {base}]])

--The headings of the words row. Short: headings.
text("herosheet.stats.skills", [[Skills]])
text("herosheet.stats.languages", [[Languages]])
text("herosheet.stats.immunities", [[Immunities]])
text("herosheet.stats.weaknesses", [[Weaknesses]])
--Under a heading with nothing in it.
text("herosheet.stats.none", [[None]])

----------------------------------------------------------------------------
-- THE HERO SHEET: Abilities
----------------------------------------------------------------------------

--The column's heading. Short: a heading.
text("herosheet.abilities.header", [[Abilities]])
--The groups, in the order they list. Short: group headings.
text("herosheet.abilities.group.main", [[Main actions]])
text("herosheet.abilities.group.maneuver", [[Maneuvers]])
text("herosheet.abilities.group.triggered", [[Triggered actions]])
text("herosheet.abilities.group.other", [[Other]])
text("herosheet.abilities.group.freestrike", [[Free strikes]])
text("herosheet.abilities.group.standard", [[Standard actions]])
--The note at the right of the Standard actions heading.
text("herosheet.abilities.standard_note", [[Every Hero can do these]])

--The tags at the right of an ability row: the action it takes (other action
--names come from the rules), then its cost. Short: small tags.
text("herosheet.abilities.tag.triggered", [[Triggered action]])
text("herosheet.abilities.tag.free_triggered", [[Free triggered action]])
text("herosheet.abilities.tag.no_action", [[No action]])
text("herosheet.abilities.tag.signature", [[Signature]])
text("herosheet.abilities.tag.free_strike", [[Free strike]])
--A cost. {number} is how much, {resource} the heroic resource (Focus, Wrath...).
text("herosheet.abilities.tag.cost", [[{number} {resource}]])

----------------------------------------------------------------------------
-- THE HERO SHEET: Features
----------------------------------------------------------------------------

--The column's heading. Short: a heading.
text("herosheet.features.header", [[Features]])
--Beside it while a filter hides some. {shown} and {total} are numbers.
text("herosheet.features.count_filtered", [[{shown} of {total}]])
--The filter chips beside it. Short: chips.
text("herosheet.features.pillar.combat", [[Combat]])
text("herosheet.features.pillar.exploration", [[Exploration]])
text("herosheet.features.pillar.montage", [[Montage]])
text("herosheet.features.pillar.negotiation", [[Negotiation]])
text("herosheet.features.pillar.respite", [[Respite]])
--The grey text in the empty filter box.
text("herosheet.features.filter_placeholder", [[Filter features]])
--When the filters hide every feature.
text("herosheet.features.no_match", [[No features match. Clear the filters to see them all.]])

--The sections, in the order they list. Short: group headings.
text("herosheet.features.section.core", [[Core feature]])
text("herosheet.features.section.class", [[Class]])
text("herosheet.features.section.ancestry", [[Ancestry]])
text("herosheet.features.section.complication", [[Complication]])
text("herosheet.features.section.kit", [[Kit]])
text("herosheet.features.section.title", [[Titles]])
text("herosheet.features.section.perk", [[Perks]])
text("herosheet.features.section.career", [[Career]])
text("herosheet.features.section.culture", [[Culture]])
text("herosheet.features.section.treasure", [[Treasures]])

--Under a feature that was picked from a choice. {choice} is the choice's name.
text("herosheet.features.chosen_for", [[Chosen for {choice}]])
--The link under a long feature's text. Short: a link.
text("herosheet.features.show_more", [[Show more]])
text("herosheet.features.show_less", [[Show less]])

----------------------------------------------------------------------------
-- HERO CARDS: the portrait cards in the town strip, the encounter roster
-- and the montage
----------------------------------------------------------------------------

--The name on a card when the hero's player never gave it one. Short: it
--sits on a small card.
text("herocard.name.unnamed", [[Unnamed Hero]])
--The small line under the name: who plays the hero, when nobody has claimed
--it, or when the whole party shares it. Short.
text("herocard.player.unclaimed", [[Unclaimed]])
text("herocard.player.party", [[The party]])

--The tooltip on a condition or effect icon, when its name is missing.
text("herocard.condition.fallback", [[Condition]])
text("herocard.effect.fallback", [[Effect]])

--The tooltip on the heroic resource icon, when the class does not name it.
text("herocard.heroic_resource.fallback", [[Heroic Resource]])

--The tooltip on the recoveries circle beside the stamina bar. {current} and
--{max} are numbers; {value} is the Stamina one Recovery gives. The second
--line shows under the first.
text("herocard.recoveries.tooltip_count", [[<b>Recoveries: {current} / {max}</b>]])
text("herocard.recoveries.tooltip_value", [[Recovery Value: {value} Stamina]])

--The tooltip on the small "+" beside the recoveries circle (montage, narrative
--and prep screens only). {amount} is the Stamina one Recovery gives.
text("herocard.recoveries.spend_tooltip", [[Spend a Recovery: regain {amount} Stamina]])

--The tooltip on the blue brain badge. {count} is a number.
text("herocard.intelligence.tooltip", [[{count} Intelligence earned, to spend before the fight]])

--The tooltip on the amber hammer badge (in town). {count} is a number.
text("herocard.downtime.tooltip.one", [[{count} Downtime Activity to spend on projects]])
text("herocard.downtime.tooltip.other", [[{count} Downtime Activities to spend on projects]])

--The tooltip on the pulsing "!" badge when the hero has a trigger to use.
--{hero} is the hero's name; {triggers} is the list of triggers, one per line.
text("herocard.trigger.tooltip", [[{hero} has a trigger available.

Click to jump to {hero}.]])
text("herocard.trigger.tooltip_list", [[{hero} has a trigger available.

{triggers}

Click to jump to {hero}.]])

--The tooltip on the X that removes a card, when the screen gives none.
text("herocard.dismiss.tooltip", [[Dismiss]])
