local mod = dmhub.GetModLoading()

--Encounter of the Week: the words players see in the game itself -- the story stage, montages, narratives, Tactical Preparation, the encounter interface, victory and defeat.
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

local text = UIText.Define("EncounterText")

----------------------------------------------------------------------------
-- ARRIVING: the start of the game
----------------------------------------------------------------------------

--The note in the Hero Tokens history when the party's tokens are handed out
--at the start of the game.
text("encounter.arrival.hero_tokens_note", [[Start of the session]])

--The Codex > About Encounter of the Week dialog names the encounter. For an
--encounter played in parts, the part is added after its title.
--{number} is the part's number.
text("encounter.about.part", [[Part {number}]])
--A part that has its own name: {title} is that name.
text("encounter.about.part_named", [[Part {number}: {title}]])
--{title} is the encounter's name, {part} one of the two lines above.
text("encounter.about.title_with_part", [[{title} -- {part}]])

----------------------------------------------------------------------------
-- ARRANGE YOUR HEROES: the panel when the heroes win the initiative
----------------------------------------------------------------------------

--The panel's heading and the line under it.
text("encounter.arrange.title", [[Arrange Your Heroes]])
text("encounter.arrange.intro", [[You have won the initiative. Choose starting locations, then press Ready.]])

--The button. Short: it is a button.
text("encounter.arrange.ready_button", [[Ready]])
--The same button once you have pressed it (press again to take it back).
text("encounter.arrange.not_ready_button", [[Not Ready]])

--The countdown, used inside the status lines below as {time}. {time} here
--is the minutes and seconds left, like 1:45.
text("encounter.arrange.time_left", [[The fight begins in {time}]])
--The status line. {names} is the players still arranging (see the next
--entry), {time} the countdown above.
text("encounter.arrange.status_ready_waiting", [[You are ready. Waiting for {names}. {time}.]])
text("encounter.arrange.status_everyone_ready", [[Everyone is ready. Draw steel!]])
text("encounter.arrange.status_also_waiting", [[Also waiting for {names}. {time}.]])
text("encounter.arrange.status_not_ready", [[{time}, or as soon as you are ready.]])
--How several players' names are joined: "Kira and Brann", "Kira, Brann and
--Osk". {names} is every name but the last, joined by commas; {last} is the
--last name.
text("encounter.arrange.names_and", [[{names} and {last}]])

----------------------------------------------------------------------------
-- THE VICTORY SCREEN: notes on each hero's card
----------------------------------------------------------------------------

--On the card of a hero who has won this encounter before, and so gets no
--Victory for it this time.
text("encounter.victory.already_completed", [[Already Completed]])
--On a living hero's card after a win: what they take home. {treasure} is
--the items, like "Bastion Belt x2, Ward Token".
text("encounter.victory.treasure_note", [[Treasure: {treasure}]])
--On every hero's card after a Proving Pits game, which awards nothing.
text("encounter.victory.practice_note", [[Proving Pits: practice only]])

--A hero's name in the town's Hall of Heroes when the game cannot find it.
text("encounter.hall.hero_fallback", [[Hero]])

--The title of the Conclusion or Defeat story screen after the fight, for an
--encounter played in parts. {number} is the part's number.
text("encounter.story.part", [[Part {number}]])
--A part that has its own name: {title} is that name.
text("encounter.story.part_named", [[Part {number}: {title}]])
--{title} is the encounter's name, {part} one of the two lines above.
text("encounter.story.title_with_part", [[{title} -- {part}]])

----------------------------------------------------------------------------
-- FOR ENCOUNTER AUTHORS: testing an encounter (Game menu > Test Encounter)
----------------------------------------------------------------------------

