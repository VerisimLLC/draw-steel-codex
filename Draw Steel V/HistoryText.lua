local mod = dmhub.GetModLoading()

--History (History.lua, HistoryCapture.lua, HistoryCard.lua, HistoryTray.lua): the words of
--the History window, its rows and lines, the detail card a row opens, the search, and the
--small text written under each line as it happens.
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
--  * Some entries start with a space or a comma, or are only part of a sentence:
--    the game joins them to the words around them. Keep that space or comma.
--  * Two entries ending .one and .other are the same line for a count of one
--    and for any other count.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("HistoryText")

----------------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------------

--A player's own choice, in General Settings.
text("history.settings.use_old_log_name", [[Use Old Action Log]])
text("history.settings.use_old_log_help", [[Show the old Action Log instead of History]])
--The Director's switch for the whole game, in Game Settings.
text("history.settings.record_name", [[Record History]])
text("history.settings.record_help", [[Record play in History. When off, nothing is recorded and everyone sees the old Action Log.]])
--History's own settings, in Settings.
text("history.settings.notifications_name", [[History notifications]])
text("history.settings.sidebar_preview_name", [[History Sidebar Preview]])
text("history.settings.sidebar_preview_help", [[Briefly shows actions from other turns beside the History button while History is closed.]])

----------------------------------------------------------------------------
-- WORDS USED ALL OVER HISTORY
----------------------------------------------------------------------------

