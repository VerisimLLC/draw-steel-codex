local mod = dmhub.GetModLoading()

--Encounter of the Week: the words of the Great Forge -- the town's
--10000-point building project, raised with the Tinkerer's Guild (a cabal of
--Gnome tinkerers): first planned, then built.
--
--Code: EotwDowntime.lua (the project), EncounterOfTheWeek.lua (the map).
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * {name} is filled in by the game (a hero's name, a number, ...). Keep every
--    one, spelled exactly as it is; you may move it anywhere in the sentence.
--  * A line break inside [[ ]] is a line break on screen.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--EVERY LINE BELOW IS A PLACEHOLDER DRAFT (2026-11-10), waiting for real words.
--
--Code: UIText (DMHub Utils/UIText.lua). Design: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The Great Forge".

local text = UIText.Define("EotwTextGreatForge")

----------------------------------------------------------------------------
-- THE MAP: the location's marker and heading
----------------------------------------------------------------------------

--While the town is still building it. The label is the name on the map
--marker (1-3 words); the title and tagline head the screen when it is opened.
text("eotw.locations.great_forge_site.label", [[Great Forge Construction]])
text("eotw.locations.great_forge_site.title", [[The Great Forge Construction]])
text("eotw.locations.great_forge_site.tagline", [[The Tinkerer's Guild has agreed to help build the Great Forge. Lead them in building it so treasures may be forged.]])

--Once it is built.
text("eotw.locations.great_forge.label", [[Great Forge]])
--The map label while demons besiege it.
text("eotw.locations.great_forge_siege.label", [[Great Forge -- Under Siege!]])
text("eotw.locations.great_forge.title", [[The Great Forge]])
text("eotw.locations.great_forge.tagline", [[The Great Forge, a place to forge treasures of great value]])

----------------------------------------------------------------------------
-- THE BUILDING SITE: the card above the project
----------------------------------------------------------------------------

--A short call to action, shown large in italics.
text("downtime.great_forge_site.intro", [[Join the Tinkerer's Guild in building the Great Forge!]])
--One or two sentences on what it will be.
text("downtime.great_forge_site.community", [[The gnomes of the Tinkerer's Guild scurry back and forth, building the Forge. Help them in doing so!]])

----------------------------------------------------------------------------
-- THE PROJECT: Build the Great Forge
----------------------------------------------------------------------------

text("downtime.projects.build_great_forge.title", [[Build the Great Forge]])
--Where it is worked on, as in "Go to the Great Forge Construction to work on it."
text("downtime.projects.build_great_forge.place", [[the Great Forge Construction]])
--Shown under its cost.
text("downtime.projects.build_great_forge.benefit", [[The Great Forge opens for all the heroes of Blackbottom.]])
--The line under the title, and the same line once it is finished.
text("downtime.projects.build_great_forge.blurb", [[This is a Community Project, everyone builds this together!]])
text("downtime.projects.build_great_forge.blurb_maxed", [[The Great Forge is complete.]])
--The big banner when the last roll finishes it, and the line under it.
text("downtime.projects.build_great_forge.complete_banner", [[The Great Forge!]])
text("downtime.projects.build_great_forge.complete_subtitle", [[The Great Forge, built by the Heroes of Blackbottom and the Tinkerer's Guild.]])

----------------------------------------------------------------------------
-- THE PROJECT: its two stages
----------------------------------------------------------------------------

--The two stages' names (1-2 words each).
text("downtime.projects.build_great_forge.stage_planning", [[Planning]])
text("downtime.projects.build_great_forge.stage_building", [[Building]])
--Replaces the project's blurb during each stage.
text("downtime.projects.build_great_forge.stage_planning_blurb", [[The Tinkerer's Guild needs leaders, architects and mages to plan the Great Forge: Presence or Reason.]])
text("downtime.projects.build_great_forge.stage_building_blurb", [[The plans are drawn. Now the Great Forge must be built: Might or Agility.]])
--The banner shown to the hero whose roll finishes the planning, and the
--line under it.
text("downtime.projects.build_great_forge.stage_banner", [[The Plans Are Drawn!]])
text("downtime.projects.build_great_forge.stage_subtitle", [[The Great Forge goes up!]])

----------------------------------------------------------------------------
-- DISCORD: the building's name on the town's progress posts
----------------------------------------------------------------------------

--As it reads in the middle of a sentence: "Work on ___ is 50% done". The
--server writes these cards, so this name lives in its code, not here:
--cloudflare-game-server/src/discord-core.ts, COMMUNITY_PROJECT_NAMES
--("the Great Forge").

----------------------------------------------------------------------------
-- THE PROJECT: what heroes say after a roll
----------------------------------------------------------------------------

--Chosen by how far along the project is and how the roll went (hopeful: a
--good roll; neutral; frustrated: a poor roll). Three lines each; a line said
--recently is not repeated while another is left.
--
--Only the planning half is rolled for: at half way the siege begins and
--the rest is won in combat, so there are no building or finishing lines.

--Planning, first half (points 0-2499): what the planners, leaders and mages
--are doing with the gnomes of the Tinkerer's Guild.
text("downtime.lines.great_forge.planning_early_hopeful_1", [[The Forge is getting off to a great start. I can feel the energy here!]])
text("downtime.lines.great_forge.planning_early_hopeful_2", [[Another day or two of good hard work like this and our Forge won't be too far off!]])
text("downtime.lines.great_forge.planning_early_hopeful_3", [[The Gnomes aren't so bad to work with. They do like their tinkering!]])
text("downtime.lines.great_forge.planning_early_neutral_1", [[A good start, a good start on the Forge. I just wonder how long it will all take?]])
text("downtime.lines.great_forge.planning_early_neutral_2", [[How many Gnomish Tinkerers does a Forge take to build, anyhow?]])
text("downtime.lines.great_forge.planning_early_neutral_3", [[Let's plan it all out, one stone at a time.]])
text("downtime.lines.great_forge.planning_early_frustrated_1", [[The way those Gnomes giggle and cackle. It does get annoying after a while!]])
text("downtime.lines.great_forge.planning_early_frustrated_2", [[This Forge will be a place for great treasures to be made. Yet something about it leaves me with a foreboding sense.]])
text("downtime.lines.great_forge.planning_early_frustrated_3", [[I tried to work hard, but it's all giving me a headache. I wonder if being close to so much magic does that?]])

--Planning, second half (points 2500-4999).
text("downtime.lines.great_forge.planning_late_hopeful_1", [[I can feel the energy in this place. This Forge is going to be a place like no other!]])
text("downtime.lines.great_forge.planning_late_hopeful_2", [[I wonder why the Tinkerers insisted on the magic gemstones going in this pattern. Like a portal to another place...]])
text("downtime.lines.great_forge.planning_late_hopeful_3", [[On we go, I can't wait to craft items of great power here.]])
text("downtime.lines.great_forge.planning_late_neutral_1", [[Another day, another room planned. We'll get to craft our items one day!]])
text("downtime.lines.great_forge.planning_late_neutral_2", [[All the magic in this place is a little dizzying! It's hard to think straight.]])
text("downtime.lines.great_forge.planning_late_neutral_3", [[I'm not sure I ever realized working with the Tinkerer's Guild would be so complicated!]])
text("downtime.lines.great_forge.planning_late_frustrated_1", [[I just wish I had a clue what the Gnomes were jabbering about...]])
text("downtime.lines.great_forge.planning_late_frustrated_2", [[Working with a bunch of Gnomish Tinkerers isn't exactly going well now, is it?]])
text("downtime.lines.great_forge.planning_late_frustrated_3", [[I hope this all works out. I feel a sense of foreboding with all the magic here...]])

----------------------------------------------------------------------------
-- GIDDLEBRICK: the first visit, while the Forge is being planned
----------------------------------------------------------------------------

--Lines 1-7 are David's words (2026-11-15), as given. The hero answering is
--one of the player's heroes at home, chosen at random.

--His name and title over his lines ("{name}, {title}").
text("great_forge.giddlebrick.name", [[Giddlebrick Thundlestrom]])
text("great_forge.giddlebrick.title", [[Tinkerer's Guild]])

text("great_forge.intro.line1_npc", [[Well hello there! I'm Giddlebrick Thundlestrom head of the Blackbottom Chapter of the Tinkerer's Guild. You must be here to help with construction of the Forge.]])
text("great_forge.intro.line2_hero", [[Why yes, yes I am. How shall we get started?]])
text("great_forge.intro.line3_npc", [[Eager to get into it, nice to see it! Now, you must understand that we are the Tinkerer's Guild have chosen this location specifically for the Forge. The most powerful treasures in all the land will be forged here, my friend!]])
text("great_forge.intro.line4_hero", [[Oh, why is that? What's so special about this place?]])
text("great_forge.intro.line5_npc", [[Oh this is a magical place my friend. Right here we are standing on a spot where planes converge. Took a lot of measuring and the right amount of divination to determine that, let me tell you! But here, the planes come together, and magical energy from other realms seeps into our own. All the better to craft the best treasures with!]])
--The hero's answer: a Fury, Tactician or Beastheart...
text("great_forge.intro.line6_hero_martial", [[Magical energy? I'll just have to take your word for it.]])
--...a hero trained in Magic, or an Elementalist...
text("great_forge.intro.line6_hero_magic", [[I do think you might be onto something. I sense something special about this place.]])
--...anyone else.
text("great_forge.intro.line6_hero", [[Interesting. How can I help to start building?]])
text("great_forge.intro.line7_npc", [[Well, we are still in the planning phase, but there is much to do, I'm sure that you can help lead some of the workers in putting the forge together. Why don't you get started?]])

----------------------------------------------------------------------------
-- THE SIEGE: from half way, demons attack the Forge
----------------------------------------------------------------------------

--DRAFTS (2026-11-15) except where noted. The tagline and the banner's
--subtitle are David's words.

--The location's heading during the siege.
text("eotw.locations.great_forge_siege.title", [[The Great Forge Under Siege]])
text("eotw.locations.great_forge_siege.tagline", [[While building the forge a portal has opened to another realm and demons are attacking Blackbottom!]])

--The moment the portal opens, played once to each player: to whoever is at
--the Forge when it happens, and to everyone else the first time they visit
--after. Their leading hero (the one whose roll opened it, else their first
--hero in town) speaks; a demon (a Ruinant) and Giddlebrick join in. The four
--spoken lines are David's words; the demon's name and title are DRAFTS.
--Said only by a hero who arrives to find it (the demons interrupt them):
text("great_forge.siege_event.hero_arrive", [[Let's work on building this for...]])
text("great_forge.siege_event.demon", [[Mortals, die!]])
text("great_forge.siege_event.giddlebrick", [[Demons? We must have delved too close. A portal has opened to an abyssal realm!]])
text("great_forge.siege_event.hero_defend", [[The Forge and Blackbottom must be defended!]])
--The demon's name plate over its lines (name, then title).
text("great_forge.siege_event.demon_name", [[Ruinant]])
text("great_forge.siege_event.demon_title", [[Demon]])

--The banner after that moment (and, if it cannot play, on its own).
text("downtime.projects.build_great_forge.siege_banner", [[Demons Attack!]])
text("downtime.projects.build_great_forge.siege_subtitle", [[While building the forge a portal has opened to another realm and demons are attacking Blackbottom!]])

--The project's line during the siege, and why no one can roll on it.
text("downtime.projects.build_great_forge.siege_blurb", [[Demons pour out of a portal at the Forge. Only defending it will finish the build.]])
text("downtime.projects.build_great_forge.siege_rolls_closed", [[No work can be done while demons attack the Forge. Win the fight on the Forge's board to add Project Points.]])

--The fight's party board (the card on the right).
text("eotw.forge.board_title", [[Defend the Forge]])
text("eotw.forge.siege_note", [[Drive the demons back! Each difficulty you win adds its Project Points to the Forge once for each player.]])
text("eotw.forge.defend_title", [[The Fight]])
--Under each difficulty: what it is worth, {points} being "20 Project Points".
text("eotw.forge.row_points", [[Worth {points}]])
text("eotw.forge.row_normal", [[Win to unlock Challenge Mode.]])
text("eotw.forge.row_challenge", [[An especially lethal fight. Win to unlock Deadly Mode.]])
text("eotw.forge.row_deadly", [[Challenge Mode applied twice. Its victors are honored first when the Forge is complete.]])
text("eotw.forge.row_earned", [[You have earned these points. You can still fight to help others earn theirs.]])
text("eotw.forge.row_locked_challenge", [[Win on Normal to unlock.]])
text("eotw.forge.row_locked_deadly", [[Win in Challenge Mode to unlock.]])
--The button on each unlocked difficulty. Short: a button.
text("eotw.forge.form_party_button", [[Form a Party]])
text("eotw.forge.no_parties", [[No one is defending the Forge right now. Form a party and others can join you!]])

----------------------------------------------------------------------------
-- THE BUILT FORGE
----------------------------------------------------------------------------
--Everything at the built Forge (Giddlebrick's greeting and negotiation, the
--workshop) is in EotwTextForgeNegotiation.lua.
