local mod = dmhub.GetModLoading()

--The words of the Hero Builder, Level up and the Skills & Languages component, in the main game and in Encounter of the Week.
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

local text = UIText.Define("HeroBuilderText")

----------------------------------------------------------------------------
-- THE HERO BUILDER: the title row
-- (Draw Steel Character Builder/HeroBuilder.lua)
----------------------------------------------------------------------------

--The big heading at the top left: a Hero without a class yet, and one with.
text("herobuilder.title.create", [[Create Your Hero]])
text("herobuilder.title.edit", [[Edit Your Hero]])
--Before the Level dropdown, under the heading. Short.
text("herobuilder.title.build_at_level", [[Build at Level]])
--Before the slow-start dropdown, beside the Level at Level 1. Short.
text("herobuilder.title.slow_start", [[Slow start]])
--The Undo button at the top right. Short: a button.
text("herobuilder.title.undo", [[Undo]])
--Its tooltip during a combat turn, when it is off.
text("herobuilder.title.undo_off", [[Undo is off during a combat turn.]])
--Its tooltip otherwise. {change} is the undo list's words for the last
--change (the "undo list" entries below).
text("herobuilder.title.undo_tooltip", [[Undo: {change}]])
--The button that leaves the Builder for the Hero sheet. Short: a button.
text("herobuilder.title.back_to_sheet", [[Back to the sheet]])