--Who stands for a creature players may not see.
text("history.unknown_creature", [[Unknown creature]])
--The Director, where History names who did something.
text("history.director", [[Director]])
--Something that belongs to someone: "Ana's Fireball".
text("history.possessive", [[{owner}'s {name}]])
text("history.round", [[Round {round}]])
--A downtime project's event rolled on its table: "Seek the Lost Sword event".
text("history.project_event", [[{project} event]])
--A table roll whose table has no name.
text("history.table", [[Table]])
--Someone on the heroes' side, when the line has no name for them.
text("history.a_hero", [[A Hero]])
text("history.tier", [[Tier {tier}]])
--A change someone made by hand, not by a rule or ability.
text("history.set_by_hand", [[Set by hand]])
--The Director's eye on something players can't see, on hover.
text("history.hidden_from_players", [[Hidden from players]])
--The Director's eye on a hidden roll, on hover, once it is shown to players.
text("history.visible_to_everyone", [[Visible to everyone]])
--Someone chose the result after the dice landed: a tier badge's hover, and after a line.
text("history.overridden", [[Overridden]])
--A list of three or more: {most} is all but the last, joined by commas.
text("history.list.and", [[{most} and {last}]])
--Names for things a line has no name for.
text("history.a_project", [[A project]])
text("history.the_npc", [[the NPC]])
text("history.reinforcements", [[Reinforcements]])
--The word before the last of a list ("Goblin, Orc and Troll").
text("history.join.and", [[and]])
--The same, for a list of choices ("is no longer winded or dying").
text("history.join.or", [[or]])
--How a forced move reads after a creature's name ("was pushed 3 squares"). Any other
--kind of move reads "moved".
text("history.moved_verb.push", [[pushed]])
text("history.moved_verb.pull", [[pulled]])
text("history.moved_verb.slide", [[slid]])
text("history.moved_verb.teleport", [[teleported]])
text("history.moved_verb.moved", [[moved]])
--A resource spent or gained: "3 surges", but this for one.
text("history.resource.one_surge", [[1 surge]])
--The small tags beside a row or the card's title.
text("history.tag.villain_action", [[Villain Action]])
text("history.tag.reverted", [[Reverted]])
text("history.tag.ended", [[Ended]])
text("history.tag.active", [[Active]])
--A montage test's result.
text("history.tag.success", [[Success]])
text("history.tag.failure", [[Failure]])

----------------------------------------------------------------------------
-- THE TRAY: rows, turns, rounds and the buttons on them
----------------------------------------------------------------------------

--What sort of action a row was, beside its title and on the card. Room is kept for
--about "Triggered action": a much longer word would be cut short.
text("history.action.main", [[Main action]])
text("history.action.maneuver", [[Maneuver]])
text("history.action.freestrike", [[Free strike]])
text("history.action.triggered", [[Triggered action]])
--A row's hover: click it to open its detail card.
text("history.tray.open_detail_tooltip", [[Open the detail]])
--A roll nested under the action that asked for it: "Gordon rolled 14".
text("history.tray.roll.secret", [[rolled in secret]])
text("history.tray.roll.rolled", [[rolled {total}]])
--How an opposed power roll came out against one target: "Succeeded - 14 against 9".
text("history.tray.opposed.tied", [[Tied]])
text("history.tray.opposed.succeeded", [[Succeeded]])
text("history.tray.opposed.failed", [[Failed]])
text("history.tray.opposed.totals", [[{total} against {against}]])
--The tag on a trigger nested under an action: when it happened.
text("history.tray.trigger.triggered", [[Triggered]])
text("history.tray.trigger.free", [[Free]])
text("history.tray.trigger.before", [[Before the roll]])
text("history.tray.trigger.during", [[During the roll]])
text("history.tray.trigger.after", [[After the roll]])
--What a trigger used from the roll dialog did to the tier. {amount} is signed: +1, -2.
text("history.tray.trigger.tiers.one", [[{amount} tier]])
text("history.tray.trigger.tiers.other", [[{amount} tiers]])
--The chip on a row whose roll was a natural 19 or 20.
text("history.tray.critical", [[Critical]])
--Beside a heal that spent a Recovery, or a resource line: gives it back.
text("history.tray.undo", [[Undo]])
--A turn's heading and fold line: "Turn 3 - Hero turn - 4 minions".
text("history.tray.turn", [[Turn {turn}]])
text("history.tray.turn.hero", [[Hero turn]])
text("history.tray.turn.enemy", [[Enemy turn]])
--How many minions take the turn together.
text("history.tray.turn.minions", [[{count} minions]])
--What the creature whose turn it is still has to use, as the action bar shows it.
text("history.tray.pip.main", [[Main]])
text("history.tray.pip.maneuver", [[Maneuver]])
text("history.tray.pip.move", [[Move]])
--Where the turns you have not seen start.
text("history.tray.new_marker", [[New since you last looked]])
--A section heading out of combat, when the game mode has no name.
text("history.tray.exploration", [[Exploration]])
--Under a trigger that fired because a creature fell on its target.
text("history.tray.landed_on_by", [[Landed on by {name}]])
--On the right of a round's heading.
text("history.tray.round_malice", [[Malice {before} to {after}]])
--Folded turns and rounds: "Turns 1-4", "Combat - Rounds 1-3". {dash} is a dash the code fills in.
text("history.tray.turns", [[Turns {first}{dash}{last}]])
text("history.tray.combat", [[Combat]])
text("history.tray.rounds", [[Rounds {first}{dash}{last}]])
--The pill at the foot of the list that scrolls to the newest row.
text("history.tray.new_below", [[{count} new below]])
text("history.tray.latest", [[Latest]])
--In place of the rows on a map with no History yet.
text("history.tray.empty_map", [[Nothing has happened on this map yet.]])
--The map switcher's hover.
text("history.tray.map_switcher_tooltip", [[Display history for another map]])
--Who goes first, under the Draw Steel swords and on the combat's first line.
text("history.draw_steel.heroes_first", [[Heroes go first]])
text("history.draw_steel.enemies_first", [[Enemies go first]])
--The Draw Steel die, when one was rolled. Keep the leading space.
text("history.draw_steel.rolled", [[ (rolled {rolled})]])

----------------------------------------------------------------------------
-- THE TRAY: the small captions under a target
----------------------------------------------------------------------------

--The small captions under a target on a row.
text("history.caption.winded", [[Winded]])
text("history.caption.dying", [[Dying]])
text("history.caption.killed", [[Killed]])
text("history.caption.squad_destroyed", [[Squad destroyed]])
text("history.caption.minions_killed", [[{killed} of {total} killed]])
--Forced movement. {kind} is the move, capitalised: Push, Pull, Slide, Vertical push, ...
text("history.caption.moved.immune", [[Immune to forced movement]])
text("history.caption.moved.stopped", [[{kind} stopped]])
text("history.caption.moved.blocked", [[{kind} blocked]])
text("history.caption.moved.fell_only", [[Fell {distance}]])
text("history.caption.moved.distance", [[{kind} {distance}]])
--These follow the move, after a dot.
text("history.caption.moved.stability", [[Stability {stability}]])
text("history.caption.moved.walls.one", [[Broke {count} wall]])
text("history.caption.moved.walls.other", [[Broke {count} walls]])
text("history.caption.moved.fell", [[fell {distance}]])
--An area ability caught a creature on its user's side.
text("history.caption.ally_hit", [[Ally hit]])
text("history.caption.landed_on", [[Landed on]])
--{state} is winded or dying.
text("history.caption.no_longer", [[No longer {state}]])
--{type} is the damage type, capitalised.
text("history.caption.immunity", [[{type} immunity -{amount}]])
text("history.caption.weakness", [[{type} weakness +{amount}]])
text("history.caption.soaked", [[{amount} soaked by temporary Stamina]])
text("history.caption.temporary_stamina", [[temporary Stamina {before} to {after}]])
text("history.caption.resisted", [[Resisted]])

----------------------------------------------------------------------------
-- THE TRAY: lines, for what happened outside any action
----------------------------------------------------------------------------

--A line: something that happened outside any action. {name} is the creature's name, in
--bold, or nothing when there is none.
text("history.line.damage_typed", [[{name} took {amount} {type} damage]])
text("history.line.damage", [[{name} took {amount} damage]])
text("history.line.heal", [[{name} regained {amount} Stamina]])
--How long a condition lasts, after its name: {duration} is "save ends", "EoT" or "EoE". Keep the leading space.
text("history.line.duration", [[ ({duration})]])
text("history.line.renewed", [[{name}'s {effect} was renewed]])
text("history.line.condition", [[{name} is {condition}{duration}]])
text("history.line.effect", [[{name} {effect}{duration}]])
--What ended. {names} is one name, or a list.
text("history.line.ended", [[{name} {names}]])
text("history.line.rolled_in_secret", [[{name} rolled in secret]])
text("history.line.rolled", [[{name} rolled {total}]])
text("history.line.save_passed", [[{name} saved against {effect}]])
text("history.line.save_failed", [[{name} failed a save against {effect}]])
text("history.line.persistence", [[{name} stopped maintaining {ability}]])
--A Talent's heroic resource went below 0, or back.
text("history.line.strained", [[{name} is strained]])
text("history.line.not_strained", [[{name} is no longer strained]])
--A note card posted outside any action. {title} is the note's title.
text("history.line.note", [[{name} {title}]])
text("history.line.captain", [[{name} is now {squad}'s captain]])
text("history.line.captain.the_squad", [[the squad]])
text("history.line.encounter_ended", [[<b>Encounter ended</b>]])
--{project} is the project's name, in bold.
text("history.line.project_completed", [[{project} completed]])
text("history.line.project_milestone", [[{project} reached a milestone]])
--A negotiation. {npc} is the NPC's name, in bold; {trait} a motivation or pitfall.
text("history.line.negotiation.began", [[Negotiation with {npc}]])
text("history.line.negotiation.ended", [[Negotiation with {npc} ended]])
text("history.line.negotiation.pitfall", [[{name} hit a pitfall: {trait}]])
text("history.line.negotiation.reveal", [[{npc} {trait} revealed]])
--The Director moved a meter. {which} is "interest" or "patience", as the game stores it.
text("history.line.negotiation.adjust", [[{npc} {which} {before} to {after}]])
--A montage.
text("history.line.montage.threat", [[<b>{threat}</b> was not vanquished]])
text("history.line.montage.a_threat", [[A threat]])
text("history.line.montage.ended", [[<b>Montage ended</b>]])
--The Director moved a montage's counter. {counter} is "successes" or "failures", as the game stores it.
text("history.line.montage.counter", [[<b>{montage}</b> {counter} {before} to {after} of {limit}]])
text("history.line.montage.montage", [[Montage]])
--A spoilered modifier the Director revealed.
text("history.line.reveal_alone", [[<b>{modifier}</b> revealed]])
text("history.line.reveal", [[{name} {modifier} revealed]])
text("history.line.turn_reverted", [[<b>Turn reverted</b>]])
text("history.line.reinforcements", [[<b>{wave}</b> arrived]])
text("history.line.stamina_set", [[{name} Stamina {before} to {after}]])
--What a macro gave a Hero.
text("history.line.award.victories.one", [[{name} gained {count} Victory]])
text("history.line.award.victories.other", [[{name} gained {count} Victories]])
--{quantity} is the line below when there is more than one, or nothing.
text("history.line.award.item", [[{name} received {item}{quantity}]])
text("history.line.award.quantity", [[ x{quantity}]])
text("history.line.award.an_item", [[an item]])
text("history.line.award.title", [[{name} earned the title {title}]])
text("history.line.award.renown", [[{name} Renown {before} to {after}]])
text("history.line.award.wealth", [[{name} Wealth {before} to {after}]])
text("history.line.respite", [[{name} took a respite]])
text("history.line.level_up", [[{name} reached Level {level}]])
--The start of a combat, before who goes first.
text("history.line.draw_steel", [[<b>Draw Steel!</b>]])
text("history.line.killed", [[{name} was killed]])
--{state} is "winded" or "dying", as the game stores it.
text("history.line.threshold", [[{name} is {state}]])
text("history.line.minions", [[<b>{squad}</b> {killed} of {total} minions killed]])
--Forced movement. {kind} is push, pull or slide; {verb} is "pushed", "pulled", ...
text("history.line.moved.immune", [[{name} is immune to forced movement]])
text("history.line.moved.held_ground", [[{name} held its ground: stability {stability} stopped the {kind}]])
text("history.line.moved.distance", [[{name} was {verb} {squares}]])
text("history.line.moved.blocked", [[{name} was blocked and didn't move]])
text("history.line.moved.distance_of", [[{name} was {verb} {distance} of {requested} squares (stability {stability})]])
text("history.line.resource", [[{name} {verb} {resource}]])
text("history.line.malice_director", [[<b>Director</b> Malice]])
text("history.line.malice", [[{name} Malice]])
text("history.line.temporary_stamina", [[{name} temporary Stamina]])
--The number at the end of a temporary Stamina, Malice or Hero Token line.
text("history.line.number_change", [[{before} to {after}]])

----------------------------------------------------------------------------
-- THE DIRECTOR'S MENU on a row
----------------------------------------------------------------------------

--The Director's right-click menu on a row.
text("history.menu.reveal", [[Reveal to players]])
text("history.menu.hide", [[Hide from players]])
text("history.menu.delete", [[Delete entry]])
text("history.menu.clear", [[Clear History]])
--The dialog that asks before Clear History.
text("history.menu.clear_confirm.title", [[Clear History?]])
text("history.menu.clear_confirm.body", [[This removes every entry on this map for everyone. It can't be undone.]])
text("history.menu.clear_confirm.confirm", [[Clear History]])
text("history.menu.clear_confirm.cancel", [[Cancel]])

----------------------------------------------------------------------------
-- SEARCH
----------------------------------------------------------------------------

--The search box, before anything is typed.
text("history.search.placeholder", [[Search creatures, abilities, conditions]])
--In place of the rows when nothing matches. {search} is the chips and words searched for.
text("history.search.nothing_matches", [[Nothing matches "{search}".]])
--The suggestion groups under the search box.
text("history.search.group.creatures", [[Creatures]])
text("history.search.group.abilities", [[Abilities]])
text("history.search.group.conditions", [[Conditions]])
text("history.search.group.other", [[Other]])
--The outcome words offered as search chips. Each finds rows by the word in code beside it.
text("history.search.other.killed", [[Killed]])
text("history.search.other.winded", [[Winded]])
text("history.search.other.triggered", [[Triggered]])
text("history.search.other.surges", [[Surges]])
text("history.search.other.malice", [[Malice]])
text("history.search.other.pushed", [[Pushed]])
text("history.search.other.fell", [[Fell]])
text("history.search.other.immunity", [[Immunity]])
text("history.search.other.resisted", [[Resisted]])
text("history.search.other.critical", [[Critical]])
--A chip for every creature of one type: "All Undead".
text("history.search.all_of_type", [[All {type}]])
--The x on a chip, and the x that clears every chip, on hover.
text("history.search.remove_chip", [[Remove {name}]])
text("history.search.clear", [[Clear the search]])
--How many rows match.
text("history.search.matches.one", [[1 match]])
text("history.search.matches.other", [[{count} matches]])
--The faces of your Heroes beside the search box, on hover.
text("history.search.hero.show_everything", [[Show everything]])
text("history.search.hero.show_only", [[Show only {name}]])

----------------------------------------------------------------------------
-- THE DETAIL CARD: its frame and headings
----------------------------------------------------------------------------

--The line under the card's title: "Main action - Round 2, turn 13".
text("history.card.round_turn", [[Round {round}, turn {turn}]])
--The card's footer, before the time.
text("history.card.rolled_by", [[Rolled by {player}]])
--The Back button at the top of the card, in the tray. An arrow is drawn before it.
text("history.card.back", [[Back]])
--The card's title. "Gordon - Dice" for a Dice panel roll; "A Hero - Argument" in a negotiation.
text("history.card.title.encounter_ended", [[Encounter ended]])
text("history.card.title.dice", [[Dice]])
text("history.card.title.argument", [[Argument]])
--The card's close button, on hover.
text("history.card.close_tooltip", [[Close the detail]])
--Over a moved creature's side-view button, when the engine can't draw the move side-on.
text("history.card.side_view", [[Side view]])
--The card's three section headings. The rule after each starts at a fixed place, so a
--much longer heading would run into it.
text("history.card.section.what_happened", [[What happened]])
text("history.card.section.why", [[Why]])
text("history.card.section.the_numbers", [[The numbers]])

----------------------------------------------------------------------------
-- THE DETAIL CARD: What happened
----------------------------------------------------------------------------

--How long a condition lasts, after its name. Each starts with a space.
text("history.story.duration.save_ends", [[ (save ends)]])
text("history.story.duration.eot", [[ until the end of its turn]])
--A distance in squares.
text("history.story.squares.one", [[{count} square]])
text("history.story.squares.other", [[{count} squares]])
--Damage taken. {type} is a damage type ("fire"); {parts} lists each type ("4 fire and 4 cold").
text("history.story.took_typed_damage", [[took {amount} {type} damage]])
text("history.story.took_damage", [[took {amount} damage]])
text("history.story.took_damage_parts", [[took {amount} damage: {parts}]])
text("history.story.damage_part", [[{amount} {type}]])
text("history.story.damage_part_untyped", [[{amount} untyped]])
--Forced movement. {kind} is push, pull or slide; {verb} is "pushed", "pulled", ...
text("history.story.moved.immune", [[is immune to forced movement]])
text("history.story.moved.held_ground", [[held its ground: stability {stability} stopped the {kind}]])
text("history.story.moved.blocked", [[was blocked and didn't move]])
--{words} is the line before it.
text("history.story.moved.with_stability", [[{words} (stability {stability})]])
text("history.story.moved.fell", [[fell {squares}]])
text("history.story.moved.distance", [[{verb} {squares}]])
text("history.story.moved.distance_of", [[{verb} {distance} of {requested} squares (stability {stability})]])
text("history.story.moved.breaking", [[{words}, breaking through {walls}]])
text("history.story.moved.walls.one", [[a wall]])
text("history.story.moved.walls.other", [[{count} walls]])
text("history.story.moved.then_fell", [[{words}, it fell {squares}]])
text("history.story.moved.was", [[was {words}]])
--What happened to one creature, read after its name. {words} is the line so far.
text("history.story.from_minions", [[{words} from {minions}]])
text("history.story.minions.one", [[{count} minion]])
text("history.story.minions.other", [[{count} minions]])
text("history.story.soaked", [[{words}, {soaked} of it to temporary Stamina]])
text("history.story.caught_in_area", [[was caught in the area and {words}]])
text("history.story.regained", [[regained {amount} Stamina]])
--Damage, then the push that came with it.
text("history.story.damage_then_moved", [[{damage}: {moved}]])
text("history.story.landed_on", [[was landed on]])
--{state} is winded or dying.
text("history.story.now_state", [[now {state}]])
text("history.story.renewed", [[{name} was renewed]])
--An effect that is not a condition. {duration} is one of the duration lines above, or nothing.
text("history.story.gained_effect", [[gained {name}{duration}]])
text("history.story.is", [[is {conditions}]])
text("history.story.killed", [[was killed]])
text("history.story.resisted_being", [[resisted being {conditions}]])
text("history.story.resisted_effect", [[resisted {effect}]])
text("history.story.resisted", [[resisted]])
text("history.story.effect_ended", [[{name} ended]])
text("history.story.no_longer", [[is no longer {states}]])
text("history.story.temporary_stamina", [[temporary Stamina went from {before} to {after}]])
--How the pieces above join into the words after a name. Keep the leading space or
--"'s": the card joins creatures that share words only when they start with a space.
text("history.story.predicate.notes_only", [['s {notes}.]])
text("history.story.predicate.verbs", [[ {verbs}.]])
text("history.story.predicate.then_it", [[{words} It {verbs}.]])
text("history.story.predicate.then_notes", [[{words} {notes}.]])
text("history.story.predicate.immune", [[ was not {conditions}.]])
text("history.story.predicate.then_immune", [[{words} It was not {conditions}.]])
text("history.story.predicate.ally", [[, an ally,{words}]])
--Several creatures that shared the same words: "Goblin 1-4 each took 5 damage."
text("history.story.each", [[{names} each{words}]])
--A minion squad.
text("history.story.squad_destroyed", [[the squad is destroyed]])
text("history.story.minions_killed", [[{killed} of {total} minions killed]])
--{words} is the damage it took ("took 12 damage"); {deaths} is one of the two lines above.
text("history.story.squad.took", [[{name} {words}]])
text("history.story.squad.then_deaths", [[{words}. {deaths}]])
text("history.story.squad.deaths", [[{words}: {deaths}]])
text("history.story.squad.end", [[{words}.]])
text("history.story.squad.only_deaths", [[{name} {deaths}.]])
--What happened to every member besides: {shared} starts with a space.
text("history.story.squad.then_shared", [[{words} The squad{shared}]])
text("history.story.squad.shared", [[The squad{shared}]])
--A resource a trigger or action changed. {resource} is "3 surges", "2 Focus", ...
text("history.story.resource", [[{name} {verb} {resource}.]])
text("history.story.resource.gained", [[gained]])
text("history.story.resource.spent", [[spent]])
--A trigger that hit a target of the action. {ability} is "Ana's Riposte".
text("history.story.trigger_hit_typed", [[{ability} then hit {name} for {amount} {type} damage.]])
text("history.story.trigger_hit", [[{ability} then hit {name} for {amount} damage.]])
--{words} is what happened to {name}, as above.
text("history.story.trigger_did", [[{ability}: {name}{words}]])
--What a Hero said in a negotiation.
text("history.story.argument_said", [["{text}"]])
--At the end of an encounter: what ended on each creature. {names} lists them.
text("history.story.encounter_ended", [[{name} {names}]])
--An opposed power roll.
text("history.story.opposed.tie_totals", [[{user} and {target} both rolled {total}. A tie changes nothing.]])
text("history.story.opposed.tie", [[{user} and {target} tied. A tie changes nothing.]])
text("history.story.opposed.succeeded", [[succeeded]])
text("history.story.opposed.failed", [[failed]])
text("history.story.opposed.result_totals", [[{user} rolled {total} against {target}'s {against} and {outcome}.]])
text("history.story.opposed.result", [[{user} {outcome} against {target}.]])
--When nothing else happened.
text("history.story.used", [[{name} used {ability}.]])

----------------------------------------------------------------------------
-- THE DETAIL CARD: The numbers
----------------------------------------------------------------------------

--How edges and banes net out on a roll, and what that does.
text("history.numbers.edge", [[Edge]])
text("history.numbers.double_edge", [[Double edge]])
text("history.numbers.bane", [[Bane]])
text("history.numbers.double_bane", [[Double bane]])
text("history.numbers.cancelled_out", [[Cancelled out]])
--What a double edge or double bane does, in the number column.
text("history.numbers.plus_tier", [[+1 tier]])
text("history.numbers.minus_tier", [[-1 tier]])
--The rules note under the edges and banes.
text("history.numbers.note.two_edges_one_bane", [[A maximum of two edges count (a double edge); with one bane, the roll is made with one edge.]])
text("history.numbers.note.two_banes_one_edge", [[A maximum of two banes count (a double bane); with one edge, the roll is made with one bane.]])
text("history.numbers.note.cancel_out", [[Edges and banes cancel out: the roll is made without either.]])
text("history.numbers.note.max_edges", [[A maximum of two edges count (a double edge).]])
text("history.numbers.note.max_banes", [[A maximum of two banes count (a double bane).]])
--How many there were, in brackets after the label: "(3 edges, 1 bane)".
text("history.numbers.edges.one", [[{count} edge]])
text("history.numbers.edges.other", [[{count} edges]])
text("history.numbers.banes.one", [[{count} bane]])
text("history.numbers.banes.other", [[{count} banes]])
--What a tier modifier did. {sign} is + or -.
text("history.numbers.tiers.one", [[{sign}{count} tier]])
text("history.numbers.tiers.other", [[{sign}{count} tiers]])
text("history.numbers.not_tier", [[not Tier {tier}]])
--What took edges or banes away. {source} is the modifier's name. The first letter of
--the list is made a capital.
text("history.numbers.ignored_by", [[ignored by {source}]])
text("history.numbers.removed_by", [[removed by {source}]])
--The same, on a line of its own under the modifier.
text("history.numbers.ignored_by_line", [[Ignored by {source}]])
text("history.numbers.removed_by_line", [[Removed by {source}]])
--{label} is Edge, Double bane, ...
text("history.numbers.for_this_target", [[{label} for this target]])
--Damage immunity and weakness. {type} is the damage type, capitalised, or the word below.
text("history.numbers.damage_word", [[Damage]])
text("history.numbers.immunity", [[{type} immunity {amount}]])
text("history.numbers.weakness", [[{type} weakness {amount}]])
--A kit's damage bonus.
text("history.numbers.kit", [[{name} kit]])
--Surges spent on damage, and the characteristic each adds.
text("history.numbers.surge_characteristic", [[({characteristic} {amount})]])
text("history.numbers.surge_characteristic_each", [[({characteristic} {amount} each)]])
text("history.numbers.spent_surges.one", [[Spent 1 surge]])
text("history.numbers.spent_surges.other", [[Spent {count} surges]])
--A target's own roll against the ability (an opposed or resisted roll).
text("history.numbers.their_roll", [[Their roll]])
--What one damage type dealt: "Tier 3: fire". {source} is the tier or the ability.
text("history.numbers.dealt_type", [[{source}: {type}]])
--Damage a fall dealt, and damage from a falling creature landing on this one.
text("history.numbers.fall", [[Fall]])
text("history.numbers.landed_on", [[Landed on]])
--The damage total; "each" when several creatures share the sum.
text("history.numbers.taken", [[Taken]])
text("history.numbers.taken_each", [[Taken, each]])
text("history.numbers.regained", [[Regained]])
--A push or pull that stability changed.
text("history.numbers.stability_ignored", [[Stability ignored]])
text("history.numbers.stability", [[Stability]])
text("history.numbers.moved", [[Moved]])
--Beside the Director's eye on a hidden roll, and what players see in its place.
text("history.numbers.rolled_in_secret_note", [[Rolled in secret.]])
--A side of an opposed roll players may not see.
text("history.numbers.rolled_in_secret", [[Rolled in secret]])
--Someone chose the tier after the dice landed. {name} is who.
text("history.numbers.overridden", [[{name} overrode the result: Tier {tier}. The dice gave Tier {dicetier}.]])
text("history.numbers.bonus", [[Bonus]])
text("history.numbers.total", [[Total]])
--The headings inside The numbers.
text("history.numbers.result", [[Result]])
text("history.numbers.power_roll", [[Power roll]])
text("history.numbers.dice", [[Dice]])
text("history.numbers.triggered", [[Triggered]])
--An opposed roll with no name, after its roller's name.
text("history.numbers.roll", [[Roll]])
--What an action spent: "Cost: 3 Focus".
text("history.numbers.cost", [[Cost: {cost}]])

----------------------------------------------------------------------------
-- THE DETAIL CARD: Why
----------------------------------------------------------------------------

--"cannot be knocked prone": a condition whose name doesn't read after "cannot be".
text("history.why.condition_phrase.prone", [[knocked prone]])
--How many surges came from one place, starting a sentence ("Two were gained from ...").
text("history.why.surge_number.1", [[One]])
text("history.why.surge_number.2", [[Two]])
text("history.why.surge_number.3", [[Three]])
text("history.why.surge_number.4", [[Four]])
text("history.why.surge_number.5", [[Five]])
--How many minions died, in words ("killed two").
text("history.why.minion_number.1", [[one]])
text("history.why.minion_number.2", [[two]])
text("history.why.minion_number.3", [[three]])
text("history.why.minion_number.4", [[four]])
text("history.why.minion_number.5", [[five]])
text("history.why.minion_number.6", [[six]])
text("history.why.minion_number.7", [[seven]])
text("history.why.minion_number.8", [[eight]])
text("history.why.minion_number.9", [[nine]])
text("history.why.minion_number.10", [[ten]])
--What edges and banes did to a roll's tier. {names} lists the modifiers, in [brackets].
text("history.why.an_edge", [[an edge]])
text("history.why.a_bane", [[a bane]])
text("history.why.a_double_edge", [[a double edge]])
text("history.why.a_double_bane", [[a double bane]])
text("history.why.gave", [[{names} gave {what}]])
--{what} is one of the four above, or the word below when a modifier gave the other.
text("history.why.set_by_hand", [[{what} was set by hand]])
text("history.why.another", [[another]])
--What took edges or banes away: "[Twisted] ignored it". {verb} is one of the two below.
text("history.why.removed", [[{names} {verb} {what}]])
text("history.why.removed.verb_ignored", [[ignored]])
text("history.why.removed.verb_removed", [[removed]])
--{what}, when the edges or banes were named earlier in the line.
text("history.why.removed.it", [[it]])
text("history.why.removed.one", [[one]])
text("history.why.removed.two", [[two]])
--{what}, on a target's line, for what the roll's own line had.
text("history.why.the_edge", [[the edge]])
text("history.why.the_double_edge", [[the double edge]])
text("history.why.the_bane", [[the bane]])
text("history.why.the_double_bane", [[the double bane]])
text("history.why.one_edge", [[one edge]])
text("history.why.two_edges", [[two edges]])
text("history.why.one_bane", [[one bane]])
text("history.why.two_banes", [[two banes]])
--What a tier modifier did: "[Mark] raised it a tier". {did} is one of the lines below.
text("history.why.tier", [[{source} {did}]])
text("history.why.tier.kept_off_1", [[kept it off Tier 1]])
text("history.why.tier.made_3", [[made it Tier 3]])
text("history.why.tier.made_1", [[made it Tier 1]])
text("history.why.tier.kept_from_3", [[kept it from Tier 3]])
text("history.why.tier.raised", [[raised it {tiers}]])
text("history.why.tier.lowered", [[lowered it {tiers}]])
text("history.why.tier.tiers.one", [[a tier]])
text("history.why.tier.tiers.other", [[{count} tiers]])
--A flat bonus on the roll.
text("history.why.bonus_added", [[{source} added {amount} to the roll]])
text("history.why.bonus_took", [[{source} took {amount} off the roll]])
text("history.why.natural", [[a natural 19 or 20 is always Tier 3]])
--Joins clauses that hold "and" of their own: "a, b, and c". {most} is all but the last, joined by commas.
text("history.why.join_clauses", [[{most}, and {last}]])
--After a tier line's lead ("Tier 3, up from Tier 2"). Keep the leading comma.
text("history.why.qualifier.up_from_tier", [[, up from Tier {tier}]])
text("history.why.qualifier.down_from_tier", [[, down from Tier {tier}]])
text("history.why.qualifier.not_tier", [[, not Tier {tier}]])
--The same after a damage line's lead ("19 damage, up from 15").
text("history.why.qualifier.up_from", [[, up from {amount}]])
text("history.why.qualifier.down_from", [[, down from {amount}]])
--What pushed one way, then what pushed back: "[Prone] gave an edge, but [Twisted] ignored it".
text("history.why.but", [[{words}, but {but}]])
--The full stop that ends a Why sentence.
text("history.why.sentence_end", [[{words}.]])
--Where surges came from. {subject} is one of the lines below; {tail} is the free-surge
--line below, or nothing.
text("history.why.surges.gained_from", [[{subject} gained from {source}{tail}.]])
text("history.why.surges.a_modifier", [[a modifier]])
text("history.why.surges.it_was", [[It was]])
text("history.why.surges.they_were", [[They were]])
--{number} is One, Two, ... from the list above.
text("history.why.surges.number_was", [[{number} was]])
text("history.why.surges.number_were", [[{number} were]])
--Keep the leading space.
text("history.why.surges.free_tail", [[ and could only be spent on this strike]])
--What changed a target's damage. {type} is a space and the damage type (" fire"), or nothing.
text("history.why.damage.added", [[{name} added {amount}{type}]])
text("history.why.damage.took_off", [[{name} took {amount} off]])
text("history.why.damage.surge_added", [[1 surge added {amount}{type}]])
text("history.why.damage.surges_added", [[{count} surges added {amount}{type} each]])
--{words} is one of the two lines above; {name} is whose characteristic it was.
text("history.why.damage.surge_characteristic", [[{words} ({name}'s highest characteristic, {characteristic} {amount})]])
--The bold lead of a damage line. {qualifier} is one of the "up from" lines above, or nothing.
text("history.why.lead.damage", [[{amount} damage{qualifier}]])
text("history.why.lead.extra_damage", [[{amount} extra damage]])
text("history.why.lead.damage_to", [[{amount} damage to {names}{qualifier}]])
--A free strike for moving away. {striker} made the strike.
text("history.why.lead.moved_away", [[Moved away without shifting]])
text("history.why.moved_away", [[{name} moved away from {striker}, who made a free strike against it.]])
--A triggered action's own Trigger line, as its card writes it.
text("history.why.trigger_text", [[Trigger: {text}]])
--The tier lines. {qualifier} is one of the "up from Tier" lines above, or nothing.
text("history.why.lead.tier", [[Tier {tier}{qualifier}]])
text("history.why.lead.tier_against", [[Tier {tier} against {names}{qualifier}]])
--An area ability that hit someone on its user's side.
text("history.why.lead.area", [[Area ability]])
text("history.why.area", [[It hits every creature in the area, allies included.]])
--A condition a target's immunity stopped. The first two name the feature that made it immune.
text("history.why.immune_from.one", [[{names} is immune to {condition}.]])
text("history.why.immune_from.other", [[{names} are immune to {condition}.]])
text("history.why.lead.immune_to", [[Immune to {condition}]])
text("history.why.cannot_be", [[{names} cannot be {condition}.]])
--A fall that added to a forced move.
text("history.why.fall", [[The fall dealt {amount} damage, for {total} instead of {without}.]])
--A fall that was all of a target's damage.
text("history.why.fall_only", [[The fall dealt {amount} damage.]])
--When the side view can be shown.
text("history.why.fall_side_view", [[{words} Hover here for the side view.]])
text("history.why.lead.fell.one", [[Fell {count} square]])
text("history.why.lead.fell.other", [[Fell {count} squares]])
--A collision. {squares} is "2 squares"; {kind} is push, pull or slide.
text("history.why.lead.hit_object", [[Hit an object]])
text("history.why.hit_object", [[{name} had {squares} of the {kind} left: {amount} damage, plus 2 for hitting an object.]])
--The same, when whoever pushed it adds damage for pushing into objects. {pusher} is their name.
text("history.why.hit_object_bonus", [[{name} had {squares} of the {kind} left: {amount} damage, plus 2 for hitting an object and {bonus} from {pusher}'s bonus for pushing into objects.]])
text("history.why.lead.hit_creature", [[Hit {other}]])
text("history.why.hit_creature", [[{name} had {squares} of the {kind} left, so it and {other} each took {amount} damage.]])
--Added after either collision line when the creature's forced movement damage reduction took some off.
text("history.why.collision_reduced", [[Its forced movement damage reduction took off {amount}.]])
--How many minions the damage killed. {count} and {number} are the minion numbers above ("two").
text("history.why.lead.minions", [[Minions]])
text("history.why.minions_known", [[Each minion in this squad has {stamina} Stamina, so {amount} damage killed {count}.]])
text("history.why.minions_unknown.one", [[{amount} damage was enough to kill {number} minion.]])
text("history.why.minions_unknown.other", [[{amount} damage was enough to kill {number} minions.]])
--Potency tests. {potency} is written as the stat block does ("M<2"); {what} is the
--condition ("being slowed") or effect it gated.
text("history.why.potency.being", [[being {condition}]])
text("history.why.lead.potency", [[Potency]])
text("history.why.potency.hidden_resisted", [[{names} resisted.]])
text("history.why.potency.hidden_not_resisted", [[{names} did not resist.]])
text("history.why.potency.raised_resisted", [[{from} became {potency}, but {names} resisted.]])
text("history.why.potency.raised_not_resisted_what", [[{from} became {potency}, so {names} could not resist {what}.]])
text("history.why.potency.raised_not_resisted", [[{from} became {potency}, so {names} could not resist.]])
text("history.why.lead.potency_raised.one", [[Potency raised with {count} surge]])
text("history.why.lead.potency_raised.other", [[Potency raised with {count} surges]])
text("history.why.potency.resisted", [[{potency}: {names} resisted.]])
text("history.why.potency.not_resisted_what", [[{potency}: {names} could not resist {what}.]])
text("history.why.potency.not_resisted", [[{potency}: {names} could not resist.]])
--A trigger whose name is really its rule text is called this instead.
text("history.why.trigger_word_lead", [[Trigger]])
text("history.why.trigger_word", [[trigger]])
text("history.why.triggered_by", [[Triggered by this action: {effect}]])
--When nothing changed the result.
text("history.why.nothing_changed", [[Nothing changed the roll or the damage.]])

----------------------------------------------------------------------------
-- THE HISTORY BUTTON: the Sidebar Preview and the Since you last looked card
----------------------------------------------------------------------------

--The Sidebar Preview bubble beside the History button: past two lines it says how many more.
text("history.bubble.and_more", [[and {count} more]])
--The History button's hover card, with what happened since you last opened History.
text("history.since.title", [[Since you last looked]])
text("history.since.more_turns.one", [[and 1 more turn]])
text("history.since.more_turns.other", [[and {count} more turns]])
text("history.since.click_to_open", [[Click to open]])

----------------------------------------------------------------------------
-- THE SMALL TEXT UNDER A LINE, written as it happens (HistoryCapture.lua)
----------------------------------------------------------------------------

--Under a damage line at the start of a turn. {cause} is what dealt it.
text("history.cause.start_of_turn", [[Start of turn: {cause}]])
--Under a respite's line: what it restored, "Stamina 12 to 30 - Recoveries 2 to 8".
text("history.cause.respite.stamina", [[Stamina]])
text("history.cause.respite.recoveries", [[Recoveries]])
text("history.cause.respite.xp", [[XP]])
text("history.cause.respite", [[Respite]])
--A number that changed: "Interest 2 to 3". {label} is one of the words above or below.
text("history.cause.change", [[{label} {before} to {after}]])
--Under a heal that spent a Recovery.
text("history.cause.used_recovery", [[Used a Recovery]])
--Downtime projects.
text("history.cause.downtime.milestone", [[The Director rolls a project event]])
--After the Hero's name and a dot.
text("history.cause.downtime.points", [[project points {points} of {goal}]])
--A negotiation. Players see the bands ({before}, {after} are band names) where the
--Director sees numbers.
text("history.cause.negotiation.interest", [[Interest]])
text("history.cause.negotiation.patience", [[Patience]])
text("history.cause.negotiation.band", [[{before} to {after}]])
text("history.cause.negotiation.interest_now", [[Interest {interest}]])
text("history.cause.negotiation.patience_now", [[Patience {patience}]])
text("history.cause.negotiation.argument", [[Argument]])
text("history.cause.negotiation.read", [[Read {npc}]])
text("history.cause.negotiation.learned_something", [[Learned something]])
text("history.cause.negotiation.learned_nothing", [[Learned nothing]])
text("history.cause.negotiation.pitfall", [[Pitfall]])
text("history.cause.negotiation.motivation", [[Motivation]])
text("history.cause.negotiation.final_offer", [[Final offer: {offer}]])
text("history.cause.negotiation.no_deal", [[No deal]])
--Montages. {test} and {option} are the test and the option the Hero chose.
text("history.cause.montage.test", [[{test}: {option}]])
text("history.cause.montage.successes.one", [[{count} success]])
text("history.cause.montage.successes.other", [[{count} successes]])
text("history.cause.montage.failures.one", [[{count} failure]])
text("history.cause.montage.failures.other", [[{count} failures]])
text("history.cause.montage.unvanquished.one", [[{count} threat not vanquished]])
text("history.cause.montage.unvanquished.other", [[{count} threats not vanquished]])
text("history.cause.montage", [[Montage]])
--Why effects ended.
text("history.cause.end_of_turn", [[End of turn]])
text("history.cause.end_of_round", [[End of round]])
text("history.cause.is_dying", [[{name} is dying]])
text("history.cause.respite_began", [[Respite began]])
--Under a saving throw's line. The first letter is made a capital when it stands alone.
text("history.cause.save_rolled", [[rolled {total} ({target} or more ends it)]])
text("history.cause.end_of_turn_save", [[End of turn: {rolled}]])
--Under a Turn reverted line.
text("history.cause.reverted_by_director", [[By the Director]])
text("history.cause.reverted_by", [[By {name}]])
--Why a persistent ability stopped.
text("history.cause.persistence.chose", [[Chose to stop]])
text("history.cause.persistence.targets_gone", [[All its targets are dead]])
text("history.cause.persistence.damage", [[Took {damage} damage in one turn, 5 times Reason {reason}]])
