local mod = dmhub.GetModLoading()

--Encounter of the Week: the words encounter authors see -- the Montage Builder, the Encounter Builder, the authoring test and the script checker's warnings.
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

local text = UIText.Define("EncounterAuthoringText")

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: a map with no script yet (Game > Encounter Builder)
----------------------------------------------------------------------------

text("author.encounter_builder.new_script.heading", [[This map has no Encounter of the Week script yet.]])
text("author.encounter_builder.new_script.help", [[Create one to start building: a journal document filed under this map with a narrative, a montage and the encounter to begin from. You can change or delete any of it.]])
--Buttons. Short.
text("author.encounter_builder.new_script.create", [[Create the script]])
text("author.encounter_builder.new_script.cancel", [[Cancel]])
--The status line once it is made. {document} is the new document's name.
text("author.encounter_builder.new_script.created", [[Created the script document '{document}' under this map.]])

----------------------------------------------------------------------------
-- THE BUILDER WINDOW: its title bar and footer (shared by the Encounter
-- Builder and the Montage Builder)
----------------------------------------------------------------------------

--The window's title. {name} is the script document's name.
text("author.encounter_builder.window.title", [[Encounter Builder: {name}]])
text("author.montage_builder.window.title", [[Montage Builder: {name}]])
--Shown for a moment while the window opens.
text("author.montage_builder.window.title_initial", [[Montage Builder]])
--A script document with no name.
text("author.montage_builder.load.script_fallback_name", [[Script]])
--The dropdown of montages, when the script has more than one. {number} is
--the montage's number, {beat} its place among all the beats.
text("author.montage_builder.window.montage_option", [[Montage {number} (beat {beat})]])
--The title bar's buttons. Short: buttons.
text("author.montage_builder.window.back_to_script", [[Back to the script]])
text("author.montage_builder.window.test_montage", [[Test this montage]])
text("author.montage_builder.window.undo", [[Undo]])
text("author.montage_builder.window.validator", [[Validator]])
text("author.montage_builder.window.close", [[Close]])
--A button that deletes something reads this after the first click.
text("author.montage_builder.confirm_again", [[Click again to confirm]])

--A series: one script document per part, filed under this map. The dropdown
--of its parts. {number} is a part's number, {title} its title.
text("author.encounter_builder.part.option", [[Part {number}]])
text("author.encounter_builder.part.option_titled", [[Part {number}: {title}]])
--The button that adds the next part. Short: a button.
text("author.encounter_builder.part.add", [[+ Part]])
--Its tooltip. {number} is the new part's number.
text("author.encounter_builder.part.add_tooltip", [[Add Part {number}: a new script document filed under this map, unlocked by winning the part before it.]])
--Its tooltip when the map is not a series yet.
text("author.encounter_builder.part.add_tooltip_first", [[Make this encounter a series: this script becomes Part 1, and a new script document filed under this map becomes Part 2, unlocked by winning Part 1.]])
--The new part's document name. {number} is its part number.
text("author.encounter_builder.part.document_name", [[Encounter Script (Part {number})]])
--The status lines. {number} is the part, {document} the new document's name.
text("author.encounter_builder.part.made_part_one", [[Made this script Part 1 of a series.]])
text("author.encounter_builder.part.created", [[Added Part {number}: the script document '{document}' under this map.]])

--The footer, after the status line: how many problems the script has.
--{count} is that number.
text("author.montage_builder.footer.no_problems", [[No problems in the script.]])
text("author.montage_builder.footer.problems.one", [[{count} problem in the whole script (open the validator for all of them).]])
text("author.montage_builder.footer.problems.other", [[{count} problems in the whole script (open the validator for all of them).]])