--Where a test starts. Shown in the Game menu ("Test Encounter: From the
--Start") and in the test dialog's "Start at" choices. Short.
text("encounter.test.mode_start", [[From the Start]])
text("encounter.test.mode_montage", [[Montage]])
text("encounter.test.mode_combat", [[Combat]])

--Why a test cannot start. Shown in the test dialog after "Part 2 cannot be
--tested:", so they start lower-case.
text("encounter.test.unknown_mode", [[unknown test mode]])
text("encounter.test.no_script", [[this map has no Encounter of the Week script]])
text("encounter.test.no_montage_beat", [[this map's script has no # Montage beat]])
text("encounter.test.no_encounter_beat", [[this map's script has no # Encounter beat]])
text("encounter.test.director_only", [[only the Director can test an encounter]])
text("encounter.test.in_eotw_game", [[this is an Encounter of the Week game]])
text("encounter.test.already_running", [[a test is already running]])
text("encounter.test.end_combat_first", [[end combat first]])
text("encounter.test.code_not_loaded", [[the Encounter of the Week code is not loaded]])
text("encounter.test.choose_hero", [[choose at least one hero]])

--The notes in the Hero Tokens and Malice histories when a test starts and
--ends.
text("encounter.test.hero_tokens_start_note", [[Start of the encounter test]])
text("encounter.test.hero_tokens_end_note", [[End of the encounter test]])
text("encounter.test.malice_end_note", [[End of the encounter test]])

--The button on the Conclusion or Defeat story screen at the end of a test,
--and what it says while the test is closing. Short: a button.
text("encounter.test.story_end_button", [[End Test]])
text("encounter.test.story_ending", [[Ending...]])

--The game's map script, as listed in the Director's Map Scripts panel.
text("encounter.map_script.name", [[Encounter of the Week]])
text("encounter.map_script.description", [[Runs the weekly encounter: enters combat with the normal Draw Steel roll once every player has arrived, then keeps the Monster AI playing the monsters. Attached to the map automatically by the Encounter of the Week game mode.]])

----------------------------------------------------------------------------
-- THE STORY STAGE: names used when a hero's name cannot be found
----------------------------------------------------------------------------

--Stand-ins for a hero's name when the game cannot find it, used across the
--montage stage. "A hero" / "The hero" start a sentence; the lower-case ones
--sit mid-sentence. "Your hero" is on buttons for the player's own hero.
text("stage.fallback.a_hero", [[A hero]])
text("stage.fallback.the_hero", [[The hero]])
text("stage.fallback.your_hero", [[Your hero]])
text("stage.fallback.a_hero_lower", [[a hero]])
text("stage.fallback.the_hero_lower", [[the hero]])

----------------------------------------------------------------------------
-- THE MONTAGE STAGE: header and columns
----------------------------------------------------------------------------

--The big title at the top of the montage stage.
text("stage.montage.title", [[Montage]])
--The line under the title. {round} is the current round, {rounds} how many
--there are.
text("stage.montage.status_arriving", [[Waiting for players to arrive...]])
text("stage.montage.status_round", [[Round {round} of {rounds}]])
text("stage.montage.status_consequences", [[Consequences]])
text("stage.montage.status_complete", [[Complete]])
--The headings over the left and right columns. Short: column headings.
text("stage.montage.column_opportunities", [[Opportunities]])
text("stage.montage.column_threats", [[Threats]])

----------------------------------------------------------------------------
-- THE MONTAGE STAGE: the middle panel between turns
----------------------------------------------------------------------------

--While the party is still arriving.
text("stage.montage.arriving_title", [[Gathering the party]])
text("stage.montage.arriving_hint", [[Waiting for all players to arrive...]])
--Whose move it is. {heroes} is the player's own heroes' names, joined by
--the word below.
text("stage.montage.waiting_for_others", [[Waiting for the other heroes to act.]])
text("stage.montage.your_move", [[Your move: drag {heroes} onto an Opportunity or a Threat.]])
--Joins two or more hero names in the line above. Keep the spaces.
text("stage.montage.your_move_or", [[ or ]])
--The heading of a new round. {round} is its number.
text("stage.round.title", [[Round {round}]])
--A one-line summary of the last hero's turn, under the round heading.
--{hero} is the hero, {entry} the Opportunity or Threat, {option} the option
--they chose, {tier} like "tier 2" or "critical", {depth} how far they got,
--{steps} / {obstacles} / {chests} counts like "3 steps".
text("stage.round.summary_ordered_delve", [[{hero} took on {entry}: {depth} of {steps}.]])
text("stage.round.summary_delve", [[{hero} delved into {entry}: {obstacles} met, {chests} opened.]])
text("stage.round.summary_passed", [[{hero} approached {entry} and did nothing.]])
text("stage.round.summary_no_roll", [[{hero}: {entry} ({option}, no roll)]])
text("stage.round.summary_tier", [[{hero}: {entry} ({option}, {tier})]])
--A small line under the summary: the hero used a knack. {knack} says which.
text("stage.round.summary_knack", [[Knack: {knack}]])
--A temporary Threat that ran out at the end of the round. {threat} is its
--name; the second entry stands in when it has none.
text("stage.round.threat_expired", [[{threat} was left unresolved.]])
text("stage.round.threat_expired_fallback", [[A threat]])
--When the montage has finished.
text("stage.montage.over_title", [[The montage is over]])
text("stage.montage.over_hint", [[Draw Steel!]])

----------------------------------------------------------------------------
-- THE MONTAGE STAGE: Opportunity and Threat cards
----------------------------------------------------------------------------

--A line on a temporary card. The second is for a Threat with a consequence.
text("stage.entry.deadline", [[Gone at the end of this round]])
text("stage.entry.deadline_threat", [[Gone at the end of this round -- deal with it or face the consequence]])
--The status line at the bottom of a card. {hero} is who is there now.
text("stage.entry.status_taken", [[Taken]])
text("stage.entry.status_vanquished", [[Vanquished]])
--Challenge Mode: a threat the party must vanquish more than once. Its title
--reads like "Goblin Scouts x2". {name} is the threat's name, {count} how
--many more times it must be vanquished.
text("stage.entry.name_times", [[{name} x{count}]])
--The status line once it has been vanquished once but not yet for good.
text("stage.entry.status_vanquished_partly.one", [[Vanquished once -- once more to go]])
text("stage.entry.status_vanquished_partly.other", [[Vanquished once -- {count} more times to go]])
text("stage.entry.status_hero_here", [[{hero} is here]])
text("stage.entry.status_drag_here", [[Drag a hero here]])

--Across the top of the small hero portrait on a card, once the hero is
--done. Short: one word. (A rolled tier shows "Tier 2" etc. instead.)
text("stage.entry.slot.passed", [[Passed]])
text("stage.entry.slot.delved", [[Delved]])
text("stage.entry.slot.done", [[Done]])
--The tooltip on that portrait. {hero} is the hero's name, {depth} how far
--they got, {steps} / {obstacles} / {chests} counts like "2 chests",
--{tier} like "Tier 2", {total} the roll.
text("stage.entry.slot.tooltip_now", [[<b>{hero}</b> is dealing with this now.]])
text("stage.entry.slot.tooltip_passed", [[<b>{hero}</b> approached and did nothing.]])
text("stage.entry.slot.tooltip_ordered_delve", [[<b>{hero}</b> took this on: {depth} of {steps}.]])
text("stage.entry.slot.tooltip_delve", [[<b>{hero}</b> delved in: {obstacles} met, {chests} opened.]])
text("stage.entry.slot.tooltip_rolled", [[<b>{tier}</b> (rolled {total})]])
text("stage.entry.slot.tooltip_no_roll", [[No roll]])
--{knack} says which knack the hero used.
text("stage.entry.slot.tooltip_knack", [[Knack: {knack}]])

----------------------------------------------------------------------------
-- THE MONTAGE STAGE: outcome icons (tooltips)
----------------------------------------------------------------------------

--The tooltips on the small icons on each card and option, saying what it
--may lead to.
text("stage.outcome.intelligence", [[May earn Intelligence.]])
text("stage.outcome.herotoken", [[May earn Hero Tokens for the party.]])
text("stage.outcome.treasure", [[May find treasure.]])
text("stage.outcome.temphp", [[May grant Temporary Stamina.]])
text("stage.outcome.malice", [[May give the monsters Malice, which they spend on their most powerful abilities in the fight.]])
text("stage.outcome.harm", [[May cost Stamina or Recoveries.]])
text("stage.outcome.other", [[May lead to a mysterious reward.]])
--The question-mark icon on a Threat whose consequence is not known.
text("stage.outcome.other_consequence", [[Beware, this threat has an unknown consequence.]])
--A Threat's icon that comes from its consequence. {outcome} is one of the
--tooltips above.
text("stage.outcome.only_if_unresolved", [[{outcome} Only if this threat is never dealt with.]])
text("stage.outcome.also_if_unresolved", [[{outcome} Leaving this threat unresolved may also do this.]])

----------------------------------------------------------------------------
-- THE SCENE STAGE: a hero at an Opportunity or Threat
----------------------------------------------------------------------------

--The title over the scene. {hero} is the hero, {entry} the Opportunity or
--Threat, {place} the spot inside a delve they have reached.
text("stage.scene.title_approach", [[{hero} approaches {entry}]])
text("stage.scene.title_delve", [[{hero} in {entry}]])
text("stage.scene.title_delve_place", [[{hero} in {entry}: {place}]])
--The speaker's name over a line in another language. {speaker} is who
--speaks, {language} the language. "speaking" is for words the hero cannot
--understand.
text("stage.scene.speaker_in_language", [[{speaker} (in {language})]])
text("stage.scene.speaker_speaking_language", [[{speaker} (speaking {language})]])
--Over the list of options. {hero} is the hero choosing.
text("stage.scene.choose_prompt", [[Choose how to approach it:]])
text("stage.scene.hero_choosing", [[{hero} is choosing...]])
--A small tag beside an option that needs no roll. Short.
text("stage.scene.option_no_roll_tag", [[no roll]])
--The tooltip on an option for another player. {hero} is the hero choosing.
text("stage.scene.option_ping_tooltip", [[Ping this option for everyone: suggest it to {hero}.]])
--The last option: do nothing. Short: a button.
text("stage.scene.leave_button", [[Leave]])
text("stage.scene.leave_tooltip", [[Leave without doing anything. This passes your turn -- not very heroic.]])
--The option to step back out of a wrong choice. Short: a button.
text("stage.scene.back_out_button", [[Oops, back out]])
text("stage.scene.back_out_tooltip", [[Wrong place? Step back and choose again. This does not use your turn.]])
--While the test is being rolled. {hero} is the hero rolling.
text("stage.scene.prompt_roll", [[Make your roll.]])
text("stage.scene.hero_rolling", [[{hero} is rolling...]])

----------------------------------------------------------------------------
-- THE SCENE STAGE: an option's card
----------------------------------------------------------------------------

--The line when the hero is not allowed to take this option.
text("stage.option.rider_locked", [[You are missing a requirement for this option]])
--An edge or bane an earlier outcome gave this test. {label} is like "Edge",
--{entry} where it was earned.
text("stage.option.granted_at", [[{label}: earned at {entry}]])
--The hero has a knack that changes this option. {knack} says which.
text("stage.option.knack", [[Knack: {knack}]])
--A Ritualist blessed this test. {hero} is the Ritualist; the second entry
--stands in for their name.
text("stage.option.blessed", [[Double Edge: blessed by {hero} (Ritualist)]])
text("stage.option.blessed_fallback", [[a Ritualist]])
--Where the roll would be, for an option that needs none.
text("stage.option.no_roll_needed", [[No roll needed]])

----------------------------------------------------------------------------
-- THE SCENE STAGE: perks
----------------------------------------------------------------------------

--Ritualist. {hero} is the Ritualist; the fallback stands in for their name.
text("stage.perk.blessed", [[{hero} has blessed this test: a double edge (Ritualist).]])
text("stage.perk.blessed_fallback", [[A Ritualist]])
text("stage.perk.bless_button", [[Bless your own test (Ritualist)]])
text("stage.perk.bless_tooltip", [[Ritualist: a minute's blessing gives a double edge on this test. Once a round.]])
--After a failed test, over the perks that could rescue it. {hero} is the
--hero, {tier} the tier they rolled, {total} the roll.
text("stage.perk.rolled_tier", [[{hero} rolled tier {tier}]])
text("stage.perk.rolled_tier_total", [[{hero} rolled tier {tier} ({total})]])
--A perk button and its "no" button. {hero} is the hero with the perk,
--{perk} its name. Short: buttons.
text("stage.perk.use_button", [[{hero}: use {perk}]])
text("stage.perk.dont_use_button", [[Don't use {perk}]])
--What other players see while the perk's owner decides.
text("stage.perk.may_use", [[{hero} may use {perk}...]])
--Pardon My Friend. {hero} failed the test at tier {tier}; {helper} steps in
--(the fallback stands in for their name).
text("stage.perk.pardon", [[{hero} rolled tier {tier}. {helper} steps in to make the test instead, with a bane (Pardon My Friend)...]])
text("stage.perk.pardon_helper_fallback", [[Another hero]])
--Team Leader, once used. {hero} and {owner} are both the leader's name
--({owner} reads "{owner}'s"); the fallback stands in for {owner}.
text("stage.perk.team_leader_active", [[{hero} leads the party: every hero tests as if they had {owner}'s exploration skills (Team Leader).]])
text("stage.perk.team_leader_owner_fallback", [[their]])
--The Team Leader button and its tooltip. {hero} is the leader.
text("stage.perk.team_leader_button", [[{hero}: lead the party (Team Leader)]])
text("stage.perk.team_leader_tooltip", [[Team Leader: spend a hero token, and for this montage every hero tests as if they also had your exploration skills.]])

----------------------------------------------------------------------------
-- THE SCENE STAGE: montage dice (table rolls, Recovery losses)
----------------------------------------------------------------------------

--The card's title when the roll has no name.
text("stage.dice.title_fallback", [[Dice]])
--One line per roll. {hero} rolls, {label} is what for (the fallback when it
--has no name), {dice} like 1d6, {result} the result or one of the two
--words below.
text("stage.dice.roll_line", [[{hero}: {label} ({dice}) -- {result}]])
text("stage.dice.label_fallback", [[Roll]])
text("stage.dice.result_rolling", [[rolling...]])
text("stage.dice.result_yours", [[your roll]])
--The hint under the card. {heroes} is who has still to roll.
text("stage.dice.hint_yours", [[Roll your dice.]])
text("stage.dice.hint_all_in", [[The dice are in.]])
text("stage.dice.hint_waiting", [[Waiting on the dice for {heroes}...]])
--The button that rolls. Short: a button.
text("stage.dice.roll_button", [[Roll]])

----------------------------------------------------------------------------
-- THE SCENE STAGE: delves and chests
----------------------------------------------------------------------------

--The chest card's title, and the name of its table when it has none.
text("stage.chest.title", [[A chest]])
text("stage.chest.table_fallback", [[Treasure]])
--While the chest is rolled. {hero} is the hero, {total} the roll.
text("stage.chest.prompt_roll", [[Roll for what the chest holds...]])
text("stage.chest.hero_opening", [[{hero} opens the chest...]])
text("stage.chest.hero_rolls", [[{hero} rolls {total}.]])
--Takes the find and moves on. Short: a button.
text("stage.chest.continue_button", [[Continue]])

--What the delve has given so far. {delve} is its name (the fallback when
--it has none); {obstacles} / {chests} / {recoveries} are counts like
--"2 chests".
text("stage.delve.haul_title", [[{delve} so far]])
text("stage.delve.haul_title_fallback", [[The delve]])
text("stage.delve.haul_summary", [[{obstacles} met, {chests} opened. {recoveries} left.]])
--The question at a chest. The first is for a delve taken in order.
text("stage.delve.prompt_ordered", [[Press on, or turn back?]])
text("stage.delve.prompt", [[Press deeper, or turn back with what you have?]])
text("stage.delve.hero_deciding", [[{hero} is deciding whether to press on...]])
--The buttons and their tooltips. {cost} is like "1 Recovery". Short: buttons.
text("stage.delve.press_on_button", [[Press on]])
text("stage.delve.press_on_tooltip", [[Go on to what comes next.]])
text("stage.delve.press_deeper_button", [[Press deeper (lose {cost})]])
text("stage.delve.press_deeper_tooltip", [[Lose {cost} now and face another obstacle. There may be more treasure further in.]])
text("stage.delve.press_deeper_locked_tooltip", [[Pressing deeper costs {cost}, and you do not have one to spare.]])
text("stage.delve.turn_back_button", [[Turn back]])
text("stage.delve.turn_back_tooltip", [[Leave with everything you have found. This ends your turn.]])

----------------------------------------------------------------------------
-- THE MONTAGE STAGE: unresolved threats at the end
----------------------------------------------------------------------------

--Over each Threat nobody dealt with, as its consequence lands.
text("stage.consequence.heading", [[An unresolved threat]])
--{consequence} is the consequence's text.
text("stage.consequence.text", [[Consequence: {consequence}]])
text("stage.consequence.none_written", [[No consequence is written for this threat.]])
--Moves on to the next one. Short: a button.
text("stage.consequence.continue_button", [[Continue]])

----------------------------------------------------------------------------
-- THE MONTAGE STAGE: items beside the hero cards
----------------------------------------------------------------------------

--The heading of an item's tooltip when using it now would help.
text("stage.item.use_now_heading", [[Use it now:]])
--The menu when a player clicks an item. {item} is its name, {mode} which
--way to use it.
text("stage.item.use", [[Use {item}]])
text("stage.item.use_mode", [[Use: {mode}]])
--Why a menu line is greyed out, when no reason is given. Short.
text("stage.item.reason_combat_only", [[combat only]])
--How long the effect lasts. {use} is one of the menu lines above.
text("stage.item.use_lasts_location", [[{use} (lasts one location)]])
text("stage.item.use_lasts_encounter", [[{use} (lasts the whole encounter)]])
--An item's tooltip when it has no name.
text("stage.item.name_fallback", [[Item]])

----------------------------------------------------------------------------
-- THE NARRATIVE STAGE: choosing together
----------------------------------------------------------------------------

--The line under the title. {index} is the section, {count} how many there
--are, {heroes} who still has to choose.
text("stage.narrative.status_arriving", [[Waiting for the party to arrive...]])
text("stage.narrative.status_section", [[Section {index} of {count}]])
text("stage.narrative.status_section_pending", [[Section {index} of {count}  --  still to choose: {heroes}]])
text("stage.narrative.status_section_deciding", [[Section {index} of {count}  --  deciding...]])
text("stage.narrative.status_complete", [[Complete]])
--Added after the author's prompt: how the section is decided.
text("stage.narrative.how_individual", [[Each hero chooses for themselves.]])
text("stage.narrative.how_party", [[The party must agree.]])
text("stage.narrative.how_implicit", [[Everyone must be ready to move on.]])
--Under each hero card. "Chosen" stands in when the option has no name.
--Short: one or two words.
text("stage.narrative.hero_chosen", [[Chosen]])
text("stage.narrative.hero_ready", [[Ready]])
text("stage.narrative.hero_choosing", [[Choosing...]])
--The banner when the party's votes are tied.
text("stage.narrative.split_banner", [[The party is split!]])
--A feature the section unlocked. {feature} is its name.
text("stage.narrative.callout_unlocked", [[{feature} unlocked]])
--After the section. {hero} is who broke the tie (the fallback when unknown).
text("stage.narrative.result_decided_by", [[The party could not agree -- {hero} decided]])
text("stage.narrative.result_decided_by_fallback", [[someone]])
text("stage.narrative.result_moves_on", [[The party moves on.]])

----------------------------------------------------------------------------
-- TACTICAL PREPARATION: spending Intelligence before the fight
----------------------------------------------------------------------------

--The button on each bar. Short: a button.
text("stage.prep.spend_button", [[Spend 1 Intelligence]])
--Small captions under the Intelligence count. {total} is the party's total.
text("stage.prep.pool_yours", [[yours]])
text("stage.prep.pool_yours_to_spend", [[yours to spend]])
text("stage.prep.pool_party_total", [[{total} in the party]])
text("stage.prep.pool_in_party", [[in the party]])
--Under each hero card. Short.
text("stage.prep.hero_ready", [[Ready]])
text("stage.prep.hero_preparing", [[Preparing...]])
--The two buttons. Short: buttons.
text("stage.prep.proceed_button", [[Proceed]])
text("stage.prep.wait_button", [[Wait]])
--The hint line. {heroes} is who the party is waiting for.
text("stage.prep.hint_must_spend", [[Spend what you know before the first blow lands.]])
text("stage.prep.hint_waiting", [[Waiting for {heroes}.]])
text("stage.prep.hint_all_ready", [[Everyone is ready.]])
text("stage.prep.hint_done", [[Draw steel!]])
--Over what the party learned, once everyone is ready.
text("stage.prep.result_title", [[Ready or not, combat is upon us!]])

----------------------------------------------------------------------------
-- THE STORY SCREEN: the ending, before the trip home
----------------------------------------------------------------------------

--The word over the encounter's name.
text("stage.story.victory", [[Victory]])
text("stage.story.defeat", [[Defeat]])
--The button home, and what it says once pressed.
text("stage.story.return_button", [[Return to Blackbottom]])
text("stage.story.returning", [[Returning...]])

----------------------------------------------------------------------------
-- SHARED: tiers and counts
----------------------------------------------------------------------------

--The left column of a test's tier rows (the others are 12-16 and 17+).
--Short: a column of numbers.
text("stage.tier.range_low", [[11 or lower]])
text("stage.tier.range_critical", [[Critical]])
--A tier's name. {tier} is 1, 2 or 3. "_cap" ones start a line.
text("stage.tier.name_cap", [[Tier {tier}]])
text("stage.tier.name", [[tier {tier}]])
text("stage.tier.critical_cap", [[Critical]])
text("stage.tier.critical", [[critical]])
--Counts used in the lines above. {count} is the number.
text("stage.count.steps.one", [[{count} step]])
text("stage.count.steps.other", [[{count} steps]])
text("stage.count.obstacles.one", [[{count} obstacle]])
text("stage.count.obstacles.other", [[{count} obstacles]])
text("stage.count.chests.one", [[{count} chest]])
text("stage.count.chests.other", [[{count} chests]])
text("stage.count.recoveries.one", [[{count} Recovery]])
text("stage.count.recoveries.other", [[{count} Recoveries]])

----------------------------------------------------------------------------
-- MONTAGE: heroes and the stage (EncounterOfTheWeek/EncounterMontage.lua)
----------------------------------------------------------------------------

--A hero's name on their stage card and in every montage line when the
--player never gave the hero a name.
text("montage.hero.unnamed", [[Unnamed Hero]])
--The name of the fight beat of a map that has an encounter but no script
--document.
text("montage.script.implicit_encounter_title", [[Encounter]])

--The first line on the stage when a hero walks up to an opportunity or
--threat that has no scene of its own. {hero} is the hero's name, {entry}
--the opportunity or threat.
text("montage.scene.approaches", [[{hero} approaches {entry}...]])
--Stands in for the hero's name in scene lines when it is missing.
text("montage.scene.hero_fallback", [[The hero]])

----------------------------------------------------------------------------
-- MONTAGE: the roll dialog for a test
----------------------------------------------------------------------------

--Why a standing edge or bane is on a test: an earlier outcome of the
--montage put it there. Shown on the roll dialog's modifier chip.
text("montage.test.granted_reason", [[the party earned it]])
--The same, naming where it was earned. {entry} is the opportunity or threat.
text("montage.test.granted_reason_at", [[the party earned it at {entry}]])

--The "Skilled in <skill>" chip when the skill is lent by Team Leader rather
--than the hero's own. {chip} is the chip's usual name ("Skilled in Sneak").
text("montage.roll.skilled_lent", [[{chip} (Team Leader)]])

--The roll dialog's title when a hero with Pardon My Friend makes another
--hero's failed test. {test} is the test's name, {hero} the hero they step
--in for, {characteristics} the characteristics the test lists.
text("montage.pardon.roll_title", [[{test} (for {hero}): {characteristics}]])
--Stands in for {hero} above when the name is missing.
text("montage.pardon.ally_fallback", [[an ally]])

----------------------------------------------------------------------------
-- MONTAGE: perks on a test (roll dialog chips, offers after a failed test,
-- and the lines added to the test's result)
----------------------------------------------------------------------------

--Roll dialog chips, each a short name and a one-line description.
text("montage.perk.born_tracker.chip", [[Edge: Born Tracker]])
text("montage.perk.born_tracker.description", [[Born Tracker: an edge on tests to track creatures or find your way.]])
text("montage.perk.polymath.chip", [[+1: Polymath]])
text("montage.perk.polymath.description", [[Polymath: +1 on a test to recall lore when no skill you have applies.]])
text("montage.perk.handy.chip", [[+1: Handy]])
text("montage.perk.handy.description", [[Handy: +1 on a test to craft when no skill you have applies.]])
--A Ritualist's blessing on their own test. {hero} is the Ritualist.
text("montage.perk.ritualist.chip", [[Double Edge: blessed by {hero}]])
text("montage.perk.ritualist.description", [[Ritualist: {hero} blessed this test.]])
--Stands in for {hero} above when the name is missing.
text("montage.perk.ritualist.fallback", [[a Ritualist]])
--The bane chip on a Pardon My Friend roll.
text("montage.perk.pardon.bane_chip", [[Bane: Pardon My Friend]])
text("montage.perk.pardon.bane_description", [[Pardon My Friend: stepping in for an ally, you take a bane.]])

--Offers shown after a failed test, under the perk's name.
text("montage.perk.brawny.offer", [[Lose 1d6 + your level Stamina to raise this failed Might test by one tier.]])
text("montage.perk.lucky_dog.offer", [[Lose 1d6 + your level Stamina to raise this failed intrigue test by one tier.]])
--{hero} is the hero who failed the test.
text("montage.perk.pardon.offer", [[Step in: make this Presence test yourself with a bane. Your roll replaces {hero}'s.]])
text("montage.perk.back_into_it.offer", [[Once this montage: turn {hero}'s tier 1 into tier 2.]])
--Stands in for {hero} in the two offers above when the name is missing.
text("montage.perk.hero_fallback", [[the hero]])

--Lines added to the top of a test's result.
text("montage.perk.mighty_leaps.line", [[Mighty Leaps: a Might jump never lands below tier 2]])
--{perk} is the perk's name (Brawny, Lucky Dog), {amount} the Stamina lost.
text("montage.perk.stamina_paid", [[{perk}: lost {amount} Stamina to raise the test a tier]])
--{hero} is the hero with Put Your Back Into It!
text("montage.perk.back_into_it.line", [[{hero} put their back into it: tier 1 became tier 2]])
--Stands in for {hero} above when the name is missing.
text("montage.perk.a_hero_fallback", [[A hero]])
--{hero} is the hero who stepped in; {tier} the tier number they rolled.
text("montage.perk.pardon.line_tier", [[Pardon My Friend: {hero} stepped in and rolled tier {tier}]])
text("montage.perk.pardon.line_critical", [[Pardon My Friend: {hero} stepped in and rolled a critical]])
--Stands in for {hero} in the two lines above when the name is missing.
text("montage.perk.pardon.another_hero", [[another hero]])
--The note in the Hero Token history when Team Leader spends one. {hero} is
--the leader.
text("montage.perk.team_leader.token_note", [[{hero}: Team Leader]])

----------------------------------------------------------------------------
-- MONTAGE: what a test's outcome did (the result lines under a turn, the
-- montage log and the consequences)
----------------------------------------------------------------------------

--{names} is one hero or a list of heroes ("Kira", "Kira and Brann",
--"Kira, Brann and Osk"). The "every hero" lines are used when the outcome
--is for the whole party. Each ".one" line is for one hero, ".other" for
--several (the verb changes).

--How a list of names ends. {names} is every name but the last, joined with
--commas; {last} is the last name.
text("montage.effect.names_and", [[{names} and {last}]])

--Items. {qty} is how many, {item} the item's name.
text("montage.effect.item.party", [[Every hero gains {qty} x {item}]])
text("montage.effect.item.heroes.one", [[{names} gains {qty} x {item}]])
text("montage.effect.item.heroes.other", [[{names} gain {qty} x {item}]])
--The outcome named an item the game does not have.
text("montage.effect.item.unknown", [[Unknown item '{item}']])

--Stamina lost. {amount} is how much.
text("montage.effect.stamina_loss.party", [[Every hero loses {amount} Stamina]])
text("montage.effect.stamina_loss.heroes.one", [[{names} loses {amount} Stamina]])
text("montage.effect.stamina_loss.heroes.other", [[{names} lose {amount} Stamina]])
--Rolled damage to one hero (the assassin's blade). {hero}, {amount}.
text("montage.effect.damage", [[{hero} takes {amount} damage]])

--Stamina healed.
text("montage.effect.heal.party", [[Every hero heals {amount} Stamina]])
text("montage.effect.heal.heroes.one", [[{names} heals {amount} Stamina]])
text("montage.effect.heal.heroes.other", [[{names} heal {amount} Stamina]])

--Temporary Stamina.
text("montage.effect.temp_stamina.party", [[Every hero gains {amount} Temporary Stamina]])
text("montage.effect.temp_stamina.heroes.one", [[{names} gains {amount} Temporary Stamina]])
text("montage.effect.temp_stamina.heroes.other", [[{names} gain {amount} Temporary Stamina]])

--A bigger Recovery Value.
text("montage.effect.recovery_value.party", [[Every hero's Recovery Value +{amount} until the next respite]])
text("montage.effect.recovery_value.heroes", [[{names}: Recovery Value +{amount} until the next respite]])

--Recoveries lost. {recoveries} is the count with its word, from the two
--lines just below ("1 Recovery", "2 Recoveries").
text("montage.effect.recovery_count.one", [[{count} Recovery]])
text("montage.effect.recovery_count.other", [[{count} Recoveries]])
text("montage.effect.recovery_loss.party", [[Every hero loses {recoveries}]])
text("montage.effect.recovery_loss.heroes.one", [[{names} loses {recoveries}]])
text("montage.effect.recovery_loss.heroes.other", [[{names} lose {recoveries}]])
text("montage.effect.no_recoveries_left.one", [[{names} has no Recoveries left to lose]])
text("montage.effect.no_recoveries_left.other", [[{names} have no Recoveries left to lose]])

--Surges at the start of the fight. {surges} is the count with its word,
--from the two lines just below.
text("montage.effect.surge_count.one", [[{count} surge]])
text("montage.effect.surge_count.other", [[{count} surges]])
text("montage.effect.surges.party", [[Every hero begins the encounter with {surges}]])
text("montage.effect.surges.heroes.one", [[{names} begins the encounter with {surges}]])
text("montage.effect.surges.heroes.other", [[{names} begin the encounter with {surges}]])
--The note in a hero's Surges history when they are paid out.
text("montage.effect.surge_note", [[Montage boon]])

--Hero Tokens for the party.
text("montage.effect.hero_tokens.one", [[+{count} Hero Token]])
text("montage.effect.hero_tokens.other", [[+{count} Hero Tokens]])

--Intelligence. {intelligence} is the amount with its word, from the two
--lines just below.
text("montage.effect.intelligence_count.one", [[{count} Intelligence]])
text("montage.effect.intelligence_count.other", [[{count} Intelligence]])
text("montage.effect.intelligence.shared", [[+{intelligence}, shared among the party]])
text("montage.effect.intelligence.heroes.one", [[{names} gains {intelligence}]])
text("montage.effect.intelligence.heroes.other", [[{names} gain {intelligence}]])

--Malice for the Director.
text("montage.effect.malice", [[+{amount} Malice]])

--A monster joins the party. {monster} is its name.
text("montage.effect.ally.joins", [[{monster} joins {names}]])
--The outcome named a monster the game does not have.
text("montage.effect.ally.unknown", [[Unknown monster '{monster}']])
text("montage.effect.ally.no_hero", [[{monster} cannot join: no hero]])
text("montage.effect.ally.not_placed", [[{monster} could not be placed]])

--A threat dealt with.
text("montage.effect.vanquished", [[The threat is vanquished]])
--Challenge Mode: a threat that must be vanquished more than once, after a
--vanquish that did not finish it. {count} is how many more times.
text("montage.effect.vanquished_partly.one", [[The threat is weakened: vanquish it once more]])
text("montage.effect.vanquished_partly.other", [[The threat is weakened: vanquish it {count} more times]])

--A roll on one of the entry's dice tables. {table} is the table's name,
--{total} what was rolled.
text("montage.effect.table.rolled", [[{table}: rolled {total}]])
text("montage.effect.table.missing", [[No table '{table}' to roll on]])

--Bonus to rolled damage.
text("montage.effect.damage_boon.party", [[Every hero gains +{amount} to rolled damage until the next respite]])
text("montage.effect.damage_boon.heroes.one", [[{names} gains +{amount} to rolled damage until the next respite]])
text("montage.effect.damage_boon.heroes.other", [[{names} gain +{amount} to rolled damage until the next respite]])

--Damage immunity. {damage_type} is the damage type ("fire", "poison").
text("montage.effect.immunity.party", [[Every hero gains {damage_type} immunity {amount} until the next respite]])
text("montage.effect.immunity.heroes.one", [[{names} gains {damage_type} immunity {amount} until the next respite]])
text("montage.effect.immunity.heroes.other", [[{names} gain {damage_type} immunity {amount} until the next respite]])

--A lower Stamina maximum.
text("montage.effect.max_stamina.party", [[Every hero's Stamina maximum is reduced by {amount} until the next respite]])
text("montage.effect.max_stamina.heroes", [[{names}: Stamina maximum -{amount} until the next respite]])

--A consumable lost. {item} is the item's name. A hero with none loses a
--Recovery instead (second line); the swap is not mentioned.
text("montage.effect.consumable_lost", [[{hero} loses a {item}]])
text("montage.effect.consumable_recovery_lost", [[{hero} loses 1 Recovery]])

--Shown when something went wrong applying an outcome.
text("montage.effect.failed", [[Some effects could not be applied (see log)]])

--The source written in damage, healing and resource histories.
--{source} is "Montage" (below) or the beat type, {entry} the opportunity,
--threat or narrative option.
text("montage.effect.source_label", [[{source}: {entry}]])
text("montage.effect.source_montage", [[Montage]])

----------------------------------------------------------------------------
-- MONTAGE: dice the players roll (table rolls, Recoveries lost, damage)
----------------------------------------------------------------------------

--What each roll is for, shown beside the dice. Short.
text("montage.dice.damage_label", [[Damage]])
text("montage.dice.recoveries_label", [[Recoveries lost]])
--The roll's name in the roll log. {hero} is the hero rolling, {label} what
--it is for (a table's name, or one of the labels above).
text("montage.dice.roll_description", [[{hero}: {label}]])
--Stand in for {hero} and {label} above when they are missing.
text("montage.dice.hero_fallback", [[Hero]])
text("montage.dice.label_fallback", [[Montage]])

----------------------------------------------------------------------------
-- MONTAGE: delves and chests
----------------------------------------------------------------------------

--Narration when a delve ends and the delve has no scene of its own for it.
--{hero} is the delving hero.
text("montage.delve.forced_out", [[{hero} has no Recoveries left, and must turn back.]])
text("montage.delve.exhausted", [[There is nothing further to find here.]])

--The chest roll's name in the roll log. {delve} is the delve, {chest} the
--chest table's name.
text("montage.chest.roll_description", [[{delve}: {chest}]])
--Stand in for {delve} and {chest} above when they are missing.
text("montage.chest.delve_fallback", [[Delve]])
text("montage.chest.chest_fallback", [[Chest]])

----------------------------------------------------------------------------
-- MONTAGE: using items (the icons beside a hero's stage card)
----------------------------------------------------------------------------

--The menu entry for an item with only one use. Short: a menu entry.
text("montage.item.use_label", [[Use]])
--Why a use is greyed out.
text("montage.item.nothing_to_use", [[This item has nothing to use.]])
text("montage.item.combat_use_only", [[Used in combat, not in a montage.]])
text("montage.item.needs_map", [[Needs the battle map: use it in combat.]])
--The few words on a greyed-out menu entry. Short.
text("montage.item.combat_only_short", [[combat only]])

--Why no item can be used right now.
text("montage.item.blocked.not_rounds", [[Items can be used while the montage rounds are under way.]])
text("montage.item.blocked.rolling", [[Not while this hero's test is being rolled.]])
text("montage.item.blocked.pardon", [[Not while this hero is rolling for Pardon My Friend.]])
text("montage.item.blocked.another_item", [[Another item is being used.]])

--Why using an item failed.
text("montage.item.error.no_hero", [[No such hero.]])
text("montage.item.error.not_your_hero", [[That is not your hero.]])
text("montage.item.error.no_longer_has", [[The hero no longer has that item.]])
text("montage.item.error.cannot_use_here", [[That item cannot be used here.]])
text("montage.item.error.failed", [[Something went wrong using that item.]])

--Hovering an item while a hero is at an entry: what using it would do
--there. {option} is the option's name, {language} a language, {modifier}
--the name of a roll bonus.
text("montage.item.benefit.language", [[Lets you understand the {language} being spoken.]])
text("montage.item.benefit.hidden_option", [[Could reveal a hidden option here.]])
text("montage.item.benefit.knack", [[Opens a knack for {option}.]])
text("montage.item.benefit.edge", [[An edge on {option}.]])
text("montage.item.benefit.double_edge", [[A double edge on {option}.]])
text("montage.item.benefit.modifier", [[{modifier} helps the test for {option}.]])
--Stands in for {option} when the option has no name.
text("montage.item.benefit.option_fallback", [[this option]])

----------------------------------------------------------------------------
-- MONTAGE: the Intelligence pool's history (the pools strip tooltip)
----------------------------------------------------------------------------

--Who earned it, when no opportunity or threat is named.
text("montage.intelligence.history_who_fallback", [[Encounter of the Week]])
--The time of a change that has not reached the server yet.
text("montage.intelligence.history_pending", [[pending]])
--Where spent Intelligence came from when no single hero held it.
text("montage.intelligence.spent_from_party", [[the party]])

----------------------------------------------------------------------------
-- MONTAGE: the Secret Twin's assassin (an extra threat for a hero marked in
-- town). These lines are written into the threat as if an author had.
-- Keep the threat name free of "(", ")" and ":": they would break it.
----------------------------------------------------------------------------

--The threat's name on the stage. {hero} is the hunted hero. This and the
--four entries below are fed through the script reader, so never use ( ) or
--a colon in them, and never start a line with | or a word followed by a colon.
text("montage.assassin.threat_name", [[An Assassin Hunts {hero}]])
--The threat's description.
text("montage.assassin.description", [[Someone from {hero}'s past has caught up with them: a killer is closing in.]])
--What happens if nobody stops it (shown as its Consequence, and in the
--result). Keep it about the 4d6 damage: that is what is rolled.
text("montage.assassin.consequence", [[{hero} takes 4d6 damage]])
--The one option for dealing with it. Short: an option name.
text("montage.assassin.option_name", [[Ambush the Assassin]])
--The option's tier 1 result: story only, no rules words.
text("montage.assassin.tier1", [[The assassin slips away into the shadows.]])
--The damage roll's label. Short.
text("montage.assassin.dice_label", [[Assassin's blade]])

----------------------------------------------------------------------------
-- MONTAGE: boons and curses on the character sheet (the ongoing effects an
-- outcome puts on a hero). Each is made once per game, so a change only
-- shows in games where it has not been made yet. {amount} is the number.
----------------------------------------------------------------------------

text("montage.boon.recovery_description", [[Your Recovery Value is increased by {amount}.]])
text("montage.boon.damage_description", [[You gain a +{amount} bonus to rolled damage.]])
--The roll bonus's own description, shown on the roll dialog.
text("montage.boon.damage_modifier_description", [[+{amount} to rolled damage.]])
text("montage.curse.max_stamina_description", [[Your Stamina maximum is reduced by {amount}.]])
--{damage_type} is the damage type ("fire", "poison").
text("montage.boon.immunity_description", [[You have {damage_type} immunity {amount}.]])

----------------------------------------------------------------------------
-- NARRATIVE SCENES: the party choosing together
----------------------------------------------------------------------------

--The name shown for the shared "party" voter in a scene the party decides
--together, when the heroes belong to the whole table rather than to one
--player.
text("narrative.party_name", [[The party]])
--Where a scene's effects came from, in a hero's Stamina and resource
--history. Shown as "Narrative: <the scene's name>". Short.
text("narrative.effect_source", [[Narrative]])

----------------------------------------------------------------------------
-- TACTICAL PREPARATION: spending Intelligence before combat
----------------------------------------------------------------------------

--The screen's title and the line under it.
text("prep.title", [[Tactical Preparation]])
text("prep.instructions", [[Combat is upon you! Spend your Intelligence wisely.]])

--The Surprise bar: its name, then what each level means, worst to best.
text("prep.surprise.title", [[Surprise]])
text("prep.surprise.level0", [[You are surprised.]])
text("prep.surprise.level1", [[You lose the initiative.]])
text("prep.surprise.level2", [[You roll for initiative.]])
text("prep.surprise.level3", [[You win the initiative.]])
text("prep.surprise.level4", [[The enemy is surprised.]])

--The Traps bar: its name, then what each level means, worst to best.
text("prep.traps.title", [[Traps]])
text("prep.traps.level0", [[You are unaware of traps.]])
--Level 1, on a map that has traps.
text("prep.traps.level1", [[You know where some of the traps are.]])
--Level 1, on a map with no traps at all.
text("prep.traps.level1_none", [[There are no traps on the map.]])
text("prep.traps.level2", [[All traps on the map are marked.]])

--The Enemy Stamina bar: its name, then what each level means, worst to best.
text("prep.stamina.title", [[Enemy Stamina]])
text("prep.stamina.level0", [[You have little awareness of the enemy's health.]])
text("prep.stamina.level1", [[You see enemy stamina bars.]])
text("prep.stamina.level2", [[You fully know the stamina of your enemies.]])

--Who spent or is ready, when the heroes belong to the whole table rather
--than to one player.
text("prep.party_name", [[The party]])
--A line in the Intelligence pool's history when a point is spent.
--{screen} is this screen's title (Tactical Preparation), {bar} the bar it
--was spent on (Surprise, Traps, ...), {heroes} the heroes whose
--Intelligence paid for it.
text("prep.intelligence_log.spend", [[{screen}: {bar} ({heroes})]])
--Where the preparation's effects came from, in a hero's Stamina and
--resource history. Shown as "Preparation: Tactical Preparation". Short.
text("prep.effect_source", [[Preparation]])

----------------------------------------------------------------------------
-- THE ENCOUNTER INTERFACE: the pool strip (Malice, Hero Tokens,
-- Intelligence)
----------------------------------------------------------------------------

--Each pool's name, the heading of its change history in the tooltip.
text("hud.pool.malice.title", [[Malice]])
text("hud.pool.herotokens.title", [[Hero Tokens]])
text("hud.pool.intelligence.title", [[Intelligence]])

--The tooltip explaining each pool. **...** is bold, a line starting with
--"* " is a bullet. The Hero Tokens text matches the hero tokens tooltip on
--the character sheet; keep the two the same.
text("hud.pool.malice.explanation", [[**Malice**

This is a power used by Monsters to charge their most powerful abilities. It will be used against you in battle, so beware!]])
text("hud.pool.herotokens.explanation", [[**Hero Tokens**
* You can spend a hero token to gain two surges.
* You can spend a hero token when you fail a saving throw to succeed instead.
* You can reroll the result of a test. You must use the new result.
* You can spend 2 hero tokens to regain Stamina equal to your Recovery value without spending a Recovery.]])
text("hud.pool.intelligence.explanation", [[**Intelligence**

The amount of awareness you have of what you are up against. It can be used at the start of a fight to control how much you know about the encounter.]])

----------------------------------------------------------------------------
-- THE ENCOUNTER INTERFACE: the corner buttons and the map credit
----------------------------------------------------------------------------

--The tooltip on the book button that opens the encounter's rules. Short.
text("hud.rules_button.tooltip", [[Encounter Rules]])
--The start of the tooltip on the map maker's logo in the corner of the map;
--the map maker's name follows it.
text("hud.map_credit.lead", [[Map by]])

----------------------------------------------------------------------------
-- ABOUT ENCOUNTER OF THE WEEK: the dialog from the Codex menu
----------------------------------------------------------------------------

--The Codex menu item that opens the dialog, and the dialog's title.
text("hud.about.menu_item", [[About Encounter of the Week]])
text("hud.about.title", [[About Encounter of the Week]])
--The credits, one line each. {name} is the credited name (it may be a link).
text("hud.about.credit.draw_steel", [[<b>Draw Steel</b> by {name}]])
text("hud.about.credit.eotw", [[<b>Encounter of the Week</b> concept and engineering by {name}]])
text("hud.about.credit.eotw_name", [[the Codex Development Team]])
text("hud.about.credit.cartography", [[<b>Cartography</b> by {name}]])
--The heading over the encounter being played. {title} is its name.
text("hud.about.encounter_heading", [[About {title}]])
--Under that heading. {name} is the encounter's author, or the map's maker
--(bold, and a link when they have a website).
text("hud.about.written_by", [[Written by {name}]])
text("hud.about.map_by", [[Map by {name}]])
--Short: a button.
text("hud.about.close", [[Close]])

----------------------------------------------------------------------------
-- PLAYERS LEAVING AND COMING BACK: the notices under the players row
----------------------------------------------------------------------------

--A player's name when the game cannot find it.
text("presence.player_fallback", [[A player]])
--A hero's name when the game cannot find it.
text("presence.hero_fallback", [[Unnamed Hero]])
--Joins the last name onto a list of names: "Ana, Bo and Cy". {list} is the
--names before the last (already separated by commas), {last} the last one.
text("presence.names_and", [[{list} and {last}]])

--A player left. {name} is who left, {controller} the player now running
--their heroes, {heroes} those heroes' names ("Ana and Bo").
--Seen by the player who takes over, when the leaver had no heroes:
text("presence.left.you_control_nothing", [[{name} has left. You control what they controlled until they return.]])
--Seen by the player who takes over:
text("presence.left.you_control", [[{name} has left. You control {heroes} until they return.]])
--Seen by everyone else, when the leaver had no heroes:
text("presence.left.no_heroes", [[{name} has left.]])
--Seen by everyone else:
text("presence.left.other_controls", [[{name} has left. {controller} controls {heroes} until they return.]])

--A player abandoned the game for good. Same placeholders as above.
text("presence.abandoned.no_heroes", [[{name} has abandoned the game.]])
text("presence.abandoned.you_control", [[{name} has abandoned the game. You control {heroes} from now on.]])
text("presence.abandoned.other_controls", [[{name} has abandoned the game. {controller} controls {heroes} from now on.]])

--Hosting moved to another player. {previous} is the old host's name.
--Seen by the new host:
text("presence.newhost.you", [[You are now the host, taking over from {previous}.]])
--{previous} when the old host's name is not known.
text("presence.newhost.previous_fallback", [[the previous host]])
--Seen by everyone else. {name} is the new host.
text("presence.newhost.other", [[{name} is now the host.]])

--A player came back. {name} is who, {heroes} the heroes handed back to them.
--Seen by the returning player, who had no heroes:
text("presence.returned.you", [[Welcome back.]])
--Seen by the returning player:
text("presence.returned.you_control", [[Welcome back. You control {heroes} again.]])
--Seen by everyone else:
text("presence.returned.no_heroes", [[{name} is back.]])
text("presence.returned.other_controls", [[{name} is back and controls {heroes} again.]])

--The host handed a free agent to a player. {heroes} is the hero, {name} its
--real player (who has left), {controller} the player now running it.
--Seen by the player who receives it:
text("presence.given.you_control", [[You now control {heroes} until {name} returns.]])
--The same, when its player abandoned the game (they will not return):
text("presence.given.you_control_abandoned", [[You now control {heroes}.]])
--Seen by everyone else:
text("presence.given.other_controls", [[{controller} now controls {heroes} until {name} returns.]])
text("presence.given.other_controls_abandoned", [[{controller} now controls {heroes}.]])

--The button on a "has left" notice that opens the players list so the host
--can hand the heroes on. Short: a button.
text("presence.notice.reassign_button", [[Reassign]])

----------------------------------------------------------------------------
-- PLAYERS LEAVING AND COMING BACK: when the host leaves
----------------------------------------------------------------------------

--Shown to the game's owner on coming back to a game another player is
--hosting. {hosts} is that player's name (or names).
text("presence.reclaim.notice", [[Welcome back. {hosts} is hosting the game while you were away.]])
--Short: a button.
text("presence.reclaim.button", [[Reclaim Host]])
--Shown to everyone when the host has gone. {host} is the host's name.
text("presence.hostgone.notice", [[{host}, the host, has left. Nobody can play on until someone takes over hosting.]])
--{host} when the host's name is not known.
text("presence.hostgone.host_fallback", [[The host]])
--Short: a button.
text("presence.hostgone.button", [[Claim Host]])
--When taking over hosting fails. {message} is the reason the server gave.
text("presence.host_request.refused", [[Could not take over hosting: {message}]])
text("presence.host_request.unreachable", [[Could not reach the server to change the host: {message}]])
--{message} in the first of those when the server's answer made no sense.
text("presence.host_request.invalid_response", [[invalid response]])

----------------------------------------------------------------------------
-- LEAVING THE ENCOUNTER: the dialog on Leave or Quit
----------------------------------------------------------------------------

--The title: on Quit (closing the app), and on Leave.
text("presence.exit.title_quit", [[Quit the Encounter?]])
text("presence.exit.title_leave", [[Leave the Encounter?]])
text("presence.exit.body", [[You are leaving the Encounter of the Week. You can resume later.]])
--The small print under it. Shown to the host while others are playing:
text("presence.exit.note_host", [[You are the host: the others will be asked to take over hosting while you are away.]])
--While others are playing:
text("presence.exit.note_abandon", [[You will give up on the game. Remaining players may continue it, controlling your heroes.]])
--When this is the last player in the game:
text("presence.exit.note_abandon_last", [[The game will end.]])
--The buttons. Short.
text("presence.exit.cancel_button", [[Cancel]])
text("presence.exit.quit_button", [[Quit]])
text("presence.exit.leave_button", [[Leave]])
text("presence.exit.abandon_button", [[Abandon Game]])
--The abandon button after one click: a second click confirms.
text("presence.exit.abandon_confirm", [[Really abandon?]])

----------------------------------------------------------------------------
-- THE PLAYERS LIST: the popout under the title bar's players row
----------------------------------------------------------------------------

--The heading, and the hint under it. The host sees the longer hint.
text("presence.players.title", [[Players]])
text("presence.players.hint", [[Free agents are heroes whose player has left. They go back to their player when they return.]])
text("presence.players.hint_host", [[Free agents are heroes whose player has left. They go back to their player when they return. As the host you control them, or you can hand them to another player.]])
--Beside each player's name. Short.
text("presence.players.status_here", [[Here]])
text("presence.players.status_away", [[Away]])
text("presence.players.status_abandoned", [[Abandoned]])
--The status of the player who hosts. {status} is one of the three above.
text("presence.players.status_host", [[{status} - Host]])
--Under a player with no heroes.
text("presence.players.no_heroes", [[No heroes]])
text("presence.players.no_heroes_away", [[Their heroes are free agents until they return]])
text("presence.players.no_heroes_abandoned", [[Their heroes fight on as free agents]])
--Under a hero whose player has left. {owner} is that player's name.
text("presence.players.free_agent", [[Free agent: {owner}'s hero]])
--The same, when that player abandoned the game.
text("presence.players.free_agent_abandoned", [[Free agent: {owner}'s hero (abandoned)]])

----------------------------------------------------------------------------
-- THE SCRIPT: optional features a script turns on (narrative beats)
----------------------------------------------------------------------------

--The name of the Intelligence feature, shown when it is unlocked and in the
--Encounter Builder's feature list. Short: a name.
text("script.feature.intelligence.name", [[Intelligence]])
--Shown to the party the moment a narrative scene unlocks Intelligence.
text("script.feature.intelligence.explanation", [[Intelligence is an important currency! When an encounter begins you will be able to spend your Intelligence gained to sway things in your favor. Try to acquire as much as you can.]])

----------------------------------------------------------------------------
-- THE SCRIPT: narrative sections with no choices
----------------------------------------------------------------------------

--The one option of a narrative section that offers no choices: the party
--simply reads on. Short: a button-sized card name.
text("script.narrative.proceed", [[Proceed]])

----------------------------------------------------------------------------
-- THE SCRIPT: what an outcome did (montage and narrative outcome lists)
----------------------------------------------------------------------------

--A standing edge or bane the party earned on another test of the montage.
--{test} is that test's name.
text("script.test_mod.edge", [[The party has an edge on {test}]])
text("script.test_mod.double_edge", [[The party has a double edge on {test}]])
text("script.test_mod.bane", [[The party has a bane on {test}]])
text("script.test_mod.double_bane", [[The party has a double bane on {test}]])
--A locked opportunity or threat joining the board. {entry} is its name.
text("script.unlock", [[{entry} is now available]])
--{zone} is the zone type's name (e.g. Start2).
text("script.start_zone", [[The heroes may also start the encounter in the {zone} zone]])
--{object} is a map object's name (e.g. Treasure Chest).
text("script.reveal_object", [[The {object} will be on the map when the encounter begins]])
--{zones} is the zone type's name, capitalized and with an "s" added (e.g. Traps).
text("script.reveal_zones", [[The {zones} will be revealed during the next combat]])
--{monsters} is a monster keyword, capitalized and with an "s" added (e.g. Goblins).
text("script.know_stamina", [[The party knows the Stamina of {monsters}]])
text("script.fair_initiative", [[The encounter begins with a fair roll for initiative]])
text("script.no_surprise", [[The heroes cannot be surprised]])

--What the coming encounter's initiative will be.
--When the heroes are to be surprised but already cannot be surprised:
text("script.initiative.surprised_but_immune", [[The heroes will lose initiative, but they cannot be surprised]])
text("script.initiative.surprised", [[The heroes will begin the encounter surprised]])
text("script.initiative.surprise", [[The heroes will surprise the enemy]])
text("script.initiative.win", [[The heroes will win initiative]])
text("script.initiative.lose", [[The heroes will lose initiative]])
--Fallback for any other outcome; {outcome} is its short name (e.g. win).
text("script.initiative.other", [[initiative: {outcome}]])

----------------------------------------------------------------------------
-- THE SCRIPT: an extra way to win the encounter ("Victory:" line)
----------------------------------------------------------------------------

text("script.victory.clear_map", [[Or defeat every enemy on the map]])
--{who} is the kind of creature, as the author wrote it (e.g. Dwarf).
text("script.victory.clear_map_of", [[Or defeat every {who} on the map]])

----------------------------------------------------------------------------
-- THE SCRIPT: a rule in plain words (narrative option cards, and the
-- Encounter Builder's script checker)
----------------------------------------------------------------------------

--Each rule comes in two versions: .self for the hero who took it, .party
--for every hero. {qty} is a number.
--{item} is the item's name.
text("script.effect.item.self", [[the hero gains {qty} x {item}]])
text("script.effect.item.party", [[every hero gains {qty} x {item}]])
text("script.effect.stamina.self", [[the hero loses {qty} stamina]])
text("script.effect.stamina.party", [[every hero loses {qty} stamina]])
text("script.effect.heal.self", [[the hero heals {qty} stamina]])
text("script.effect.heal.party", [[every hero heals {qty} stamina]])
text("script.effect.temp_stamina.self", [[the hero gains {qty} temporary stamina]])
text("script.effect.temp_stamina.party", [[every hero gains {qty} temporary stamina]])
text("script.effect.surges.self.one", [[the hero gains {count} surge at the start of the next combat]])
text("script.effect.surges.self.other", [[the hero gains {count} surges at the start of the next combat]])
text("script.effect.surges.party.one", [[every hero gains {count} surge at the start of the next combat]])
text("script.effect.surges.party.other", [[every hero gains {count} surges at the start of the next combat]])
text("script.effect.recovery_value.self", [[the hero's recovery value is increased by {qty} until the next respite]])
text("script.effect.recovery_value.party", [[every hero's recovery value is increased by {qty} until the next respite]])
--{dice} is a dice expression such as 1d3.
text("script.effect.lose_recoveries_dice.self", [[the hero loses {dice} recoveries (rolled for each hero)]])
text("script.effect.lose_recoveries_dice.party", [[every hero loses {dice} recoveries (rolled for each hero)]])
text("script.effect.lose_recoveries.self.one", [[the hero loses {count} recovery]])
text("script.effect.lose_recoveries.self.other", [[the hero loses {count} recoveries]])
text("script.effect.lose_recoveries.party.one", [[every hero loses {count} recovery]])
text("script.effect.lose_recoveries.party.other", [[every hero loses {count} recoveries]])
text("script.effect.hero_tokens.one", [[the party gains {count} hero token]])
text("script.effect.hero_tokens.other", [[the party gains {count} hero tokens]])
text("script.effect.intelligence", [[the party gains {qty} Intelligence]])
text("script.effect.malice", [[+{qty} malice]])
--A story track changing. {track} is the track's name, {delta} the change
--with its sign, like "+1" or "-2".
text("script.effect.track", [[{track} {delta}]])
--A track the script never declared. {track} is its name.
text("script.effect.track_undeclared", [[nothing ('{track}' is not a declared track)]])
--{ally} is the monster's name.
text("script.effect.ally", [[{ally} joins the hero]])
text("script.effect.vanquish", [[the threat is vanquished]])
--{entry} is the name of a locked opportunity or threat.
text("script.effect.unlock", [[unlock '{entry}']])
--{test} is the name of another test of the montage.
text("script.effect.test_mod.edge", [[edge on '{test}']])
text("script.effect.test_mod.double_edge", [[double edge on '{test}']])
text("script.effect.test_mod.bane", [[bane on '{test}']])
text("script.effect.test_mod.double_bane", [[double bane on '{test}']])
--{table} is a dice table's name; {times} is how many rolls (2 or more).
text("script.effect.roll_table.once", [[roll once on '{table}']])
text("script.effect.roll_table.times", [[roll {times} times on '{table}']])
text("script.effect.rolled_damage.self", [[the hero's rolled damage +{qty} until the next respite]])
text("script.effect.rolled_damage.party", [[every hero's rolled damage +{qty} until the next respite]])
--{damage_type} is a damage type (e.g. poison).
text("script.effect.immunity.self", [[the hero gains {damage_type} immunity {qty} until the next respite]])
text("script.effect.immunity.party", [[every hero gains {damage_type} immunity {qty} until the next respite]])
text("script.effect.max_stamina.self", [[the hero's maximum stamina -{qty} until the next respite]])
text("script.effect.max_stamina.party", [[every hero's maximum stamina -{qty} until the next respite]])
text("script.effect.lose_consumables.self.one", [[the hero loses {count} consumable (a recovery if none)]])
text("script.effect.lose_consumables.self.other", [[the hero loses {count} consumables (a recovery if none)]])
text("script.effect.lose_consumables.party.one", [[every hero loses {count} consumable (a recovery if none)]])
text("script.effect.lose_consumables.party.other", [[every hero loses {count} consumables (a recovery if none)]])
--A line of plain story with no rule in it. {text} is the author's words.
text("script.effect.narrative", [[narrative: {text}]])
--The same, when the words looked like a rule the game could not read.
text("script.effect.narrative_unrecognized", [[narrative (unrecognized): {text}]])