--The slow start's four rungs: the slow-start dropdown, and Level up's pills
--and page headings for them.
text("herobuilder.rung.first", [[First Encounter]])
text("herobuilder.rung.second", [[Second Encounter]])
text("herobuilder.rung.third", [[Third Encounter]])
text("herobuilder.rung.fourth", [[Fourth Encounter]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the stepper (the row of step pills)
----------------------------------------------------------------------------

--The names of the Builder's own steps, after the rules' steps. Each is a
--pill's name and its page's heading. Short.
text("herobuilder.steps.other", [[Other choices]])
text("herobuilder.steps.review", [[Review]])

--The small line under a pill. Short: a few words.
--Review's pill.
text("herobuilder.pill.before_finish", [[Before you finish]])
--A step with a pick that is no longer valid.
text("herobuilder.pill.needs_attention", [[Needs attention]])
--Skills & Languages when done: {count} is how many skills and languages are picked.
text("herobuilder.pill.picked", [[{count} picked]])
--Level up: a page with no choices on it.
text("herobuilder.pill.nothing_to_choose", [[Nothing to choose]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: states
-- The short words at the right of a section heading, under a pill and on
-- the picks pane's blocks.
----------------------------------------------------------------------------

--{count} is how many picks are still to make.
text("herobuilder.status.left", [[{count} to choose]])
--A choice with picks still to make, before it says how many.
text("herobuilder.status.to_choose", [[To choose]])
text("herobuilder.status.done", [[Done]])
--The complication step, and the inciting incident (story only).
text("herobuilder.status.optional", [[Optional]])
--Complications, while the Hero has none.
text("herobuilder.status.none_chosen", [[None chosen]])
--Ancestry's purchased traits: {spent} of {total} points spent.
text("herobuilder.status.points_spent", [[{spent} of {total} spent]])
--Where a pick would show, while nothing is picked.
text("herobuilder.status.not_chosen", [[Not chosen]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: each step's lead (the line under the page's heading)
----------------------------------------------------------------------------

text("herobuilder.lead.ancestry", [[Where your hero comes from: a signature trait, and points to spend on more.]])
text("herobuilder.lead.culture", [[Where your hero grew up: an environment, an organization and an upbringing, and a language. Pick a typical culture or build your own from three aspects.]])
text("herobuilder.lead.career", [[What your hero did before adventuring. It gives skills, languages, a perk and an inciting incident.]])
--The Class step before a class is picked.
text("herobuilder.lead.class", [[Your class is your hero's role in a fight and the heroic resource they build. Hover any class to see it.]])
--The Class step once a class is picked.
text("herobuilder.lead.class_picked", [[Your class is your hero's role in a fight and the heroic resource they build. Hover a class's (i) to compare it.]])
text("herobuilder.lead.skills", [[Every skill and language choice from the other steps, in one place. Pick skills; each one counts toward a choice it fits, and anything that no longer fits dims.]])
text("herobuilder.lead.complication", [[Optional. A complication gives a benefit and a drawback, and a hook for the Director.]])
--Other choices: choices that items and other features ask for.
text("herobuilder.lead.other", [[Choices your items and other features ask you to make.]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the step pages' sections and cards
----------------------------------------------------------------------------

--The heading over the main pick on Ancestry, Career and Class.
text("herobuilder.section.your_ancestry", [[Your ancestry]])
text("herobuilder.section.your_career", [[Your career]])
text("herobuilder.section.your_class", [[Your class]])
--Culture's heading over its ready-made cultures.
text("herobuilder.section.typical_cultures", [[Typical cultures]])
--The second line on the culture card that goes with the Hero's ancestry.
text("herobuilder.culture.own", [[Your ancestry's culture]])
--The Complication step's heading.
text("herobuilder.section.complications", [[Complications]])
--The first complication card: no complication, and its second line.
text("herobuilder.complication.none_name", [[No complication]])
text("herobuilder.complication.none_line", [[You can add one later.]])
--The rules note under the Complications heading.
text("herobuilder.complication.hint", [[The rules give one complication; your Director may allow more.]])
--The same note where a Hero may hold only one complication (Encounter of the Week).
text("herobuilder.complication.hint_one", [[A Hero has one complication. Picking another replaces it.]])
--Ancestry's purchased traits: the line under the heading. {count} is the points in all.
text("herobuilder.section.points_to_spend", [[{count} points to spend]])

--The buttons that pick at random. Short: a button.
text("herobuilder.roll.complication", [[Roll a complication]])
text("herobuilder.roll.incident", [[Roll an inciting incident]])
--What a random complication's dice roll says it is for, in the roll and the chat.
text("herobuilder.roll.complication_description", [[Complication]])
--The inciting incident's line under its heading. {career} is the career's name.
text("herobuilder.incident.note", [[Pick from the {career}'s table, or roll.]])
--Under the incident cards once one is picked.
text("herobuilder.incident.saved", [[Saved to your notes.]])

--The search field on a long list (its grey words until something is typed).
text("herobuilder.search.cultures", [[Search cultures]])
text("herobuilder.search.complications", [[Search complications]])
text("herobuilder.search.languages", [[Search languages]])
text("herobuilder.search.perks", [[Search perks]])
text("herobuilder.search.kits", [[Search kits]])
--Any other list. {name} is the choice's name in lower case.
text("herobuilder.search.row", [[Search {name}]])
--The search field's tooltip.
text("herobuilder.search.tooltip", [[Type to filter. ! or - leaves a word out, > matches the start, < the end.]])

--A card's tooltip when it is picked.
text("herobuilder.card.picked_hover", [[Picked. Click to drop it.]])
--A purchased trait's cost, before its words and a dot. {count} is the points.
text("herobuilder.card.points.one", [[{count} point]])
text("herobuilder.card.points.other", [[{count} points]])
--A card another choice already holds: its second line and tooltip. {step}
--is the step that holds it.
text("herobuilder.card.taken_on", [[Taken on {step}]])
--A purchased trait that costs more than is left: its tooltip.
text("herobuilder.card.no_points", [[Not enough points left. Remove a trait to free some.]])

--A choice whose pick is no longer valid: the warning in its red row, and
--the button there (also on a pick kept for a higher Level). Short: a button.
text("herobuilder.stale.warning", [[A choice here is no longer valid. Choose again, or use Fill in the rest.]])
text("herobuilder.row.remove", [[Remove]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: characteristics and kits (the Class step)
----------------------------------------------------------------------------

--The line under the characteristics heading, when the class sets none.
text("herobuilder.chars.note_none", [[To choose your characteristics, choose an array, then drag or click two to swap.]])
--The same line when the class sets some. {fixed} is a list of
--"herobuilder.chars.set_to" lines joined by "herobuilder.list.and".
text("herobuilder.chars.note_fixed", [[Your class has {fixed}. To choose your other characteristics, choose an array, then drag or click two to swap.]])
--One part of {fixed}. {names} are the characteristics, {value} their score ("+2").
text("herobuilder.chars.set_to", [[{names} set to {value}]])
--Before the array buttons. Short.
text("herobuilder.chars.array", [[Array]])
--Small capitals under a characteristic the class sets, and its tooltip.
text("herobuilder.chars.set_by_class", [[SET BY CLASS]])
text("herobuilder.chars.set_by_class_tooltip", [[Set by your class.]])

--The Beastheart's companion switch under Kits: its label, the name of the
--flat bonus beside the kit's, and the undo list's words for a switch.
text("herobuilder.kit.companion_melee", [[Companion melee]])
text("herobuilder.kit.companion_default", [[Companion Default]])
text("herobuilder.kit.companion_undo", [[Choose companion melee bonus]])

--The Class page's heading over each Level's choices. {ordinal} is "2nd" and so on.
text("herobuilder.class.level_heading", [[{ordinal}-Level Features]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: You gain (what a step gives without a choice)
----------------------------------------------------------------------------

--The heading, on the page and in the picks pane.
text("herobuilder.gain.title", [[You gain]])
--The link at its right to the Skills & Languages step.
text("herobuilder.gain.link", [[Choose these on Skills & Languages]])
--The muted word after a name in the pane, and the label of the row for an
--outright skill or language.
text("herobuilder.gain.tag_skill", [[Skill]])
text("herobuilder.gain.tag_language", [[Language]])
--The muted words after the ancestry's signature trait.
text("herobuilder.gain.tag_signature_trait", [[Signature trait]])
--The Class step's pane, when its grants come at more than one Level: a
--heading per Level. {ordinal} is "1st", "4th" and so on.
text("herobuilder.gain.level_heading", [[{ordinal} Level]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the (i) card (an option in full)
----------------------------------------------------------------------------

--The small capitals over a main pick's name.
text("herobuilder.kicker.ancestry", [[Ancestry]])
text("herobuilder.kicker.culture", [[Culture]])
text("herobuilder.kicker.career", [[Career]])
text("herobuilder.kicker.class", [[Class]])
text("herobuilder.kicker.complication", [[Complication]])
--Over a class its data marks as a master class.
text("herobuilder.kicker.master_class", [[Master Class]])
--The line under a class's name. {resource} is its heroic resource ("Focus").
text("herobuilder.detail.heroic_resource", [[Heroic resource: {resource}]])
--The small capitals over a class's or subclass's features, and over an
--ancestry's signature trait.
text("herobuilder.detail.first_level_features", [[1st-level features]])
text("herobuilder.detail.signature_trait", [[Signature trait]])
--The two tabs on a pinned ancestry card. Short: tabs in small capitals.
text("herobuilder.detail.description_tab", [[Description]])
text("herobuilder.detail.lore_tab", [[Lore]])
--The small capitals over an ability that has no type of its own, and over
--a feature.
text("herobuilder.detail.ability", [[Ability]])
text("herobuilder.detail.feature", [[Feature]])
--The small capitals over a skill: {group} is its group ("Exploration"); the
--other is for a skill with no group.
text("herobuilder.detail.group_skill", [[{group} skill]])
text("herobuilder.detail.skill", [[Skill]])
--The small capitals over a language, and the label of its speakers.
text("herobuilder.detail.language", [[Language]])
text("herobuilder.detail.spoken_by", [[Spoken by]])
--Under a hover card too long to show whole.
text("herobuilder.detail.pin_hint", [[Click the (i) to pin this and scroll.]])
--A kit's card: the small capitals over its parts, then one line per bonus.
--{n} is a number; {bonus} is a damage bonus by tier ("+2/+2/+2"); {type} is
--the kind of damage ("Melee Weapon", "Supernatural").
text("herobuilder.kit.equipment", [[Equipment]])
text("herobuilder.kit.bonuses", [[Bonuses]])
text("herobuilder.kit.signature_ability", [[Signature ability]])
text("herobuilder.kit.maneuver", [[Maneuver]])
text("herobuilder.kit.stamina", [[<b>Stamina Bonus:</b> +{n} per echelon]])
text("herobuilder.kit.speed", [[<b>Speed Bonus:</b> +{n}]])
text("herobuilder.kit.distance", [[<b>Distance Bonus:</b> +{n}]])
text("herobuilder.kit.reach", [[<b>Reach Bonus:</b> +{n}]])
text("herobuilder.kit.area", [[<b>Area Bonus:</b> +{n}]])
text("herobuilder.kit.disengage", [[<b>Disengage Bonus:</b> +{n}]])
text("herobuilder.kit.stability", [[<b>Stability Bonus:</b> +{n}]])
text("herobuilder.kit.damage", [[<b>{type} Damage Bonus:</b> {bonus}]])
--A culture's (i) card: after its description, the line before the three
--aspects it sets, and the last line. {language} is the culture's language.
text("herobuilder.culture.detail_sets", [[Taking this culture sets:]])
text("herobuilder.culture.detail_language", [[**Language:** {language}]])

--The Quick Build star's tooltip, and its line on a card.
text("herobuilder.quick_build.tip", [[The book's Quick Build choice]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the picks pane (the column on the right)
----------------------------------------------------------------------------

--The pane's heading. {step} is the step's name, such as "Class".
text("herobuilder.pane.title", [[Your {step}]])

--What a fresh step will ask, one block each, before its main pick.
text("herobuilder.outline.ancestry", [[Ancestry]])
text("herobuilder.outline.signature_trait", [[Signature trait]])
text("herobuilder.outline.purchased_traits", [[Purchased traits]])
text("herobuilder.outline.culture", [[Culture]])
text("herobuilder.outline.environment", [[Environment]])
text("herobuilder.outline.organization", [[Organization]])
text("herobuilder.outline.upbringing", [[Upbringing]])
text("herobuilder.outline.language", [[Language]])
text("herobuilder.outline.career", [[Career]])
text("herobuilder.outline.perk", [[Perk]])
text("herobuilder.outline.inciting_incident", [[Inciting incident]])
text("herobuilder.outline.class", [[Class]])
text("herobuilder.outline.subclass", [[Subclass]])
text("herobuilder.outline.characteristics", [[Characteristics]])
text("herobuilder.outline.kit", [[Kit]])
text("herobuilder.outline.heroic_abilities", [[Heroic abilities]])
--Under the blocks after the first. {pick} is one of the four below.
text("herobuilder.outline.waits", [[After you choose {pick}]])
--A step's main pick, as "After you choose {pick}" and the footer's
--"Still to choose here" name it.
text("herobuilder.outline.after_ancestry", [[an ancestry]])
text("herobuilder.outline.after_culture", [[a culture]])
text("herobuilder.outline.after_career", [[a career]])
text("herobuilder.outline.after_class", [[a class]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: Skills & Languages, and Review
----------------------------------------------------------------------------

--The step's two headings; also how the footer and Fill in the rest name a
--skill or language choice.
text("herobuilder.skills.skills", [[Skills]])
text("herobuilder.skills.languages", [[Languages]])
--The pane before any step has given a skill or language choice.
text("herobuilder.skills.empty", [[Your skill and language choices gather here as you choose an ancestry, culture, career and class.]])

--Review's banner. {hero} is the Hero's name, or "herobuilder.review.your_hero".
text("herobuilder.review.banner", [[This is {hero} as the sheet will show them. Hover anything to check it; Finish returns to the sheet.]])
text("herobuilder.review.your_hero", [[your Hero]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: changing a main pick (the confirm)
----------------------------------------------------------------------------

--The heading, by step.
text("herobuilder.confirm.title_ancestry", [[Change ancestry?]])
text("herobuilder.confirm.title_career", [[Change career?]])
text("herobuilder.confirm.title_class", [[Change class?]])
--Over the list of what goes. {from} is the current pick's name.
text("herobuilder.confirm.body", [[These choices belong to the {from} and will be cleared:]])
--A line in that list when the culture follows the ancestry. {culture} is the new culture.
text("herobuilder.confirm.culture_follows", [[Culture: becomes {culture}, clearing its skill choices]])
--Under the list.
text("herobuilder.confirm.note", [[Your other choices stay. You can undo this.]])
--The two buttons. Short. {from} is the current pick's name.
text("herobuilder.confirm.keep", [[Keep {from}]])
text("herobuilder.confirm.change_ancestry", [[Change ancestry]])
text("herobuilder.confirm.change_career", [[Change career]])
text("herobuilder.confirm.change_class", [[Change class]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the undo list
-- The words the undo list (and Undo's tooltip) shows for each change.
----------------------------------------------------------------------------

text("herobuilder.undo.change_ancestry", [[Change ancestry]])
text("herobuilder.undo.change_culture", [[Change culture]])
text("herobuilder.undo.change_career", [[Change career]])
text("herobuilder.undo.change_class", [[Change class]])
text("herobuilder.undo.no_complication", [[No complication]])
text("herobuilder.undo.change_complications", [[Change complications]])
text("herobuilder.undo.make_choice", [[Make a choice]])
text("herobuilder.undo.drop_pick", [[Drop a pick]])
text("herobuilder.undo.change_skills", [[Change skills]])
text("herobuilder.undo.change_languages", [[Change languages]])
text("herobuilder.undo.fill", [[Fill in the rest]])
--Changing the Level or the slow-start rung in the title row.
text("herobuilder.undo.build_at_level", [[Build at Level]])
text("herobuilder.undo.slow_start", [[Slow start]])
--Level up's Cancel. {level} is the Level being taken.
text("herobuilder.undo.cancel_level", [[Cancel Level {level}]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: the footer
----------------------------------------------------------------------------

--The footer's buttons. Short: buttons. Next reads Skip for now while the
--step has picks left, and Finish on the last step; Level up's Back is Cancel.
text("herobuilder.footer.back", [[Back]])
text("herobuilder.footer.next", [[Next]])
text("herobuilder.footer.skip", [[Skip for now]])
text("herobuilder.footer.finish", [[Finish]])
text("herobuilder.footer.cancel", [[Cancel]])
text("herobuilder.footer.fill", [[Fill in the rest]])

--The message line. {list} is links, joined with commas and
--"herobuilder.list.and"; on Review they are the steps with something left.
text("herobuilder.footer.still_to_choose", [[Still to choose here: {list}.]])
text("herobuilder.footer.still_to_do", [[Still to do: {list}.]])
--Review, when nothing is left.
text("herobuilder.footer.all_chosen", [[Everything is chosen.]])
--The last item of a long list. {count} is how many more there are.
text("herobuilder.footer.more", [[{count} more]])
--A choice in the list whose name another shares. {item} is its name.
text("herobuilder.footer.item_level", [[{item} (Level {level})]])
--The Appearance step's two links.
text("herobuilder.footer.appearance_name", [[Name]])
text("herobuilder.footer.appearance_art", [[Art]])
--After Fill in the rest, when it found nothing, and when it filled {count} choices.
text("herobuilder.footer.nothing_to_fill", [[Nothing left to fill.]])
text("herobuilder.footer.filled.one", [[Filled {count} choice.]])
text("herobuilder.footer.filled.other", [[Filled {count} choices.]])
--When a change fails. {error} is what went wrong.
text("herobuilder.footer.error", [[Something went wrong: {error}]])

--Joins the last two items of a list ("Might and Reason"). Keep the spaces
--either side.
text("herobuilder.list.and", [[ and ]])

----------------------------------------------------------------------------
-- THE HERO BUILDER: Fill in the rest (its pop-up)
----------------------------------------------------------------------------

--The heading. {noun} is one of the three nouns below.
text("herobuilder.fill.title_this", [[Fill in the rest of this {noun}]])
text("herobuilder.fill.title_every", [[Fill in the rest of every {noun}]])
--The button that switches between the two. Short.
text("herobuilder.fill.scope_this", [[This {noun}]])
text("herobuilder.fill.scope_every", [[Every {noun}]])
--What it fills: a step, in Level up a Level, or a page while the slow
--start's pages wait too.
text("herobuilder.fill.noun_step", [[step]])
text("herobuilder.fill.noun_level", [[Level]])
text("herobuilder.fill.noun_page", [[page]])
--The two buttons. Short.
text("herobuilder.fill.cancel", [[Cancel]])
text("herobuilder.fill.apply", [[Fill these]])
--The note under the list. {kept} is the second line, which shows alone
--when nothing is a Quick Build pick. The first follows a star.
text("herobuilder.fill.note_star", [[marks the book's Quick Build choices; the rest are random choices that fit. {kept}]])
text("herobuilder.fill.note_kept", [[Your own choices are kept, you can use Undo to revert these changes.]])

--The list's labels for a step's main pick. "follows" is the culture that
--comes with a new ancestry; "uncomplicate" is No complication.
text("herobuilder.fill.ancestry", [[Ancestry]])
text("herobuilder.fill.culture", [[Culture]])
text("herobuilder.fill.career", [[Career]])
text("herobuilder.fill.class", [[Class]])
text("herobuilder.fill.follows", [[Culture]])
text("herobuilder.fill.uncomplicate", [[Complication]])
--A choice whose name another shares. {label} is its name.
text("herobuilder.fill.label_level", [[{label} (Level {level})]])
--A pick that goes. {pick} is its name, or "herobuilder.fill.removes_unnamed".
text("herobuilder.fill.removes", [[Removes {pick} (no longer offered)]])
text("herobuilder.fill.removes_unnamed", [[a choice]])
--The Appearance step's rows: the name and the art. {source} is the class
--or ancestry the art comes from.
text("herobuilder.fill.name", [[Name]])
text("herobuilder.fill.art", [[Art]])
text("herobuilder.fill.art_from", [[{source} art]])

----------------------------------------------------------------------------
-- LEVEL UP: the Builder on a Hero who has gained a Level
----------------------------------------------------------------------------

--A Level's pill. {ordinal} is "2nd" and so on.
text("herobuilder.levelup.step_title", [[{ordinal} Level]])
--The page's heading: a Level's, and a slow-start rung's ({rung} is the
--rung's name, such as "Second Encounter").
text("herobuilder.levelup.heading", [[{ordinal}-Level Features]])
text("herobuilder.levelup.rung_heading", [[{rung} Features]])
--After the Hero's name in the title row. {level} is the page's Level; a
--rung's page adds a dot and the rung's name.
text("herobuilder.levelup.level", [[Level {level}]])
--What the page's features are called inside the lines below.
text("herobuilder.levelup.features", [[{ordinal}-level features]])
text("herobuilder.levelup.rung_features", [[{rung} features]])
--The page's lead: with choices to make, and without them (a rung's page,
--then a Level's).
text("herobuilder.levelup.lead", [[These are your {features}. Each choice saves as you make it.]])
text("herobuilder.levelup.lead_nothing_rung", [[These are your {features}. There is nothing to choose here.]])
text("herobuilder.levelup.lead_nothing_level", [[These are your {features}. There is nothing to choose at this Level.]])
--The pane's heading.
text("herobuilder.levelup.pane_title", [[Your {features}]])
--The Class page's heading over picks kept for a Level above the Hero's.
text("herobuilder.kept.title", [[Kept for Level {level}]])
--The first line of You gain. {amount} is the Stamina the Level adds.
text("herobuilder.levelup.stamina", [[Stamina +{amount}]])
--A manual Level up's note. The second line follows only when the Hero lacks
--the experience for the Level.
text("herobuilder.levelup.manual_note", [[Your Level rises to {level} when you finish.]])
text("herobuilder.levelup.manual_xp_note", [[Note: manual level adjustment does not increase your XP. Automatic levelling upon respite is based on the standard amount of XP for levelling.]])
--The Finish button (and its undo list words). Short: a button.
text("herobuilder.levelup.finish_level", [[Finish Level {level}]])
text("herobuilder.levelup.finish_rung", [[Finish {rung}]])

--Ordinal numbers, as in "2nd Level". {number} is the number.
text("herobuilder.ordinal.st", [[{number}st]])
text("herobuilder.ordinal.nd", [[{number}nd]])
text("herobuilder.ordinal.rd", [[{number}rd]])
text("herobuilder.ordinal.th", [[{number}th]])

----------------------------------------------------------------------------
-- SKILLS & LANGUAGES: the component (the Builder's step, Level up's skills
-- and the Hero sheet's Skills and Languages windows)
-- (Draw Steel Character Builder/HeroSkillsLanguages.lua)
----------------------------------------------------------------------------

--The headings. Shown in small capitals.
text("heroskills.heading.your_choices", [[Your choices]])
text("heroskills.heading.skills", [[Skills]])
text("heroskills.heading.languages", [[Languages]])

--The buttons under Your choices. Short.
text("heroskills.add.skill", [[Add a skill]])
text("heroskills.add.language", [[Add a language]])

--A row in Your choices names the step it comes from, then the item
--("Career: Farmer"). The step names:
text("heroskills.kind.ancestry", [[Ancestry]])
text("heroskills.kind.culture", [[Culture]])
text("heroskills.kind.career", [[Career]])
text("heroskills.kind.class", [[Class]])
text("heroskills.kind.subclass", [[Subclass]])
text("heroskills.kind.complication", [[Complication]])
text("heroskills.kind.kit", [[Kit]])
text("heroskills.kind.title", [[Title]])
text("heroskills.kind.perk", [[Perk]])
--What the rules give every Hero comes from Everyone.
text("heroskills.kind.everyone", [[Everyone]])
--A row's item when nothing names it, and a source with no name.
text("heroskills.row.choice", [[Choice]])
text("heroskills.source.unknown", [[Unknown]])
--Rows that share a name add their Level. {title} is the row's name.
text("heroskills.row.title_with_level", [[{title} (Level {level})]])
--A row added by hand: its name (also what its pick is "from"), and its
--second line.
text("heroskills.row.added_by_hand", [[Added by hand]])
text("heroskills.row.custom_feature", [[A custom feature]])
--A row replacing a skill granted twice: its name, and its second line
--({skill} is the skill granted twice).
text("heroskills.row.duplicate_skill", [[Duplicate skill]])
text("heroskills.row.duplicate_line", [[{skill} twice: choose another skill]])
--A row with nothing picked.
text("heroskills.row.not_chosen", [[Not chosen]])

--A row's second line: what the choice takes. A language choice:
text("heroskills.grant.a_language", [[A language]])
--{number} is one of the number words below.
text("heroskills.grant.n_languages", [[{number} languages]])
--A skill choice from any group, or naming skills:
text("heroskills.grant.a_skill", [[A skill]])
text("heroskills.grant.n_skills", [[{number} skills]])
--A skill choice from groups. {groups} is the groups in lower case, joined
--with "heroskills.list.or"; {article} is "A" or "An" (below), in lower case
--after named skills ("Music, Perform or a crafting skill").
text("heroskills.grant.n_group_skills", [[{number} {groups} skills]])
text("heroskills.grant.a_group_skill", [[{article} {groups} skill]])
--The words those lines start with. The Builder's You gain shows them in
--lower case after the item ("Farmer: two skills").
text("heroskills.number.one", [[One]])
text("heroskills.number.two", [[Two]])
text("heroskills.number.three", [[Three]])
text("heroskills.number.four", [[Four]])
text("heroskills.number.five", [[Five]])
text("heroskills.number.six", [[Six]])
text("heroskills.article.a", [[A]])
text("heroskills.article.an", [[An]])

--Join the last two items of a list. Keep the spaces either side.
text("heroskills.list.and", [[ and ]])
text("heroskills.list.or", [[ or ]])

--A row's state at its right. {count} is how many picks are left.
text("heroskills.status.left", [[{count} left]])
text("heroskills.status.done", [[Done]])
--A pick the Hero also has some other way. {sources} is where from.
text("heroskills.status.also_from", [[Also from {sources}]])

--Over the chips while a row is selected. {row} is the row's name.
text("heroskills.filter.choices_for", [[Choices for <b>{row}</b>]])
--The button that clears that selection. Short.
text("heroskills.filter.show_all", [[Show all]])

--The small words on a chip: a skill or language the Hero has already, and a
--dead language's tag.
text("heroskills.chip.known", [[known]])
text("heroskills.chip.dead", [[Dead]])
--A chip's tooltips. {sources} is where the Hero has it from.
text("heroskills.chip.known_from", [[You have this from {sources}.]])
--Under a skill group, and on its chips, when no choice takes it. {group}
--is the group ("Lore"), or "heroskills.chip.no_open_group" when it has none.
text("heroskills.chip.no_open_choice", [[No open {group} choice]])
text("heroskills.chip.no_open_group", [[skill]])
text("heroskills.chip.no_open_language", [[No open language choice]])
--With a row selected. {row} is the row's name.
text("heroskills.chip.not_offered", [[{row} doesn't offer this skill.]])
text("heroskills.chip.row_full", [[{row} is full. Drop a skill first.]])
--The Quick Build star's line.
text("heroskills.chip.quick_build", [[The book's Quick Build choice]])

--A skill's tooltip for a power that singles it out. {feature} is the
--power's name (or "heroskills.mark.a_feature"), {effect} one of the three below.
text("heroskills.mark.gives", [[Your {feature} gives you {effect} with this skill.]])
text("heroskills.mark.a_feature", [[A feature]])
text("heroskills.mark.edge", [[an edge]])
text("heroskills.mark.double_edge", [[a double edge]])
text("heroskills.mark.bane", [[a bane]])

--Under the chips: what the Hero has already. {list} is "Name (where from)",
--joined with commas.
text("heroskills.known.line", [[Known already: {list}.]])

--The languages' search field (its grey words), and its tooltip.
text("heroskills.search.placeholder", [[Search languages]])
text("heroskills.search.tooltip", [[Type to filter. ! or - leaves a word out, > matches the start, < the end.]])

--The Hero sheet's Skills card, at its foot: where the skills come from
--({sources} is the steps in lower case and other names), and the skills
--added by hand.
text("heroskills.card.from", [[From {sources}.]])
text("heroskills.card.by_hand", [[{skills} added by hand.]])