--When part of the window fails to draw. {error} is the technical error.
text("author.montage_builder.window.board_failed", [[Board failed: {error}]])
text("author.montage_builder.window.editor_failed", [[Editor failed: {error}]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: the board on the left (rounds and their cards)
----------------------------------------------------------------------------

text("author.montage_builder.board.no_montage", [[This script has no '# Montage' beat yet.]])
text("author.montage_builder.board.intro_label", [[Intro (shown in the header for the whole montage)]])
--Grey example text in the empty intro box.
text("author.montage_builder.board.intro_placeholder", [[The party's standing context.]])
--A round's heading. {number} is the round number.
text("author.montage_builder.board.round", [[Round {number}]])
text("author.montage_builder.board.round_implicit", [[Round 1 (no round heading)]])
text("author.montage_builder.board.party_size_help", [[At that party size the round drops that many cards, drawn at random from the ones it introduces (never a Required one).]])
--Under each round. {opportunities} and {threats} are counts.
text("author.montage_builder.board.round_counts", [[{opportunities} opportunities, {threats} threats introduced. A round needs about 6 for a full party; trim for 4 and 5 heroes.]])
--Buttons. Short.
text("author.montage_builder.board.add_party_size", [[+ Party-size line]])
text("author.montage_builder.board.add_opportunity", [[+ Opportunity]])
text("author.montage_builder.board.add_threat", [[+ Threat]])
text("author.montage_builder.board.add_round", [[+ Round]])
text("author.montage_builder.board.add_obstacle", [[+ Obstacle]])

--A delve's card under the rounds. {name} is the delve's name.
text("author.montage_builder.board.delve_heading", [[DELVE: {name}]])
--The line under it. {obstacles} is the count below; {low} and {high} are
--how many obstacles come between chests.
text("author.montage_builder.board.delve_summary_sequence", [[In sequence; {obstacles}. Click for its settings.]])
text("author.montage_builder.board.delve_summary_random", [[Random obstacles; {obstacles}, a chest every {low}-{high}. Click for its settings.]])
text("author.montage_builder.board.delve_obstacles.one", [[{count} obstacle]])
text("author.montage_builder.board.delve_obstacles.other", [[{count} obstacles]])

--An opportunity, threat, obstacle or delve scene on the board. The kind is
--shown in capitals. The kind names are also the heading of its editor.
text("author.montage_builder.kind.opportunity", [[Opportunity]])
text("author.montage_builder.kind.threat", [[Threat]])
text("author.montage_builder.kind.obstacle", [[Obstacle]])
text("author.montage_builder.card.kind_delve_scene", [[DELVE SCENE]])
--The card's summary line: these parts joined by dashes, then its tags.
--{count} is a number.
text("author.montage_builder.card.options.one", [[{count} option]])
text("author.montage_builder.card.options.other", [[{count} options]])
text("author.montage_builder.card.scene_lines.one", [[{count} scene line]])
text("author.montage_builder.card.scene_lines.other", [[{count} scene lines]])
text("author.montage_builder.card.treasure_table", [[treasure table]])
text("author.montage_builder.card.secrets", [[{count} secret]])
text("author.montage_builder.card.scene", [[scene]])
text("author.montage_builder.card.tag_required", [[Required]])
text("author.montage_builder.card.tag_locked", [[Locked]])
text("author.montage_builder.card.tag_temporary", [[Temporary]])
--Under a card with problems.
text("author.montage_builder.card.problems.one", [[{count} problem]])
text("author.montage_builder.card.problems.other", [[{count} problems]])

--A party-size line as a form: "Between 4 and 5 players: -1 Opportunity;
---1 Threat". Short words: they sit between dropdowns.
text("author.montage_builder.party_size.between", [[Between]])
text("author.montage_builder.party_size.and", [[and]])
--The last choice of the second number.
text("author.montage_builder.party_size.or_more", [[or more]])
text("author.montage_builder.party_size.players", [[players:]])
text("author.montage_builder.party_size.opportunity", [[Opportunity;]])
text("author.montage_builder.party_size.threat", [[Threat]])
text("author.montage_builder.party_size.remove", [[Remove]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: the editor on the right, before anything is picked
----------------------------------------------------------------------------

text("author.montage_builder.window.empty_heading", [[Pick an opportunity, threat or delve obstacle on the left to edit it.]])
text("author.montage_builder.window.empty_help", [[Every change is written straight into the journal document it came from, and the script is re-checked with the game's own parser. Undo takes back one change at a time.]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: the editor of an opportunity, threat or obstacle
----------------------------------------------------------------------------

--Under the heading. {document} is the journal document's name.
text("author.montage_builder.entry.source", [[In the journal document '{document}'.]])
--The kind dropdown. Short.
text("author.montage_builder.entry.kind_opportunity", [[Opportunity]])
text("author.montage_builder.entry.kind_threat", [[Threat]])
--The tag tick boxes, and their tooltips. Short.
text("author.montage_builder.entry.required", [[Required]])
text("author.montage_builder.entry.locked", [[Locked]])
text("author.montage_builder.entry.temporary", [[Temporary]])
text("author.montage_builder.entry.required_tooltip", [[Never removed by the party-size trim.]])
text("author.montage_builder.entry.locked_tooltip", [[Off the board until an 'unlock <name>' outcome lands.]])
text("author.montage_builder.entry.temporary_tooltip", [[Gone at the end of the round it appears in.]])
--The card text, approach text and consequence, with the grey example text
--of their boxes. 'Options:' is a script line and must stay as it is.
text("author.montage_builder.entry.card_text_label", [[Card text: what the party reads on the board]])
text("author.montage_builder.entry.card_text_placeholder", [[A cottage sits off the path, smoke curling from its chimney.]])
text("author.montage_builder.entry.approach_label", [[Approach text (optional 'Options:' line, shown when the hero steps up)]])
text("author.montage_builder.entry.approach_placeholder", [[Approaching the cottage, you see a witch within...]])
text("author.montage_builder.entry.consequence_label", [[Consequence: what happens at the end if the threat is never vanquished]])
text("author.montage_builder.entry.consequence_placeholder", [[What the party suffers at the end of the montage (optional words)]])
--The entry's scene.
text("author.montage_builder.entry.scene", [[Scene: plays when a hero approaches]])
text("author.montage_builder.entry.add_scene", [[+ Add a scene]])
text("author.montage_builder.entry.scene_help", [[A scene plays the approach as dialogue with portraits. With one, each option's own lines become its scenes too.]])
--Dice tables. 'roll on <table name>' is script wording and must stay.
text("author.montage_builder.entry.add_dice_table", [[+ Dice table]])
text("author.montage_builder.entry.dice_table_help", [[An outcome rolls an entry's table with 'roll on <table name>' (or 'roll twice on ...').]])
--The options. {count} is how many.
text("author.montage_builder.entry.options_heading", [[Options ({count})]])
text("author.montage_builder.entry.add_option_test", [[+ Option with a test]])
text("author.montage_builder.entry.add_option_no_roll", [[+ Option with no roll]])
text("author.montage_builder.entry.add_option_delve", [[+ Option that enters a delve]])
--The entry's problems. {count} is how many; {list} is the unmatched
--clauses, separated by slashes.
text("author.montage_builder.entry.problems_heading", [[Problems ({count})]])
text("author.montage_builder.entry.text_only", [[Text only, no rule matched ({count}): usually flavour; check for a typo'd rule. {list}]])
--The entry's tools.
text("author.montage_builder.entry.text_editor_note", [[The entry as written in its document. Anything the forms do not cover can be edited here.]])
text("author.montage_builder.entry.edit_as_text", [[Edit entry as text]])
text("author.montage_builder.entry.open_in_journal", [[Open in journal]])
--The move dropdown: its first line, then one choice per other round.
--{number} is a round number.
text("author.montage_builder.entry.move_to_round", [[Move to round...]])
text("author.montage_builder.entry.move_round_option", [[Round {number}]])
text("author.montage_builder.entry.delete", [[Delete entry]])
text("author.montage_builder.entry.delete_obstacle", [[Delete obstacle]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: one option of an entry
----------------------------------------------------------------------------

--Beside the option's name: what kind of option it is. {delve} is a delve's
--name; {kind} is one of the kinds, for a secret option.
text("author.montage_builder.option.kind_delve", [[Enters the delve '{delve}' (edit it from the board)]])
text("author.montage_builder.option.kind_test", [[Test]])
text("author.montage_builder.option.kind_no_roll", [[No roll: its rules apply at once]])
text("author.montage_builder.option.kind_none", [[No rules yet]])
text("author.montage_builder.option.kind_secret", [[{kind}  (SECRET: only heroes who meet an Allow line see it)]])
--The option's scenes, or its plain text.
text("author.montage_builder.option.scene_before", [[Scene when chosen (before the roll)]])
text("author.montage_builder.option.scene_after", [[Outcome scene (after the roll; effects apply once it has been read)]])
text("author.montage_builder.option.text_label", [[What the option says (optional)]])
text("author.montage_builder.option.text_placeholder", [[Shown with the option.]])
--The option's tools. Short: buttons.
text("author.montage_builder.option.text_editor_note", [[The option as written. Anything the forms above do not cover can be edited here.]])
text("author.montage_builder.option.edit_as_text", [[Edit as text]])
text("author.montage_builder.option.add_knack_no_roll", [[+ Knack version (no roll)]])
text("author.montage_builder.option.add_knack_test", [[+ Knack version (own test)]])
text("author.montage_builder.option.delete", [[Delete option]])
--The Save button under an "as text" box.
text("author.montage_builder.text_editor.save", [[Save text]])

--An option's test.
text("author.montage_builder.rules.test_label", [[Test]])
text("author.montage_builder.rules.test_name", [[Name]])
text("author.montage_builder.rules.skills", [[Skills]])
--Tooltips of a skill chip: a known skill, and a name that is not a skill.
--{skill} is the name as written.
text("author.montage_builder.rules.remove_skill_tooltip", [[Remove this skill]])
text("author.montage_builder.rules.unknown_skill_tooltip", [['{skill}' is not a skill name: it adds nothing to the roll. Click to remove.]])
text("author.montage_builder.rules.add_skill", [[+ Add skill]])
--The tiers. The ranges for tiers 2 and 3 are plain numbers (12-16, 17+).
text("author.montage_builder.rules.outcomes_label", [[Outcomes: the teaser is what players see until that tier lands (optional)]])
text("author.montage_builder.rules.tier1_range", [[11 or lower]])
text("author.montage_builder.rules.critical_range", [[Critical (natural 19-20)]])
text("author.montage_builder.rules.teaser_placeholder", [[Teaser (optional)]])
text("author.montage_builder.rules.critical_label", [[Critical]])
text("author.montage_builder.rules.critical_automatic", [[Automatic: tier 3 plus an additional hero token]])
--An option with no roll.
text("author.montage_builder.rules.no_roll_label", [[What happens (no roll: it applies at once)]])
text("author.montage_builder.rules.remove_paragraph_tooltip", [[Remove this paragraph]])
text("author.montage_builder.rules.add_paragraph", [[+ Paragraph]])
--Knacks: edges, banes and secret options. The requirement examples are
--script wording and must stay.
text("author.montage_builder.rules.knacks_label", [[Knacks: edges, banes and secret (Allow) requirements]])
--The round dropdown of a knack. {number} is a round number.
text("author.montage_builder.rules.any_round", [[Any round]])
text("author.montage_builder.rules.round_option", [[Round {number}]])
text("author.montage_builder.rules.remove_knack", [[Remove]])
text("author.montage_builder.rules.add_edge", [[+ Edge]])
text("author.montage_builder.rules.add_bane", [[+ Bane]])
text("author.montage_builder.rules.add_secret", [[+ Secret (Allow)]])
text("author.montage_builder.rules.requirements_help", [[Requirements read as intent: 'you can teleport', 'you speak Zaliac', 'you are a Dwarf', 'you are skilled in Track', 'you have the Lucky Dog perk', 'your Wealth is 2 or higher'... (KNACKS_REFERENCE.md).]])
--Switching between a test and no roll. Short: buttons.
text("author.montage_builder.rules.make_no_roll", [[Make it no-roll]])
text("author.montage_builder.rules.make_test", [[Make it a test]])

--A knack version of an option ("#### If ..."). The heading is followed by
--a box with the requirement.
text("author.montage_builder.knack.heading", [[KNACK: If]])
text("author.montage_builder.knack.help", [[A hero who meets this takes this version of the option instead: no roll (the knack makes the problem moot) or a better test.]])
text("author.montage_builder.knack.scene_before", [[Before (after the option's own lines)]])
text("author.montage_builder.knack.scene_after", [[After the outcome (otherwise the option's own)]])
text("author.montage_builder.knack.delete", [[Delete knack version]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: an outcome (words, plus rewards and costs)
----------------------------------------------------------------------------

--Grey example text of an outcome's words.
text("author.montage_builder.outcome.text_placeholder", [[What happens, in the words the players read]])
--The dropdown that adds a reward or cost.
text("author.montage_builder.outcome.add", [[+ Add a reward or cost...]])
--Who a reward or cost is for.
text("author.montage_builder.outcome.target_self", [[the hero]])
text("author.montage_builder.outcome.target_party", [[every hero]])
--An edge or bane on another test.
text("author.montage_builder.outcome.test_edge", [[an edge]])
text("author.montage_builder.outcome.test_double_edge", [[a double edge]])
text("author.montage_builder.outcome.test_bane", [[a bane]])
text("author.montage_builder.outcome.test_double_bane", [[a double bane]])
--How the next combat starts.
text("author.montage_builder.outcome.initiative_win", [[The heroes win initiative]])
text("author.montage_builder.outcome.initiative_lose", [[The heroes lose initiative]])
text("author.montage_builder.outcome.initiative_surprise", [[The heroes surprise the enemy]])
text("author.montage_builder.outcome.initiative_surprised", [[The heroes begin surprised]])
--Tooltips of two pickers.
text("author.montage_builder.outcome.recoveries_tooltip", [[A number, or dice rolled for each hero.]])
text("author.montage_builder.outcome.stamina_tooltip", [[A number, or dice rolled for each hero.]])
text("author.montage_builder.outcome.entry_tooltip", [[The montage's (Locked) entries.]])
--Whether the players see a reward or cost.
text("author.montage_builder.outcome.shown", [[Shown]])
text("author.montage_builder.outcome.hidden", [[Hidden]])
text("author.montage_builder.outcome.hidden_tooltip", [[Hidden: it happens, but the players are never shown the words.]])
text("author.montage_builder.outcome.remove_tooltip", [[Remove this]])
text("author.montage_builder.outcome.no_locked_entry", [[This montage has no (Locked) entry to unlock: tick Locked on one.]])
text("author.montage_builder.outcome.no_dice_table", [[This entry has no dice table: add one with '+ Dice table'.]])
--A note under some kinds of reward or cost, saying what it does.
--'Unlock: Intelligence' is a script line and must stay as it is.
text("author.montage_builder.outcome.help_intelligence", [[Only does anything when a narrative beat unlocks Intelligence ('Unlock: Intelligence').]])
text("author.montage_builder.outcome.help_malice", [[Malice the Director gets for the encounter.]])
text("author.montage_builder.outcome.help_surges", [[Granted at the start of the next combat.]])
text("author.montage_builder.outcome.help_loserecovery", [[The Recovery is gone, with no Stamina back for it.]])
text("author.montage_builder.outcome.help_loseconsumable", [[A random consumable; a hero with none loses a Recovery instead.]])
text("author.montage_builder.outcome.help_unlock", [[A (Locked) entry joins the board. Usually hidden, so the players do not see it coming.]])
text("author.montage_builder.outcome.help_testmod", [[A standing edge or bane on another test of this montage, for whoever takes it.]])
text("author.montage_builder.outcome.help_rolltable", [[Rolls a dice table written in this entry.]])
text("author.montage_builder.outcome.help_revealobject", [[An object you left inactive on the map appears for the encounter.]])
text("author.montage_builder.outcome.help_startzone", [[The heroes may also start the encounter in that zone type.]])
text("author.montage_builder.outcome.help_revealzones", [[Those zones are shown to the players during the next combat.]])
text("author.montage_builder.outcome.help_knowstamina", [[The party learns the Stamina of every monster with that keyword, for good.]])

--A dice table: its heading, the grey text of a row's box, and the add
--button.
text("author.montage_builder.table.title", [[Dice table]])
text("author.montage_builder.table.row_placeholder", [[What this row gives]])
text("author.montage_builder.table.add_row", [[+ Row]])
text("author.montage_builder.table.mystery", [[Mystery: rows read ??? until the dice land on them]])
--Deletes the whole table (also on its right-click menu). Short: a button.
text("author.montage_builder.table.delete", [[Delete table]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: a scene (one line per step: narration, speech, an
-- entrance, a branch...)
----------------------------------------------------------------------------

--The small tag at the left of each step. Short.
text("author.montage_builder.scene.step_narration", [[NARRATION]])
text("author.montage_builder.scene.step_says", [[SAYS]])
text("author.montage_builder.scene.step_enters", [[ENTERS]])
text("author.montage_builder.scene.step_exits", [[EXITS]])
text("author.montage_builder.scene.step_emote", [[EMOTE]])
text("author.montage_builder.scene.step_if", [[IF]])
text("author.montage_builder.scene.step_else_if", [[ELSE IF]])
text("author.montage_builder.scene.step_else", [[ELSE]])
text("author.montage_builder.scene.step_end", [[END]])
--The kinds of step the "+" dropdowns add.
text("author.montage_builder.scene.type_narration", [[Narration]])
text("author.montage_builder.scene.type_pc_says", [[PC says]])
text("author.montage_builder.scene.type_character_says", [[Character says]])
text("author.montage_builder.scene.type_character_enters", [[Character enters]])
text("author.montage_builder.scene.type_character_exits", [[Character exits]])
text("author.montage_builder.scene.type_emote", [[Emote]])
text("author.montage_builder.scene.type_branch", [[Branch (if ... end)]])
--A dropdown choice whose current value is not in the list. {name} is the
--value.
text("author.montage_builder.not_found_option", [[{name} (not found)]])
--A narration step. PC is script wording and must stay.
text("author.montage_builder.scene.narration_placeholder", [[PC is replaced by the hero's name.]])
--A speech step: who speaks, their emote, their language and their words.
text("author.montage_builder.scene.who_pc", [[PC (the hero)]])
text("author.montage_builder.scene.speaker_unknown_voice", [[Unknown voice (???)]])
text("author.montage_builder.scene.speaker_named_voice", [[Named voice off stage]])
text("author.montage_builder.scene.speaker_tooltip", [[Who speaks. Only PC, characters who have entered, or a voice off stage (no portrait).]])
text("author.montage_builder.scene.voice_name_placeholder", [[Name]])
text("author.montage_builder.scene.no_emote", [[(no emote)]])
text("author.montage_builder.scene.emote_tooltip", [[An emote the speaker shows as the line appears.]])
text("author.montage_builder.scene.any_language", [[(any language)]])
text("author.montage_builder.scene.language_tooltip", [[Spoken in a language: heroes who do not speak it see the line garbled.]])
text("author.montage_builder.scene.line_placeholder", [[What they say]])
--An entrance: "<name> played by <monster>".
text("author.montage_builder.scene.character_name_placeholder", [[Name]])
text("author.montage_builder.scene.played_by", [[played by]])
text("author.montage_builder.scene.monster_tooltip", [[The bestiary monster whose portrait shows on stage.]])
text("author.montage_builder.scene.monster_not_found", [[not in the bestiary: no portrait]])
--An exit: "<name> leaves the stage".
text("author.montage_builder.scene.leaves_the_stage", [[leaves the stage]])
--An emote: "<name> is <emote> (shown as the next line appears)".
text("author.montage_builder.scene.emote_is", [[is]])
text("author.montage_builder.scene.emote_when", [[(shown as the next line appears)]])
--The else and end steps.
text("author.montage_builder.scene.else_help", [[otherwise (no condition above was true)]])
text("author.montage_builder.scene.end_help", [[closes the branch]])
--Tooltips of a step's "+" and "x".
text("author.montage_builder.scene.add_inside_tooltip", [[Add a step inside this branch]])
text("author.montage_builder.scene.add_below_tooltip", [[Add a step below this one]])
text("author.montage_builder.scene.remove_line_tooltip", [[Remove this line]])
text("author.montage_builder.scene.remove_block_tooltip", [[Remove the whole branch block, with every line inside it (click twice)]])
text("author.montage_builder.scene.remove_branch_tooltip", [[Remove this branch and the lines inside it]])
--Buttons under an "if" step. Short.
text("author.montage_builder.scene.add_else_if", [[+ Else if]])
text("author.montage_builder.scene.add_else", [[+ Else]])
text("author.montage_builder.scene.add_end", [[+ End]])
text("author.montage_builder.scene.never_closed", [[This branch is never closed.]])
--The end of the step list.
text("author.montage_builder.scene.no_lines", [[(no lines yet)]])
text("author.montage_builder.scene.add_step_at_end", [[+ Add a step at the end...]])
--The help under a scene. The second is for the lines after a roll.
text("author.montage_builder.scene.help", [[Lines play top to bottom. PC is the hero who steps up. A character must enter (with a bestiary portrait) before they can speak; a voice off stage speaks with no portrait. A branch plays different lines depending on the hero.]])
text("author.montage_builder.scene.help_outcome", [[Lines play top to bottom. PC is the hero who steps up. A character must enter (with a bestiary portrait) before they can speak; a voice off stage speaks with no portrait. A branch plays different lines depending on the hero or how the roll went.]])

--A branch's condition, as a row of dropdowns per part. The first dropdown
--joins the part on: If / Unless on an "if" line, Else if on an "else if"
--line, and / or on later parts.
text("author.montage_builder.condition.join_if", [[If]])
text("author.montage_builder.condition.join_unless", [[Unless]])
text("author.montage_builder.condition.join_else_if", [[Else if]])
text("author.montage_builder.condition.join_else_if_not", [[Else if not]])
text("author.montage_builder.condition.join_and", [[and]])
text("author.montage_builder.condition.join_and_not", [[and not]])
text("author.montage_builder.condition.join_or", [[or]])
text("author.montage_builder.condition.join_or_not", [[or not]])
text("author.montage_builder.condition.join_tooltip", [['not' makes this part true when it is NOT the case.]])
--The second dropdown: what is checked.
text("author.montage_builder.condition.predicate_ancestry", [[PC is a (ancestry)]])
text("author.montage_builder.condition.predicate_class", [[PC is a (class)]])
text("author.montage_builder.condition.predicate_career", [[PC was a (career)]])
text("author.montage_builder.condition.predicate_speaks", [[PC speaks]])
text("author.montage_builder.condition.predicate_skilled", [[PC is skilled in]])
text("author.montage_builder.condition.predicate_perk", [[PC has the perk]])
text("author.montage_builder.condition.predicate_can", [[PC can]])
text("author.montage_builder.condition.predicate_chose", [[PC chose the option]])
text("author.montage_builder.condition.predicate_tier", [[The roll is]])
text("author.montage_builder.condition.predicate_has", [[PC has (anything)]])
text("author.montage_builder.condition.predicate_is", [[PC is (anything)]])
text("author.montage_builder.condition.predicate_custom", [[Custom condition]])
--The tiers "The roll is" can check.
text("author.montage_builder.condition.tier1", [[Tier 1 (11 or lower)]])
text("author.montage_builder.condition.tier2", [[Tier 2 (12-16)]])
text("author.montage_builder.condition.tier3", [[Tier 3 (17+, or a critical)]])
text("author.montage_builder.condition.critical", [[Critical (natural 19-20)]])
text("author.montage_builder.condition.remove_part_tooltip", [[Remove this part of the condition]])
text("author.montage_builder.condition.tier_never_true", [[The roll is only known in the lines after an option's test: here this is never true.]])
--Buttons that add a part. Short.
text("author.montage_builder.condition.add_and", [[+ and]])
text("author.montage_builder.condition.add_or", [[+ or]])
text("author.montage_builder.condition.and_before_or", [['and' is checked before 'or': A and B or C means (A and B) or C.]])
text("author.montage_builder.condition.hand_written", [[Written by hand with parentheses: edit it as text, or clear the brackets to get the form back.]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: a delve (its settings) and a delve's scenes
----------------------------------------------------------------------------

--{name} is the delve's name (in capitals), {document} its journal
--document's name.
text("author.montage_builder.delve.heading", [[DELVE: {name}]])
text("author.montage_builder.delve.intro", [[In the journal document '{document}'. The whole delve is one hero's turn: they meet obstacles, find chests, and press deeper (losing a Recovery) or turn back.]])
text("author.montage_builder.delve.in_sequence", [[In sequence: obstacles come in written order, pressing on is free (a story chain)]])
--"A chest every <n> to <n> obstacles". Short words between boxes.
text("author.montage_builder.delve.chest_every", [[A chest every]])
text("author.montage_builder.delve.chest_to", [[to]])
text("author.montage_builder.delve.chest_obstacles", [[obstacles]])
text("author.montage_builder.delve.intro_label", [[Intro]])
text("author.montage_builder.delve.intro_placeholder", [[Notes for the delve (optional).]])
--The list of the delve's scenes, each "[x] Chest -- a chest is found": the
--heading is script wording; these notes say when each plays.
text("author.montage_builder.delve.sections_label", [[Scenes of the delve (pick one on the board to edit it)]])
text("author.montage_builder.delve.section_chest_note", [[a chest is found]])
text("author.montage_builder.delve.section_continue_note", [[between obstacles]])
text("author.montage_builder.delve.section_leave_note", [[turning back]])
text("author.montage_builder.delve.section_forced_note", [[at 0 Recoveries]])
text("author.montage_builder.delve.section_finish_note", [[the last step of an in-sequence delve]])
text("author.montage_builder.delve.text_editor_note", [[The whole delve as written.]])
text("author.montage_builder.delve.edit_as_text", [[Edit delve as text]])

--A delve scene's editor. Its heading is shown in capitals: {delve} is the
--delve's name, {name} the scene's (Chest, Continue...).
text("author.montage_builder.section.heading", [[Delve: {delve} -- {name}]])
text("author.montage_builder.section.scene", [[Scene]])
text("author.montage_builder.section.treasure_table", [[Treasure table]])
text("author.montage_builder.section.add_treasure_table", [[+ Treasure table]])
text("author.montage_builder.section.text_editor_note", [[The section as written.]])
text("author.montage_builder.section.edit_as_text", [[Edit as text]])
text("author.montage_builder.section.delete", [[Delete section]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: the status line at the bottom of the window, after
-- each change (also what Undo names, as "Undid: ...")
----------------------------------------------------------------------------

--{why} is the reason, which comes from the game; {what} is one of the
--messages below.
text("author.montage_builder.status.not_changed", [[Not changed: {why}]])
text("author.montage_builder.status.edit_failed", [[that edit could not be made]])
text("author.montage_builder.status.nothing_to_undo", [[Nothing to undo.]])
text("author.montage_builder.status.undid", [[Undid: {what}]])
text("author.montage_builder.status.updated_from_journal", [[Updated from the journal.]])
--{error} is the technical error.
text("author.montage_builder.status.error", [[Error: {error}]])
--Entries. {name} is an entry's name, {old} and {new} names before and
--after, {round} and {number} round numbers, {document} a document's name.
text("author.montage_builder.status.not_added_no_round", [[Not added: could not find where the round sits in the master document.]])
text("author.montage_builder.status.not_added", [[Not added: {why}]])
text("author.montage_builder.status.added_threat", [[Added threat '{name}'.]])
text("author.montage_builder.status.added_opportunity", [[Added opportunity '{name}'.]])
text("author.montage_builder.status.deleted", [[Deleted '{name}'.]])
text("author.montage_builder.status.deleted_hid_document", [[Deleted '{name}' (its document '{document}' is hidden; Undo restores the link only).]])
text("author.montage_builder.status.entry_needs_name", [[An entry needs a name.]])
text("author.montage_builder.status.renamed_entry", [[Renamed the entry.]])
text("author.montage_builder.status.renamed", [[Renamed '{old}' to '{new}'.]])
text("author.montage_builder.status.added_round", [[Added Round {number}.]])
text("author.montage_builder.status.not_moved_no_round", [[Not moved: could not find the round in the master document.]])
text("author.montage_builder.status.not_moved_shared", [[Not moved: this entry shares its document with other text; move it as text.]])
text("author.montage_builder.status.already_there", [[It is already there.]])
text("author.montage_builder.status.moved", [[Moved '{name}' to round {round}.]])
text("author.montage_builder.status.changed_kind", [[Changed the entry's kind.]])
text("author.montage_builder.status.changed_tags", [[Changed the entry's tags.]])
text("author.montage_builder.status.edited_card_text", [[Edited the card text.]])
text("author.montage_builder.status.edited_approach", [[Edited the approach text.]])
text("author.montage_builder.status.added_approach", [[Added approach text.]])
text("author.montage_builder.status.edited_consequence", [[Edited the consequence.]])
text("author.montage_builder.status.added_scene", [[Added a scene.]])
text("author.montage_builder.status.added_dice_table", [[Added a dice table.]])
text("author.montage_builder.status.added_option", [[Added an option.]])
text("author.montage_builder.status.deleted_obstacle", [[Deleted an obstacle.]])
text("author.montage_builder.status.edited_as_text", [[Edited as text.]])
--The montage and its party-size lines.
text("author.montage_builder.status.edited_montage_intro", [[Edited the montage intro.]])
text("author.montage_builder.status.party_size_needs_card", [[Not changed: a party-size line has to drop at least one card.]])
text("author.montage_builder.status.edited_party_size", [[Edited a party-size line.]])
text("author.montage_builder.status.added_party_size", [[Added a party-size line.]])
text("author.montage_builder.status.removed_party_size", [[Removed a party-size line.]])
--Options, tests and knacks. {name} is an option's name.
text("author.montage_builder.status.renamed_option", [[Renamed an option.]])
text("author.montage_builder.status.edited_option_text", [[Edited an option's text.]])
text("author.montage_builder.status.deleted_option", [[Deleted option '{name}'.]])
text("author.montage_builder.status.edited_test", [[Edited a test.]])
text("author.montage_builder.status.test_needs_characteristic", [[A test needs at least one characteristic.]])
text("author.montage_builder.status.edited_teaser", [[Edited a teaser.]])
text("author.montage_builder.status.edited_outcome", [[Edited an outcome.]])
text("author.montage_builder.status.critical_automatic", [[Critical set to automatic.]])
text("author.montage_builder.status.wrote_critical", [[Wrote a critical.]])
text("author.montage_builder.status.edited_critical", [[Edited the critical.]])
text("author.montage_builder.status.edited_rules", [[Edited the rules.]])
text("author.montage_builder.status.no_roll_needs_rule", [[An option with no roll needs something to happen.]])
text("author.montage_builder.status.added_rule_line", [[Added a rule line.]])
text("author.montage_builder.status.removed_rule_line", [[Removed a rule line.]])
text("author.montage_builder.status.changed_to_no_roll", [[Changed to no roll.]])
text("author.montage_builder.status.changed_to_test", [[Changed to a test.]])
text("author.montage_builder.status.added_knack", [[Added a knack.]])
text("author.montage_builder.status.edited_knack", [[Edited a knack.]])
text("author.montage_builder.status.removed_knack", [[Removed a knack.]])
text("author.montage_builder.status.added_knack_version", [[Added a knack version.]])
text("author.montage_builder.status.edited_knack_version", [[Edited a knack version.]])
text("author.montage_builder.status.deleted_knack_version", [[Deleted a knack version.]])
--Dice tables.
text("author.montage_builder.status.renamed_table", [[Renamed a dice table.]])
text("author.montage_builder.status.changed_table_dice", [[Changed a table's dice.]])
text("author.montage_builder.status.changed_table_mystery", [[Changed whether a table's rows are a mystery.]])
text("author.montage_builder.status.edited_table_row", [[Edited a table row.]])
text("author.montage_builder.status.added_table_row", [[Added a table row.]])
text("author.montage_builder.status.removed_table_row", [[Removed a table row.]])
--{name} is the table's name.
text("author.montage_builder.status.deleted_table", [[Deleted the dice table '{name}'.]])
--Scenes and branches. {old} and {new} are a character's names before and
--after.
text("author.montage_builder.status.edited_scene_line", [[Edited a scene line.]])
text("author.montage_builder.status.added_scene_step", [[Added a scene step.]])
text("author.montage_builder.status.removed_scene_line", [[Removed a scene line.]])
text("author.montage_builder.status.nowhere_for_line", [[Nowhere to put the line.]])
text("author.montage_builder.status.pc_is_the_hero", [['PC' is the hero; a character needs another name.]])
text("author.montage_builder.status.renamed_character", [[Renamed '{old}' to '{new}' in this entry's scenes.]])
text("author.montage_builder.status.edited_condition", [[Edited a branch condition.]])
text("author.montage_builder.status.added_else_if", [[Added an 'else if' branch.]])
text("author.montage_builder.status.added_else", [[Added an 'else' branch.]])
text("author.montage_builder.status.closed_branch", [[Closed the branch.]])
text("author.montage_builder.status.removed_branch_block", [[Removed a branch block.]])
text("author.montage_builder.status.removed_branch", [[Removed a branch.]])
--Delves. {name} is a delve's name.
text("author.montage_builder.status.added_delve", [[Added the delve '{name}'.]])
text("author.montage_builder.status.added_obstacle", [[Added an obstacle.]])
text("author.montage_builder.status.delve_in_sequence", [[Delve set to in sequence.]])
text("author.montage_builder.status.delve_random", [[Delve set to random.]])
text("author.montage_builder.status.chest_interval_invalid", [[A chest interval is two numbers, low to high (e.g. 1 and 2).]])
text("author.montage_builder.status.changed_chest_interval", [[Changed the chest interval.]])
text("author.montage_builder.status.set_chest_interval", [[Set the chest interval.]])
text("author.montage_builder.status.edited_delve_intro", [[Edited the delve intro.]])
text("author.montage_builder.status.added_section", [[Added a delve section.]])
text("author.montage_builder.status.deleted_section", [[Deleted a delve section.]])
text("author.montage_builder.status.added_treasure_table", [[Added a treasure table.]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the outline on the left (the whole script, in the
-- order it plays)
----------------------------------------------------------------------------

--On a map that is one part of a series. {number} is the part number,
--{title} the part's title.
text("author.script_builder.outline.series_part", [[Part {number} of a series.]])
text("author.script_builder.outline.series_part_titled", [[Part {number} of a series: {title}.]])

--The Optional features card: its small kind tag, its title, and one line
--per feature under it. {feature} is a feature's name.
text("author.script_builder.outline.features_kind", [[FEATURES]])
text("author.script_builder.outline.features_title", [[Optional features]])
text("author.script_builder.outline.feature_on", [[{feature}: on]])
text("author.script_builder.outline.feature_off", [[{feature}: off]])

--Section headings of the outline.
text("author.script_builder.outline.before_heading", [[Before the adventure]])
text("author.script_builder.outline.beats_heading", [[The adventure, in order]])
text("author.script_builder.outline.after_heading", [[After the adventure]])

--The small kind tag on a Town Gate, Conclusion or Defeat card. Short.
text("author.script_builder.outline.story_kind", [[STORY]])
--The button that adds a missing story text. {title} is Town Gate,
--Conclusion or Defeat. Short: a button.
text("author.script_builder.outline.add_story", [[+ {title} text]])

--The small kind tag on a beat's card (shown in capitals, after its number).
--Short.
text("author.script_builder.outline.kind_narrative", [[Narrative]])
text("author.script_builder.outline.kind_montage", [[Montage]])
text("author.script_builder.outline.kind_encounter", [[Encounter]])
--A top-level heading the script does not know, which the game skips.
text("author.script_builder.outline.kind_unknown", [[Ignored]])
--Tooltips of the small up and down arrows on a beat's card.
text("author.script_builder.outline.move_earlier_tooltip", [[Play this earlier]])
text("author.script_builder.outline.move_later_tooltip", [[Play this later]])
--Under a card with problems. {count} is how many.
text("author.script_builder.outline.problems.one", [[{count} problem]])
text("author.script_builder.outline.problems.other", [[{count} problems]])
text("author.script_builder.outline.no_beats", [[No beats yet.]])
--The buttons that add a beat, and the line under them. Short: buttons.
text("author.script_builder.outline.add_narrative", [[+ Narrative]])
text("author.script_builder.outline.add_montage", [[+ Montage]])
text("author.script_builder.outline.add_encounter", [[+ Encounter]])
text("author.script_builder.outline.add_help", [[A narrative or montage is added in front of the encounter; ^ and v change the order.]])

--A beat's title on its card, in status messages, and (in capitals) at the
--top of its editor. {scene} is the name of a narrative's first scene.
text("author.script_builder.beat.label_narrative_scene", [[Narrative: {scene}]])
text("author.script_builder.beat.label_narrative", [[Narrative]])
text("author.script_builder.beat.label_montage", [[Montage]])
text("author.script_builder.beat.label_encounter", [[Encounter]])
--A beat of a kind the builder does not know, with no title of its own.
text("author.script_builder.beat.label_other", [[Beat]])
--The card summary for a heading the script does not know.
text("author.script_builder.beat.summary_unknown", [[Not a script heading: skipped when played.]])

--The one-line summary on a beat's card.
--A narrative: {scenes} and {choices} are the two counts below.
text("author.script_builder.beat.summary_narrative", [[{scenes}, {choices}]])
text("author.script_builder.beat.scenes.one", [[{count} scene]])
text("author.script_builder.beat.scenes.other", [[{count} scenes]])
text("author.script_builder.beat.choices.one", [[{count} choice]])
text("author.script_builder.beat.choices.other", [[{count} choices]])
--A montage: {rounds} and {entries} are the two counts below.
text("author.script_builder.beat.summary_montage", [[{rounds}, {entries}]])
text("author.script_builder.beat.rounds.one", [[{count} round]])
text("author.script_builder.beat.rounds.other", [[{count} rounds]])
text("author.script_builder.beat.entries.one", [[{count} opportunity and threats]])
text("author.script_builder.beat.entries.other", [[{count} opportunities and threats]])
--The encounter: these parts are joined with commas.
text("author.script_builder.beat.monsters_placed", [[monsters placed]])
text("author.script_builder.beat.no_monsters", [=[NO monsters ([[encounter]] missing)]=])
text("author.script_builder.beat.setup_lines.one", [[{count} setup line]])
text("author.script_builder.beat.setup_lines.other", [[{count} setup lines]])
text("author.script_builder.beat.reinforcement_groups.one", [[{count} reinforcement group]])
text("author.script_builder.beat.reinforcement_groups.other", [[{count} reinforcement groups]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the editor on the right, before anything is picked
----------------------------------------------------------------------------

text("author.script_builder.editor.empty_heading", [[Pick a part of the script on the left.]])
text("author.script_builder.editor.empty_help", [[The script plays top to bottom: the Town Gate text in town, then each beat in order (narratives, montages, the encounter), then the Conclusion or Defeat screen. Optional features (like Intelligence) are turned on at the top.]])
text("author.script_builder.editor.empty_undo", [[Every change is written straight into the journal document it came from and re-checked with the game's own parser. Undo takes back one change at a time.]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the Optional features editor
----------------------------------------------------------------------------

text("author.script_builder.features.heading", [[OPTIONAL FEATURES]])
text("author.script_builder.features.intro", [[Parts of Encounter of the Week a script turns on for itself. A feature the script does not turn on is not part of the game at all.]])
--Under each feature's tick box. {summary} is what the feature does (it
--comes from the game).
text("author.script_builder.features.turns_on", [[Turns on {summary}.]])
--A feature that is on: where the party is told about it. {where} is a
--beat's title, or the scene line below.
text("author.script_builder.features.on_explained", [[ON: explained to the party when {where} opens.]])
--{scene} is a scene's name, {beat} the beat's title.
text("author.script_builder.features.where_scene", [[the scene '{scene}' of {beat}]])
--The Intelligence feature: how many outcomes give Intelligence. {count}
--is that number.
text("author.script_builder.features.intelligence_none", [[Nothing in the script grants Intelligence yet: add 'Reward: Intelligence' to some outcomes.]])
text("author.script_builder.features.intelligence_grants.one", [[{count} outcome grants Intelligence.]])
text("author.script_builder.features.intelligence_grants.other", [[{count} outcomes grant Intelligence.]])
--{explanation} is the game's explanation of the feature to the players.
text("author.script_builder.features.party_told", [[What the party is told: {explanation}]])
--A feature that is off. {feature} is its name. 'Unlock: ...' is a script
--line and must stay as it is.
text("author.script_builder.features.off_help", [[OFF. Ticking it writes 'Unlock: {feature}' into the first narrative beat (one is made at the start if the script has none), so the party is told about it as that beat opens.]])
text("author.script_builder.features.intelligence_off", [[Some outcomes grant Intelligence, but it is off: the party could never spend it.]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the Town Gate, Conclusion and Defeat editors
----------------------------------------------------------------------------

--The line under each story text's heading.
text("author.script_builder.story.towngate_note", [[Shown in town under the encounter while a party forms: why the heroes should come.]])
text("author.script_builder.story.conclusion_note", [[The story screen after a victory, before the heroes return to Blackbottom.]])
text("author.script_builder.story.defeat_note", [[The story screen after a defeat.]])
--Shown when the script does not have this text yet. Short: a button.
text("author.script_builder.story.add_button", [[+ Add it]])
--Under the text when it has a backdrop picture. [[scene]] is a journal tag
--and must stay as it is.
text("author.script_builder.story.backdrop", [=[Backdrop: its [[scene]] picture (set in the journal).]=])
--Buttons. Short.
text("author.script_builder.story.open_in_journal", [[Open in journal]])
text("author.script_builder.story.delete_button", [[Delete this text]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the narrative editor
----------------------------------------------------------------------------

text("author.script_builder.narrative.intro_help", [[A story beat on the stage: its scenes play in order, and each may ask the party a choice.]])
text("author.script_builder.narrative.intro_label", [[Intro: shown when the beat opens]])
--Grey example text in the empty intro box.
text("author.script_builder.narrative.intro_placeholder", [[The heroes gather before the road ahead.]])
--When the beat or a scene turns on an optional feature. {feature} is its
--name.
text("author.script_builder.narrative.turns_on_beat", [[Turns on {feature} as it opens (Optional features).]])
text("author.script_builder.narrative.turns_on_scene", [[Turns on {feature} when this scene arrives.]])
--When the beat has a backdrop picture. [[scene]] is a journal tag and must
--stay as it is.
text("author.script_builder.narrative.backdrop", [=[Backdrop: its [[scene]] picture (set in the journal).]=])
--Each scene: its heading ({number} is the scene's number), its text box
--and the box's grey example text.
text("author.script_builder.narrative.scene_heading", [[SCENE {number}]])
text("author.script_builder.narrative.scene_text_label", [[What happens]])
text("author.script_builder.narrative.scene_text_placeholder", [[The road forks beneath a lightning-split oak.]])
--The scene's choice: who chooses, and the question.
text("author.script_builder.narrative.choice_label", [[The choice]])
text("author.script_builder.narrative.mode_together", [[The party chooses together]])
text("author.script_builder.narrative.mode_individual", [[Each hero chooses for themselves]])
text("author.script_builder.narrative.mode_tooltip", [[Together: one vote per player, and a split vote is settled at random. Each hero: every hero picks, and each choice applies to those who took it.]])
text("author.script_builder.narrative.prompt_placeholder", [[The question (optional): Which way do you go?]])
text("author.script_builder.narrative.mode_implicit", [[Not written yet: pick who chooses to make it explicit.]])
text("author.script_builder.narrative.no_choices", [[No choices: the party reads it and presses on.]])
--Each choice: its heading ({number} is the choice's number), its delete
--button, and the grey example text of its boxes.
text("author.script_builder.narrative.choice_heading", [[CHOICE {number}]])
text("author.script_builder.narrative.delete_choice_button", [[Delete]])
text("author.script_builder.narrative.choice_text_placeholder", [[Shown with the choice (optional): The ridge path is longer but safer.]])
text("author.script_builder.narrative.choice_rule_placeholder", [[What happens when it is chosen (optional words)]])
--Buttons. Short.
text("author.script_builder.narrative.add_choice", [[+ Choice]])
text("author.script_builder.narrative.delete_scene", [[Delete scene]])
text("author.script_builder.narrative.add_scene", [[+ Scene]])
text("author.script_builder.narrative.open_in_journal", [[Open in journal]])
text("author.script_builder.narrative.delete_button", [[Delete this narrative]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: a montage beat (the board itself is the Montage
-- Builder)
----------------------------------------------------------------------------

text("author.script_builder.montage.heading", [[MONTAGE]])
text("author.script_builder.montage.intro", [[Rounds of opportunities and threats: each hero takes a turn at one, with tests, scenes and delves.]])
--Short: a button.
text("author.script_builder.montage.open_builder", [[Open in the Montage Builder]])
--One line per round. {number} is the round number, {entries} the names of
--its opportunities and threats (or the empty word below).
text("author.script_builder.montage.round_line", [[Round {number}: {entries}]])
text("author.script_builder.montage.round_empty", [[(empty)]])
--Buttons. Short.
text("author.script_builder.montage.open_in_journal", [[Open in journal]])
text("author.script_builder.montage.delete_button", [[Delete this montage]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the encounter editor
----------------------------------------------------------------------------

text("author.script_builder.encounter.heading", [[ENCOUNTER]])
text("author.script_builder.encounter.intro", [[The fight. Setup runs once, just before the monsters appear.]])
text("author.script_builder.encounter.monsters_label", [[The monsters]])
--Where the monsters are described, when there are none yet.
text("author.script_builder.encounter.no_monsters", [[No monsters yet.]])
--The monsters' description with their encounter value. {monsters} is the
--description, {ev} the number.
text("author.script_builder.encounter.monsters_with_ev", [[{monsters}  (EV {ev})]])
--The button that opens the combat Encounter Builder, and its tooltip.
text("author.script_builder.encounter.open_combat_builder", [[Open Combat Encounter Builder]])
text("author.script_builder.encounter.open_combat_builder_tooltip", [[Pick the monsters, balance the encounter and place them on the map. Saving there saves them into this script.]])
--When the encounter is the map's own, with no script line.
text("author.script_builder.encounter.implicit", [[The encounter comes from the map's own encounter, not from a script line.]])
--Buttons. Short.
text("author.script_builder.encounter.add_reinforcements", [[+ Reinforcements]])
text("author.script_builder.encounter.delete_button", [[Delete the encounter]])

--The editor for a top-level heading the script does not know. {title} is
--the heading's text.
text("author.script_builder.unknown.help", [[The game skips this part of the script: '# {title}' is not a heading it knows. Rename it in the journal document to Narrative, Montage, Encounter, Delve: <name>, Town Gate, Conclusion or Defeat, or delete it.]])
text("author.script_builder.unknown.delete_button", [[Delete this heading and its text]])

--The setup lines, each a sentence of words and pickers. A placeobjects line
--reads "<label> Place <number> <object> objects in <zone> zones".
text("author.script_builder.setup.label", [[Setup and victory]])
text("author.script_builder.setup.none", [[None: the fight starts as the map is laid out.]])
--The dropdown that adds a setup line, and its choices.
text("author.script_builder.setup.add", [[+ Add setup...]])
text("author.script_builder.setup.kind_placeobjects", [[Place objects in zones]])
text("author.script_builder.setup.kind_bystanders", [[Bystanders (stay out of initiative)]])
text("author.script_builder.setup.kind_victory", [[Extra way to win]])
text("author.script_builder.setup.help", [[Place objects: draws that many tiles of the zone type and copies the object onto each (traps). Bystanders: tokens on the map that never take a turn. Extra way to win: on top of defeating the encounter.]])
--The words of a "place objects" line. Short: they sit between pickers.
text("author.script_builder.setup.place", [[Place]])
text("author.script_builder.setup.object_tooltip", [[An object on this map; one is copied onto each drawn tile.]])
text("author.script_builder.setup.objects_in", [[objects in]])
text("author.script_builder.setup.zones", [[zones]])
text("author.script_builder.setup.delete_others", [[and delete the other ones]])
text("author.script_builder.setup.delete_others_tooltip", [[Every tile of that zone type that was not drawn is removed, so only the placed ones matter.]])
--A bystanders line: grey example names in its box, and the words after it.
text("author.script_builder.setup.bystander_names_placeholder", [[Civilian, Old Tam]])
text("author.script_builder.setup.bystanders_rest", [[tokens stay out of initiative]])
--An extra-way-to-win line: "The heroes also win when every <enemy> on the
--map is defeated". The middle word is a dropdown of monster keywords;
--victory_enemy is its first choice.
text("author.script_builder.setup.victory_start", [[The heroes also win when every]])
text("author.script_builder.setup.victory_enemy", [[enemy]])
text("author.script_builder.setup.victory_end", [[on the map is defeated]])
--The tooltip of the small x at the end of each setup line.
text("author.script_builder.setup.remove_tooltip", [[Remove this line]])

--A group of reinforcements.
text("author.script_builder.reinforcements.heading", [[REINFORCEMENTS]])
--When they arrive: "Arrive on rounds 3" or "Arrive every 2 round(s) from
--round 2 until 6". Short words: they sit between pickers.
text("author.script_builder.reinforcements.arrive", [[Arrive]])
text("author.script_builder.reinforcements.mode_rounds", [[on rounds]])
text("author.script_builder.reinforcements.mode_every", [[every N rounds]])
--Grey example text in the box of round numbers.
text("author.script_builder.reinforcements.rounds_placeholder", [[3, or 2, 4]])
text("author.script_builder.reinforcements.every", [[every]])
text("author.script_builder.reinforcements.rounds_from", [[round(s) from round]])
--The last picker: "on" (no end), or "until <round>".
text("author.script_builder.reinforcements.until_none", [[on]])
text("author.script_builder.reinforcements.until_round", [[until {round}]])
text("author.script_builder.reinforcements.never_arrive", [[(not set: they never arrive)]])
--Where they come in. The first choice of the zone dropdown is
--enter_where_placed.
text("author.script_builder.reinforcements.enter", [[Enter]])
text("author.script_builder.reinforcements.enter_where_placed", [[where their group was placed]])
text("author.script_builder.reinforcements.enter_tooltip", [[A zone type on the map: they appear on its tiles.]])
--The label before each line they shout as they arrive. Short.
text("author.script_builder.reinforcements.shout", [[Shout]])
text("author.script_builder.reinforcements.no_groups", [[No groups of monsters yet: '+ Group' adds one.]])
--One line per group of monsters. {number} is the group's number,
--{monsters} what is in it. With several groups they take turns: {first}
--and {second} are the arrivals this group comes on.
text("author.script_builder.reinforcements.group", [[Group {number}: {monsters}]])
text("author.script_builder.reinforcements.group_cycle", [[Group {number} (arrival {first}, {second}, ...): {monsters}]])
--Buttons. Short.
text("author.script_builder.reinforcements.add_shout", [[+ Shout]])
text("author.script_builder.reinforcements.add_group", [[+ Group]])
text("author.script_builder.reinforcements.delete_button", [[Delete]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: the status line at the bottom of the window,
-- after each change (also listed by Undo, as "Undid: ...")
----------------------------------------------------------------------------

--{beat} is a beat's title; {why} is the reason, which comes from the game.
text("author.script_builder.status.not_moved_shared", [[Not moved: that beat shares its journal document with other sections; move it in the journal.]])
text("author.script_builder.status.not_moved", [[Not moved: {why}]])
text("author.script_builder.status.moved_earlier", [[Moved '{beat}' earlier.]])
text("author.script_builder.status.moved_later", [[Moved '{beat}' later.]])
text("author.script_builder.status.not_deleted_shared", [[Not deleted: that beat shares its journal document with other sections; delete it in the journal.]])
text("author.script_builder.status.deleted_beat", [[Deleted '{beat}'.]])
text("author.script_builder.status.added_narrative", [[Added a narrative beat.]])
text("author.script_builder.status.added_montage", [[Added a montage beat.]])
text("author.script_builder.status.added_encounter", [[Added an encounter beat.]])
text("author.script_builder.status.added_unparsed", [[Added, but the new beat did not parse: check the journal.]])
--{title} is Town Gate, Conclusion or Defeat.
text("author.script_builder.status.added_story", [[Added the {title} text.]])
text("author.script_builder.status.edited_story", [[Edited the {title} text.]])
text("author.script_builder.status.deleted_story", [[Deleted the {title} text.]])
--{feature} is an optional feature's name.
text("author.script_builder.status.feature_off", [[Turned {feature} off.]])
text("author.script_builder.status.feature_on", [[Turned {feature} on (in the first narrative).]])
text("author.script_builder.status.feature_on_new_narrative", [[Turned {feature} on (in a new narrative at the start).]])
text("author.script_builder.status.island_not_found", [=[Could not find that [[encounter]] island in its document.]=])
--Narratives. {scene} is a scene's name, {choice} a choice's.
text("author.script_builder.status.edited_narrative_intro", [[Edited the narrative's intro.]])
text("author.script_builder.status.renamed_scene", [[Renamed a scene.]])
text("author.script_builder.status.edited_scene_text", [[Edited a scene's text.]])
text("author.script_builder.status.edited_scene_choice", [[Edited a scene's choice.]])
text("author.script_builder.status.added_scene", [[Added a scene.]])
text("author.script_builder.status.deleted_scene", [[Deleted the scene '{scene}'.]])
text("author.script_builder.status.added_choice", [[Added a choice.]])
text("author.script_builder.status.renamed_choice", [[Renamed a choice.]])
text("author.script_builder.status.edited_choice_text", [[Edited a choice's text.]])
text("author.script_builder.status.deleted_choice", [[Deleted the choice '{choice}'.]])
text("author.script_builder.status.added_choice_rule", [[Added what a choice does.]])
text("author.script_builder.status.edited_choice_rule", [[Edited what a choice does.]])
text("author.script_builder.status.removed_choice_rule", [[Removed what a choice does.]])
--The encounter. {name} is a group of reinforcements' name.
text("author.script_builder.status.added_island", [[Added the encounter island.]])
text("author.script_builder.status.added_setup", [[Added a setup line.]])
text("author.script_builder.status.edited_setup", [[Edited a setup line.]])
text("author.script_builder.status.removed_setup", [[Removed a setup line.]])
text("author.script_builder.status.added_reinforcements", [[Added reinforcements.]])
text("author.script_builder.status.renamed_reinforcements", [[Renamed reinforcements.]])
text("author.script_builder.status.deleted_reinforcements", [[Deleted the reinforcements '{name}'.]])
text("author.script_builder.status.edited_arrive", [[Edited when reinforcements arrive.]])
text("author.script_builder.status.set_arrive", [[Set when reinforcements arrive.]])
text("author.script_builder.status.enter_where_placed", [[Reinforcements arrive where they were placed.]])
text("author.script_builder.status.changed_enter", [[Changed where reinforcements enter.]])
text("author.script_builder.status.set_enter", [[Set where reinforcements enter.]])
text("author.script_builder.status.added_shout", [[Added a shout.]])
text("author.script_builder.status.edited_shout", [[Edited a shout.]])
text("author.script_builder.status.removed_shout", [[Removed a shout.]])
text("author.script_builder.status.added_group", [[Added a reinforcement group.]])

----------------------------------------------------------------------------
-- THE AUTHORING TEST: the Test Encounter dialog (the hero picker), opened
-- from the Game menu's Test Encounter rows
----------------------------------------------------------------------------

--The dialog's title, and the paragraph under it.
text("author.test.picker.title", [[Test Encounter]])
text("author.test.picker.intro", [[Play this map's encounter the way its players will: you become a player for the test, with copies of the heroes you choose placed in the Start zone. END TEST (in the title bar) puts the map back and returns you to the Director.]])
--The label beside the dropdown of where the test starts (the first beat, the
--montage or the combat). Short.
text("author.test.picker.start_at", [[Start at]])
--On a map with several parts: the label beside the part dropdown. Short.
text("author.test.picker.part", [[Part]])
--The part dropdown's choices. {number} is the part number, {title} its
--title.
text("author.test.picker.part_option", [[Part {number}]])
text("author.test.picker.part_option_titled", [[Part {number}: {title}]])
--The checkbox that tests the encounter's Challenge Mode, and its tooltip.
text("author.test.picker.challenge", [[Challenge Mode]])
text("author.test.picker.challenge_tooltip", [[Play the encounter's Challenge Mode: monsters balanced for one more hero (or the strongest leveled up for a party of 6), one more montage threat, and threat consequences that cost one more Malice or Recovery.]])
--The heading over the list of heroes to choose from. Short.
text("author.test.picker.heroes_heading", [[Heroes]])
--Small headings that group the heroes in the list. Short.
text("author.test.picker.group_pregens", [[Pregens]])
text("author.test.picker.group_other", [[Other heroes in this game]])
--Shown instead of the list when there is nobody to test with.
text("author.test.picker.no_heroes", [[This game has no heroes off this map to test with. Install a module with pregens (or make some heroes) and keep them off the encounter map.]])
--Under the list, when heroes already stand on the map. {heroes} is their
--names, separated by commas.
text("author.test.picker.already_on_map", [[Already on this map, so also in the test: {heroes}.]])

--The status line above the Start button, depending on how many heroes are
--ticked. {count} is how many are ticked, {max} the most a party may have.
text("author.test.picker.status_none", [[Choose the heroes to play the encounter with.]])
text("author.test.picker.status_too_many", [[{count} heroes chosen: a party is at most {max}.]])
--Fewer than 4 heroes ticked (one form for 1 hero, one for more).
text("author.test.picker.status_few.one", [[{count} hero chosen. A real party is 4-6; the monsters scale for at least 3.]])
text("author.test.picker.status_few.other", [[{count} heroes chosen. A real party is 4-6; the monsters scale for at least 3.]])
text("author.test.picker.status_ok", [[{count} heroes chosen.]])
--When the chosen part has nothing to test. {part} is the part number,
--{reason} says why (it comes from the game).
text("author.test.picker.part_untestable", [[Part {part} cannot be tested: {reason}]])

--The dialog's buttons. Short: buttons.
text("author.test.picker.start_button", [[START TEST]])
text("author.test.picker.cancel_button", [[CANCEL]])

----------------------------------------------------------------------------
-- THE AUTHORING TEST: the item in the title bar while a test runs
----------------------------------------------------------------------------

--What is being tested. {mode} is the test's starting point (for example
--Combat). The first is shown for a moment before the test is known.
text("author.test.titlebar.title_initial", [[Encounter Test]])
text("author.test.titlebar.title", [[Encounter Test: {mode}]])
text("author.test.titlebar.title_ending", [[Encounter Test: {mode} (ending...)]])
--The button that ends the test, and what it says once pressed. Short: a
--small button.
text("author.test.titlebar.end_button", [[END TEST]])
text("author.test.titlebar.ending_button", [[ENDING...]])

----------------------------------------------------------------------------
-- THE SCRIPT VALIDATOR: the Encounter Script panel (opened from the
-- builder's Validator button, or /eotwvalidate). Its report is a plain list
-- of lines, so most of these are terse checklist notes.
----------------------------------------------------------------------------

--The document picker at the top. {name} is a journal document's name.
text("author.validator.documents.untitled", [[(untitled)]])
text("author.validator.documents.this_map", [=[{name}  [this map]]=])
--The button beside the picker. Short: a button.
text("author.validator.panel.recheck_button", [[Re-check]])
--When the panel itself breaks. {error} is the technical error.
text("author.validator.panel.failed", [[Validation failed: {error}]])

--The summary line at the top of the report. The counts are numbers.
text("author.validator.report.summary_ok", [[{beats} beats, {entries} entries, {options} options -- {rules} rules matched, {flavour} text-only clauses -- no problems]])
text("author.validator.report.summary_problems", [[{beats} beats, {entries} entries, {options} options -- {rules} rules matched, {flavour} text-only clauses -- {problems} PROBLEMS]])
text("author.validator.report.no_document", [[No such document.]])
--The sub-documents the script pulls in. {list} is their names.
text("author.validator.report.includes.one", [[includes {count} sub-document: {list}]])
text("author.validator.report.includes.other", [[includes {count} sub-documents: {list}]])
--The [[encounter]] tag must stay as it is.
text("author.validator.report.no_encounter_island", [=[no [[encounter]] island: this document spawns no combat]=])
--A script that is one part of a series. {number} is its part number,
--{previous} the part before it, {title} its title.
text("author.validator.report.part_first", [[Part 1 of a series: always open; winning it unlocks Part 2]])
text("author.validator.report.part_first_titled", [[Part 1: {title} of a series: always open; winning it unlocks Part 2]])
text("author.validator.report.part_later", [[Part {number} of a series: the town offers it once Part {previous} is won]])
text("author.validator.report.part_later_titled", [[Part {number}: {title} of a series: the town offers it once Part {previous} is won]])
text("author.validator.report.part_no_region", [[this part's encounter has no region, so heroes can walk into the other parts' areas: draw one in the encounter builder, then load it into the island]])
--{count} is the builder's "Victories awarded", {challenge} the Challenge Mode total, {limit} the warning threshold.
text("author.validator.report.victories.one", [[winning is worth {count} Victory ({challenge} in Challenge Mode)]])
text("author.validator.report.victories.other", [[winning is worth {count} Victories ({challenge} in Challenge Mode)]])
text("author.validator.report.victories_high", [[a Challenge Mode win is worth {challenge} Victories, more than {limit}: lower "Victories awarded" in the encounter builder unless you mean it]])

--Section headings of the report.
text("author.validator.report.problems_heading", [[Problems]])
--{count} is how many clauses.
text("author.validator.report.text_only_heading", [[Text-only clauses ({count}) -- no rule matched; check for a typo'd rule among them]])
text("author.validator.report.script_heading", [[Script]])
text("author.validator.report.names_heading", [[Names]])

--The problems the validator adds to the game's own. {where} is a place in
--the script (like "line 12"), {attr} a test's characteristic and skills as
--written, {skill} one skill name, {option} an option's name, {problem} one
--of these problems, {text} a setup line as written.
text("author.validator.problems.no_characteristic", [['{attr}' names no characteristic; the test has nothing to roll]])
text("author.validator.problems.not_a_skill", [['{skill}' is not a skill name; it adds nothing to the roll]])
text("author.validator.problems.option_problem", [[{where}: option '{option}' -- {problem}]])
text("author.validator.problems.setup_not_understood", [[{where}: setup instruction '{text}' is not understood]])
--{behavior} is the name the line gave, {known} the Monster AI's behavior names.
text("author.validator.problems.unknown_ai_behavior", [[{where}: '{behavior}' is not a Monster AI behavior (known: {known})]])

--The Names section: every item, monster, object and zone the script names,
--and whether the game can find it. {name} is the name as written.
text("author.validator.names.item_found", [[item '{name}': found]])
text("author.validator.names.item_not_found", [[item '{name}': NOT FOUND]])
text("author.validator.names.monster_found", [[monster '{name}': found]])
text("author.validator.names.monster_not_found", [[monster '{name}': NOT FOUND]])
text("author.validator.names.object_found", [[object '{name}': found]])
text("author.validator.names.object_not_found", [[object '{name}': NOT FOUND]])
text("author.validator.names.zone_found", [[zone '{name}': found]])
text("author.validator.names.zone_not_found", [[zone '{name}': NOT FOUND]])

--The Script section: the script laid out line by line.
--A beat. {number} is its number, {title} its title, {kind} its kind as the
--script names it (narrative, montage, encounter).
text("author.validator.report.beat", [=[Beat {number}: {title}  [{kind}]]=])
text("author.validator.report.beat_implicit", [[Beat {number}: {title}  [{kind}]  (implicit)]])
--The [[...]] around {tag} make a journal tag and must stay. {tag} is the tag's name.
text("author.validator.report.scene_tag", [=[scene: [[{tag}]]]=])
text("author.validator.report.intro", [[intro: {intro}]])
--{feature} is an optional feature's name.
text("author.validator.report.unlocks_beat", [[unlocks the {feature} feature when this beat opens]])
text("author.validator.report.unlocks_section", [[unlocks the {feature} feature when this section arrives]])
--Setup lines. {label} is the line's own label, {qty} a number, {object} an
--object's name, {zone} a zone type, {names} the bystanders' names, {text}
--the line as written.
text("author.validator.report.setup_place", [[setup {label}: place {qty} x '{object}' in {zone} zones]])
text("author.validator.report.setup_place_delete", [[setup {label}: place {qty} x '{object}' in {zone} zones, delete the other {zone} zones]])
text("author.validator.report.setup_bystanders", [[setup {label}: bystanders (no initiative): {names}]])
text("author.validator.report.setup_unrecognized", [[setup {label}: UNRECOGNIZED '{text}']])
--A "Monster AI:" line. {text} reads like "Bully on for Goblin Sniper".
text("author.validator.report.setup_ai_behavior", [[setup {label}: {text}]])
--Reinforcements. {name} is the group's name, {schedule} when they arrive
--(the game describes it), {zone} a zone type, {count} how many encounter
--islands, {text} a line they shout. [[encounter]] is a journal tag and
--must stay as it is.
text("author.validator.report.reinforcements", [[Reinforcements: {name}]])
text("author.validator.report.arrive", [[arrive: {schedule}]])
text("author.validator.report.arrive_never", [[arrive: NEVER (no Arrive: line)]])
text("author.validator.report.enter_zone", [[enter: {zone} zone]])
text("author.validator.report.enter_saved", [[enter: the islands' saved positions]])
text("author.validator.report.islands_take_turns", [=[{count} [[encounter]] islands take turns, one per arrival]=])
text("author.validator.report.islands", [=[{count} [[encounter]] island]=])
text("author.validator.report.shout", [[shout: "{text}"]])
--A narrative's section. {name} is its name, {mode} who chooses (as the
--script names it).
text("author.validator.report.section", [[Section: {name}  ({mode})]])
--An option or round the script did not write but the game supplies.
--{name} is the option's name, {number} the round's.
text("author.validator.report.option_implicit", [[{name}  (implicit)]])
text("author.validator.report.round", [[Round {number}]])
text("author.validator.report.round_implicit", [[Round {number}  (implicit)]])
text("author.validator.report.scaling", [[scaling: {text}]])
--A montage entry. {name} is its name, {tags} its tags in brackets (or
--nothing). The tag words are below.
text("author.validator.report.entry_threat", [[Threat: {name}{tags}]])
text("author.validator.report.entry_opportunity", [[Opportunity: {name}{tags}]])
text("author.validator.report.tag_required", [[Required]])
text("author.validator.report.tag_locked", [[Locked]])
text("author.validator.report.tag_temporary", [[Temporary]])
--Labels at the start of a rules line; each ends with a space, and the
--line's text follows. {tier} is 1, 2 or 3.
text("author.validator.report.consequence_label", [[Consequence: ]])
text("author.validator.report.tier_label", [[tier {tier}: ]])
text("author.validator.report.critical_auto_label", [[critical (automatic): ]])
text("author.validator.report.critical_label", [[critical: ]])
text("author.validator.report.no_roll_label", [[no roll: ]])
--A tier's teaser. {label} is one of the labels above, {teaser} the teaser.
text("author.validator.report.teaser", [[{label}teaser '{teaser}']])
--A rule the players never see. {rule} is the rule, as the game describes it.
text("author.validator.report.hidden_rule", [[(hidden) {rule}]])
--The label of a secret option's Allow line (the line's text follows).
text("author.validator.report.secret_rider", [[Secret (only for)]])
--{delve} is a delve's name.
text("author.validator.report.enters_delve", [[enters the delve '{delve}']])
text("author.validator.report.no_rules", [[no power roll and no rules]])
--{name} is a secret option's name.
text("author.validator.report.option_secret", [[{name}  (SECRET)]])
--A knack version. {requirement} is what a hero needs, as written.
text("author.validator.report.knack", [[Knack -- if {requirement}:]])

--The Knack coverage section: how well the montage's knacks fit a party.
text("author.validator.coverage.heading", [[Knack coverage]])
--The party dropdown. {party} is a party's name, {count} its heroes.
text("author.validator.coverage.party_option", [[{party} ({count} heroes)]])
text("author.validator.coverage.all_heroes", [[All heroes in the game]])
--A hero with no name of their own.
text("author.validator.coverage.unnamed_hero", [[(unnamed)]])
--{with} is how many have one, {total} how many there are.
text("author.validator.coverage.tests", [[Tests with a knack: {with} of {total} (standard: every test)]])
--{test} names an entry and its option.
text("author.validator.coverage.test_no_knack", [[no knack: {test}]])
text("author.validator.coverage.opportunities", [[Opportunities with a secret option or knack: {with} of {total} (standard: most)]])
--{entry} is an opportunity's name.
text("author.validator.coverage.opportunity_none", [[none: {entry}]])
text("author.validator.coverage.threats", [[Threats with a secret option or knack: {with} of {total} (standard: some)]])
--{hooks} is how many knacks in all, {list} the overused requirements.
text("author.validator.coverage.leaning", [[Leaning on one knack (over 15% of {hooks} hooks): {list}]])
--{count} is how many heroes are listed below it.
text("author.validator.coverage.heroes", [[Heroes ({count}) -- knacks each meets (standard: 3 or more)]])
--When the coverage check breaks. {error} is the technical error.
text("author.validator.coverage.failed", [[coverage failed: {error}]])

----------------------------------------------------------------------------
-- THE SCRIPT CHECKER: warnings about a script document
----------------------------------------------------------------------------
--Shown in the script checker and the builders, each after "line 12: " (or
--"'Document' line 12: "). Words in 'quotes' are copied from the script.
--Script words the author types (Options:, Arrive:, ## Round N, '### option',
--the encounter tag, tier1, PC chose ...) must stay exactly as they are:
--they tell the author what to write. {kind} is the entry's type word:
--opportunity, threat or obstacle.

--Optional features ("Unlock: Intelligence"). {feature} is the name written.
text("author.script.unlock.unknown_feature", [['Unlock: {feature}' names no feature of Encounter of the Week; ignored]])
text("author.script.unlock.under_option", [['Unlock: {feature}' is under the option '{option}'; it belongs in the section's own text (a feature is unlocked by the scene, not by a choice); ignored]])
text("author.script.unlock.outside_narrative", [['Unlock: {feature}' only works in a narrative beat; ignored]])
--{clause} is the rule as written.
text("author.script.intelligence_not_unlocked", [['{clause}' but nothing unlocks Intelligence; write 'Unlock: Intelligence' in a narrative beat or the party can never spend it]])

--Beats and their headings. {title} is the heading as written.
text("author.script.unknown_beat", [[unknown beat '{title}' (expected Montage, Narrative, Encounter, Delve: <name>, Part <n>: <title>, Results, Town Gate, Conclusion or Defeat); ignored]])
text("author.script.second_story", [[a second '# {title}'; only the first is used]])
--{part} is the part number already given.
text("author.script.second_part", [[a second '# {title}'; a script is one part, so only '# Part {part}' counts (give each part its own document)]])
text("author.script.section_outside_beat", [['## {title}' outside a montage or narrative beat; ignored]])

--Sub-documents linked into the script. {target} is the link as written,
--{problem} says what is wrong with it, {document} is a document's name.
text("author.script.include.problem", [['{target}' {problem}; the line is left as text]])
text("author.script.include.itself", [['{document}' includes itself; not included again]])
--{depth} is the most documents deep a link may go.
text("author.script.include.too_deep", [['{document}' is nested more than {depth} documents deep; not included]])

--Montage beats. {entry} is an opportunity's or threat's name, {option} an
--option's name, {directive} a party-size line such as "3-5 Players: -1 Threat".
text("author.script.montage.empty", [[montage has no opportunities or threats]])
text("author.script.montage.unknown_section", [['## {title}' is not 'Round N', 'Opportunity: ...' or 'Threat: ...'; ignored]])
text("author.script.montage.option_outside_entry", [['### {title}' outside an opportunity/threat; ignored]])
text("author.script.montage.consequence_on_opportunity", [[Consequence: on an opportunity ({entry}) is ignored]])
text("author.script.montage.scaling_misplaced", [[party-size directive '{directive}' must sit directly under its '## Round N' heading, above the entries; ignored]])
text("author.script.montage.scaling_not_understood", [[party-size directive '{directive}' not understood; ignored (use '3-5 Players: -1 Opportunity, -1 Threat')]])
--{drops} and {pool} are numbers, {kind} is opportunity or threat, {round} the round number.
text("author.script.montage.scaling_too_many", [['{directive}' drops {drops} {kind} but round {round} introduces only {pool} that may be removed]])
text("author.script.montage.scene_separator_misplaced", [['---' starts a scene only inside an opportunity or threat, above its first '### option'; ignored]])
text("author.script.montage.second_scene", [[{kind} '{entry}' already has a scene; this '---' is ignored]])
text("author.script.montage.entry_no_options", [[{kind} '{entry}' has no options]])
text("author.script.montage.option_no_rules", [[option '{option}' has no power roll and no rules (write '|Name: Characteristic' and tiers, or '|' clause lines for an option with no roll)]])
--{threat} is the threat's name.
text("author.script.montage.threat_no_consequence", [[threat '{threat}' has no Consequence:]])
--{clause} is the rule as written; {table} the dice table it names.
text("author.script.montage.roll_table_unknown", [['{clause}' names no dice table of this entry (write '|{table}: 1d6' and its rows in the entry)]])
text("author.script.montage.unlock_unknown_entry", [['{clause}' names no '(Locked)' opportunity or threat of this montage]])
text("author.script.montage.test_mod_unknown_option", [['{clause}' names no '### option' of this montage]])
text("author.script.montage.locked_never_unlocked", [[{kind} '{entry}' is (Locked) but nothing unlocks it]])

--Power rolls, riders and knacks. {roll} is the roll's name, {rider} a rider
--line or its type (Edge, Bane...), {knack} a knack's requirement
--("you can fly"), {problem} what is wrong with a requirement.
text("author.script.roll.bad_header", [['|' line is not a power roll header (|Name: Attr); ignored]])
--{tiers} is how many tier lines there are.
text("author.script.roll.too_few_tiers", [[power roll '{roll}' has {tiers} tier lines (need 3, optionally 4); ignored]])
text("author.script.roll.outside_option", [[power roll '{roll}' is not under a '### option'; ignored]])
text("author.script.roll.second_roll", [[option '{option}' already has a power roll; '{roll}' ignored]])
--{rules} is the option's rules line as written.
text("author.script.roll.after_rules", [[option '{option}' already has rules with no roll ('{rules}'); the power roll '{roll}' is ignored]])
--{tier} is the tier number.
text("author.script.roll.empty_teaser", [[tier {tier} of '{roll}' has an empty teaser before '=>'; shown in full]])
text("author.script.rider_no_requirement", [[rider '{rider}' has no requirement; ignored]])
text("author.script.option_rider_without_roll", [[option '{option}' has no roll, so its '{rider}' rider does nothing (only Allow / Secret gate an option with no roll)]])
text("author.script.knack_rider_without_roll", [[knack '{knack}' has no roll, so its '{rider}' rider does nothing (only Allow / Secret gate an option with no roll)]])
text("author.script.knack_no_rules", [[knack '{knack}' of option '{option}' has no roll and no '|' rules; ignored]])
text("author.script.knack_problem", [[knack '{knack}': {problem}]])
text("author.script.knack_on_delve_option", [[option '{option}' enters a delve; its knack '{knack}' is ignored]])

--Dice tables ("|Treasure: 1d6" and its rows). {table} is the table's name,
--{dice} its dice, {row} a row as written.
text("author.script.table.bad_row", [['|{row}' is not a table row (use '|1-2: result' or '|3: result'); ignored]])
text("author.script.table.second_table", [[{kind} '{entry}' already has a table named '{table}'; this one is ignored]])
text("author.script.table.misplaced", [[a dice table ('{table}: {dice}') belongs in a montage entry or under a delve's '## Chest'; ignored]])

--Scenes (lines after '---', and branches with if / else / end).
--{condition} is the condition as written, {problem} what is wrong with it,
--{text} a scene line as written.
text("author.script.scene.condition_problem", [[scene condition '{condition}': {problem}]])
text("author.script.scene.condition_tier", [[scene condition '{condition}' tests the tier, which is only known in the lines below an option's power roll; it is never true here]])
text("author.script.scene.no_if", [['{text}' has no 'if' above it; ignored]])
text("author.script.scene.end_without_if", [['end' has no 'if' above it; ignored]])
text("author.script.scene.if_not_closed", [['if' is never closed with 'end'; closed at the end of the scene]])
--{option} is the option name written after "PC chose"; {entry} the entry's name.
text("author.script.scene.chose_unknown_option", [['PC chose {option}' names no '### option' of {entry}]])
--What is wrong with a scene condition (shown after "scene condition '...': ").
text("author.script.condition.missing_paren", [[missing ')']])
text("author.script.condition.missing", [[a condition is missing]])
text("author.script.condition.unknown", [['{condition}' is not a condition (use 'PC speaks X', 'PC is X', 'PC has X', 'PC can X', 'PC was a X', 'PC chose X', 'tier1'-'tier3', 'crit', '<Track> is 2 or more' or 'Part 1 was a failure')]])
--{word} is the word that was not expected.
text("author.script.condition.unexpected", [[unexpected '{word}']])

--Narrative beats. {section} is a section's name, {rules} a rules line as
--written, {clause} a rule as written.
text("author.script.narrative.no_sections", [[narrative beat has no '## <section>' headings]])
text("author.script.narrative.option_outside_section", [['### {title}' outside a narrative '## section'; ignored]])
text("author.script.narrative.rules_outside_option", [['|{rules}' is not under a '### option'; ignored]])
text("author.script.narrative.no_mode", [[section '{section}' does not say 'Choose together:' or 'Choose individually:'; assuming together]])
text("author.script.narrative.names_montage_test", [['{clause}' is in a narrative beat; only a montage beat has entries and tests to name]])

--Encounter beats. {label} is the word before the colon, {instruction} the
--rest of the line, {victory} what follows "Victory:".
text("author.script.encounter.no_island", [=[encounter beat has no [[encounter]] island under it]=])
text("author.script.encounter.unknown_section", [['## {title}' in an encounter beat is not 'Reinforcements: <Name>'; ignored]])
text("author.script.encounter.victory_not_understood", [['Victory: {victory}' is not understood (write 'Victory: every enemy on the map is defeated' or 'Victory: every Dwarf on the map is defeated'); ignored]])
text("author.script.encounter.unknown_setup", [[unrecognized encounter setup instruction '{label}: {instruction}'; ignored]])

--Reinforcements ("## Reinforcements: <Name>"). {name} is the group's name,
--{arrive} what follows "Arrive:", {label} an unknown word before a colon.
text("author.script.reinforcements.arrive_not_understood", [[reinforcements '{name}': 'Arrive: {arrive}' is not understood (write 'Arrive: round 3', 'Arrive: rounds 2 and 4' or 'Arrive: every round from round 2')]])
text("author.script.reinforcements.second_arrive", [[reinforcements '{name}' already has an 'Arrive:' line; this one is ignored]])
text("author.script.reinforcements.enter_no_zone", [[reinforcements '{name}': 'Enter:' names no zone]])
text("author.script.reinforcements.unknown_label", [[reinforcements '{name}': '{label}:' is not 'Arrive:', 'Enter:' or 'Shout:'; ignored]])
text("author.script.reinforcements.no_arrive", [[reinforcements '{name}' have no 'Arrive:' line; they never arrive]])
text("author.script.reinforcements.no_island", [=[reinforcements '{name}' have no [[encounter]] island; nothing arrives]=])
text("author.script.reinforcements.no_enter", [[reinforcements '{name}' have no 'Enter:' zone; they arrive at their island's saved positions]])

--Delves ("# Delve: <Name>"). {delve} is the delve's name, {section} a
--"## Chest" / "## Continue" / ... heading, {obstacle} an obstacle's name.
text("author.script.delve.second_delve", [[a second '# Delve: {delve}'; only the first is used]])
text("author.script.delve.section_twice", [[delve '{delve}' already has a '## {section}'; this one is ignored]])
text("author.script.delve.unknown_section", [['## {title}' in a delve is not 'Obstacle: <name>', 'Chest', 'Continue', 'Leave', 'Forced Out' or 'End'; ignored]])
--{text} is the "Chest: every ..." line as written.
text("author.script.delve.chest_interval_bad", [['{text}' is not a usable chest interval; using every 1-2 obstacles]])
text("author.script.delve.chest_second_table", [[the chest already has a table; '{table}' ignored]])
text("author.script.delve.missing", [[option '{option}' enters the delve '{delve}', but there is no '# Delve: {delve}']])
text("author.script.delve.option_roll_ignored", [[option '{option}' enters a delve; its power roll is ignored]])
text("author.script.delve.no_obstacles", [[delve '{delve}' has no '## Obstacle: ...']])
text("author.script.delve.no_chest", [[delve '{delve}' has no '## Chest'; no treasure will turn up]])
text("author.script.delve.chest_no_table", [[delve '{delve}': '## Chest' has no dice table ('|Treasure: 1d6' then '|1-2: ...' rows)]])
text("author.script.delve.finish_unordered", [['## {section}' plays only in an in-order delve ('Order: in sequence'); a random delve ignores it]])
text("author.script.delve.section_options", [['## {section}' of delve '{delve}' is a scene; its '### options' are ignored]])
text("author.script.delve.obstacle_no_options", [[obstacle '{obstacle}' has no options]])
text("author.script.delve.option_no_rules", [[option '{option}' has no power roll and no rules]])
text("author.script.delve.option_nested_delve", [[option '{option}' is inside a delve already; 'Delve: {delve}' is ignored]])

----------------------------------------------------------------------------
-- THE MONTAGE BUILDER: the outcome picker's list of rules
----------------------------------------------------------------------------
--Each row of the picker reads "Group: Label". Short: list rows.

text("author.script.clause_group.reward", [[Reward]])
text("author.script.clause_group.cost", [[Cost]])
text("author.script.clause_group.next_encounter", [[Next encounter]])
text("author.script.clause_group.montage", [[Montage]])

text("author.script.clause.item", [[Gain an item]])
text("author.script.clause.herotoken", [[Hero tokens]])
text("author.script.clause.intelligence", [[Intelligence]])
text("author.script.clause.heal", [[Heal Stamina]])
text("author.script.clause.temphp", [[Temporary Stamina]])
text("author.script.clause.surges", [[Surges (next combat)]])
text("author.script.clause.recovery", [[Recovery value bonus]])
text("author.script.clause.damageboon", [[Rolled damage bonus]])
text("author.script.clause.immunityboon", [[Damage immunity]])
text("author.script.clause.ally", [[An ally joins]])
text("author.script.clause.stamina", [[Lose Stamina]])
text("author.script.clause.loserecovery", [[Lose Recoveries]])
text("author.script.clause.loseconsumable", [[Lose a consumable]])
text("author.script.clause.maxstamina", [[Maximum Stamina reduced]])
text("author.script.clause.malice", [[Malice for the Director]])
text("author.script.clause.initiative", [[Initiative]])
text("author.script.clause.nosurprise", [[Cannot be surprised]])
text("author.script.clause.fairinitiative", [[Fair roll for initiative]])
text("author.script.clause.knowstamina", [[Know monsters' Stamina]])
text("author.script.clause.revealzones", [[Reveal zones]])
text("author.script.clause.startzone", [[Extra starting zone]])
text("author.script.clause.revealobject", [[Reveal a map object]])
text("author.script.clause.vanquish", [[Vanquish the threat]])
text("author.script.clause.unlock", [[Unlock an entry]])
text("author.script.clause.testmod", [[Edge or bane on a test]])
text("author.script.clause.rolltable", [[Roll on a dice table]])

----------------------------------------------------------------------------
-- THE ENCOUNTER BUILDER: optional features
----------------------------------------------------------------------------

--What turning on Intelligence does. Shown as "Turns on {this}." under the
--feature's checkbox, so it starts lower-case and has no full stop.
text("author.script.feature.intelligence.summary", [[the party's shared Intelligence pool and the Tactical Preparation screen]])

----------------------------------------------------------------------------
-- THE BUILDERS: why an edit could not be made
----------------------------------------------------------------------------
--Shown after "Not changed: " when the builder cannot make an edit.

text("author.script_edit.place_not_in_document", [[that place is not in any document]])
text("author.script_edit.spans_documents", [[that text spans more than one document]])
text("author.script_edit.element_not_in_document", [[that element is not in any document]])
--{tier} is the tier number.
text("author.script_edit.tier_no_line", [[tier {tier} has no line to write]])
text("author.script_edit.riders_outside_roll", [[this option has rider lines outside its roll block; edit it as text]])
text("author.script_edit.rules_split", [[these rules are split up; edit them as text]])

--Why text typed into a description box cannot be used as it is (it would
--be read as part of the script instead of as prose).
text("author.script_edit.prose.heading", [[a line starts with '#', which would start a new heading]])
text("author.script_edit.prose.rules_line", [[a line starts with '|', which is a rules line]])
text("author.script_edit.prose.scene_line", [[a '---' line would start a scene]])
text("author.script_edit.prose.tag_line", [=[a [[tag]] line]=])
text("author.script_edit.prose.keyword_line", [[a line starting 'Consequence:' or 'Options:' means something else]])

----------------------------------------------------------------------------
-- THE BUILDERS: starter text for a new beat or section
----------------------------------------------------------------------------
--Placeholder story written into the script when the author adds a new beat
--or section; the author replaces it. Each is ONE line: no line breaks, and
--it must not start with '#', '|' or '---'.

--A new narrative beat: its intro, one section with a choice of two roads.
text("author.script_edit.starter.narrative.intro", [[The heroes gather before the road ahead.]])
--The section's heading.
text("author.script_edit.starter.narrative.section", [[The Road Ahead]])
text("author.script_edit.starter.narrative.section_text", [[The road forks beneath a lightning-split oak.]])
--The question after "Choose together: ".
text("author.script_edit.starter.narrative.prompt", [[Which way do you go?]])
--The two options' names and descriptions.
text("author.script_edit.starter.narrative.option1", [[The high road]])
text("author.script_edit.starter.narrative.option1_text", [[The ridge path is longer but safer.]])
text("author.script_edit.starter.narrative.option2", [[The low road]])
text("author.script_edit.starter.narrative.option2_text", [[The valley path is quick and dark.]])
--A new montage beat's intro.
text("author.script_edit.starter.montage.intro", [[The road ahead is long and dangerous.]])
--A new narrative section: its text, the question after "Choose together: ",
--and its two options' names.
text("author.script_edit.starter.section.text", [[Describe what happens.]])
text("author.script_edit.starter.section.prompt", [[What do you do?]])
text("author.script_edit.starter.section.option1", [[Press on]])
text("author.script_edit.starter.section.option2", [[Turn back]])
